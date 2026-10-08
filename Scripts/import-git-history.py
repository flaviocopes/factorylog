#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
HOME = Path.home()
DEFAULT_STORE = HOME / "Library" / "Application Support" / "Factory Log" / "events.jsonl"
CURSOR_AGENT = HOME / ".local" / "bin" / "cursor-agent"
CURSOR_AGENT_EMAIL = "cursoragent@cursor.com"
AUTO_ARCHIVE_PREFIX = "Automatically marked Done"
COVERAGE_MARGIN = timedelta(minutes=15)
FIELD = "\x1f"
SKIPPED_DIRECTORIES = {"node_modules", ".build", "dist", "build", "vendor", ".venv"}
COMMIT_PREFIX = re.compile(r"^[a-z-]+(\([^)]*\))?:\s*")
PULL_REQUEST_SUFFIX = re.compile(r"\s*\(#\d+\)$")


@dataclass(frozen=True)
class Commit:
    repo: Path
    sha: str
    at: datetime
    email: str
    subject: str


@dataclass
class Session:
    repo: Path
    commits: list[Commit]
    source: str = "cursor"
    title: str = ""
    updates: list[str] = field(default_factory=list)


def parse_args() -> argparse.Namespace:
    today = datetime.now().astimezone().date()
    parser = argparse.ArgumentParser(description="Backfill Work Tracebook from local Git history.")
    parser.add_argument("--from-date", type=date.fromisoformat, default=today - timedelta(days=21))
    parser.add_argument("--through-date", type=date.fromisoformat, default=today)
    parser.add_argument(
        "--root",
        action="append",
        type=Path,
        help="Directory to search for repositories; may be repeated",
    )
    parser.add_argument(
        "--author",
        action="append",
        help="Commit author email to include; defaults to your Git email and Cursor Agent",
    )
    parser.add_argument("--gap-minutes", type=int, default=45)
    parser.add_argument("--model", default=os.environ.get("FACTORYLOG_MODEL", "composer-2.5"))
    parser.add_argument("--no-titles", action="store_true", help="Skip the model and reuse commit subjects")
    parser.add_argument("--factorylog", type=Path)
    parser.add_argument("--store", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def find_repositories(roots: list[Path], max_depth: int = 4) -> list[Path]:
    repositories: list[Path] = []
    for root in roots:
        if not root.is_dir():
            continue
        base_depth = len(root.parts)
        for current, directories, _ in os.walk(root):
            path = Path(current)
            if (path / ".git").is_dir():
                repositories.append(path)
                directories.clear()
                continue
            if len(path.parts) - base_depth >= max_depth:
                directories.clear()
                continue
            directories[:] = [
                name for name in directories
                if not name.startswith(".") and name not in SKIPPED_DIRECTORIES
            ]
    return sorted(repositories)


def git(repo: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(repo), *arguments], capture_output=True, text=True, check=False)


def load_commits(repo: Path, start: datetime, end: datetime, authors: set[str]) -> list[Commit]:
    # Local branches plus the remote default branch: unmerged agent branches would
    # duplicate the squash commits that land on main.
    refs = ["--branches"]
    if git(repo, "rev-parse", "-q", "--verify", "refs/remotes/origin/HEAD").returncode == 0:
        refs.append("refs/remotes/origin/HEAD")

    result = git(
        repo,
        "log",
        *refs,
        "--no-merges",
        f"--since={start.isoformat()}",
        f"--until={end.isoformat()}",
        f"--format=%H{FIELD}%aI{FIELD}%ae{FIELD}%(trailers:key=Co-authored-by,valueonly,separator=%x2C){FIELD}%s",
    )
    commits: list[Commit] = []
    for line in result.stdout.splitlines():
        sha, stamp, email, co_authors, subject = line.split(FIELD, 4)
        if email.lower() not in authors:
            continue
        if CURSOR_AGENT_EMAIL in co_authors.lower():
            email = CURSOR_AGENT_EMAIL
        at = datetime.fromisoformat(stamp)
        if start <= at <= end:
            commits.append(Commit(repo, sha, at, email.lower(), subject.strip()))
    return commits


def parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def coverage_spans(store: Path) -> dict[str, list[tuple[datetime, datetime]]]:
    """Time spans already described by existing tasks, keyed by project path.

    Open tasks cover everything up to now, because their live reports will
    describe the rest of that work.
    """
    tasks: dict[str, list[dict]] = {}
    if store.exists():
        for line in store.read_text().splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            tasks.setdefault(event["taskID"], []).append(event)

    now = datetime.now(timezone.utc)
    spans: dict[str, list[tuple[datetime, datetime]]] = {}
    for events in tasks.values():
        written = [event for event in events if not event["summary"].startswith(AUTO_ARCHIVE_PREFIX)]
        if not written:
            continue
        stamps = [parse_timestamp(event["timestamp"]) for event in written]
        is_open = not any(event["kind"] == "task.archived" for event in events)
        end = now if is_open else max(stamps) + COVERAGE_MARGIN
        path = str(Path(events[0]["project"]["path"]).resolve())
        spans.setdefault(path, []).append((min(stamps) - COVERAGE_MARGIN, end))
    return spans


def codex_sessions() -> dict[str, list[tuple[datetime, datetime]]]:
    """Codex session windows keyed by working directory."""
    files = list((HOME / ".codex" / "sessions").rglob("*.jsonl"))
    files += list((HOME / ".codex" / "archived_sessions").glob("*.jsonl"))
    sessions: dict[str, list[tuple[datetime, datetime]]] = {}
    for path in files:
        try:
            with path.open() as handle:
                meta = json.loads(handle.readline()).get("payload", {})
            started = parse_timestamp(meta["timestamp"])
            ended = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            continue
        cwd = meta.get("cwd")
        if isinstance(cwd, str):
            sessions.setdefault(str(Path(cwd).resolve()), []).append((started, ended))
    return sessions


def within(moment: datetime, spans: list[tuple[datetime, datetime]]) -> bool:
    return any(start <= moment <= end for start, end in spans)


def group_sessions(commits: list[Commit], gap: timedelta) -> list[Session]:
    sessions: list[Session] = []
    for commit in sorted(commits, key=lambda item: (str(item.repo), item.at)):
        if sessions:
            previous = sessions[-1].commits[-1]
            same_day = previous.at.astimezone().date() == commit.at.astimezone().date()
            if previous.repo == commit.repo and same_day and commit.at - previous.at <= gap:
                sessions[-1].commits.append(commit)
                continue
        sessions.append(Session(commit.repo, [commit]))
    return sessions


def clean_subject(subject: str) -> str:
    text = PULL_REQUEST_SUFFIX.sub("", COMMIT_PREFIX.sub("", subject)).strip()
    return text[:1].upper() + text[1:] if text else subject


TITLE_PROMPT = """You are writing entries for an engineering work log.

Below are the Git commit subjects from one work session in the project \
"{project}", oldest first. Reply with ONLY a JSON object, no prose and no code \
fences, in exactly this shape:

{{"title": "...", "updates": ["...", "..."]}}

Rules:
- title: under 60 characters, names the main work of the session, no trailing period.
- updates: exactly {count} strings, one per commit, in the same order.
- Rewrite each subject as one short, plain, past-tense sentence, like \
"Drafted a post about SSH apps." Drop prefixes such as "post:" or "fix:" but \
keep what they meant.
- Keep names, numbers, and dates. Never add facts that are not in the subject.

Commits:
{commits}"""


def extract_json(text: str) -> dict | None:
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        value = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def describe(session: Session, model: str | None, workspace: Path) -> None:
    session.title = clean_subject(session.commits[0].subject)[:120]
    session.updates = [clean_subject(commit.subject) for commit in session.commits]
    if model is None or not CURSOR_AGENT.exists():
        return

    listing = "\n".join(
        f"{index}. {PULL_REQUEST_SUFFIX.sub('', commit.subject)}"
        for index, commit in enumerate(session.commits, start=1)
    )
    prompt = TITLE_PROMPT.format(project=session.repo.name, count=len(session.commits), commits=listing)
    environment = dict(os.environ, FACTORYLOG_HOOK_DISABLED="1")
    try:
        result = subprocess.run(
            [
                str(CURSOR_AGENT),
                "--print",
                "--output-format",
                "text",
                "--mode",
                "ask",
                "--model",
                model,
                "--trust",
                "--workspace",
                str(workspace),
                prompt,
            ],
            capture_output=True,
            text=True,
            timeout=240,
            check=False,
            env=environment,
            cwd=str(workspace),
        )
    except (subprocess.TimeoutExpired, OSError):
        return

    parsed = extract_json(result.stdout) if result.returncode == 0 else None
    if not parsed:
        return
    title = str(parsed.get("title", "")).strip().rstrip(".")
    updates = parsed.get("updates")
    if title:
        session.title = title[:120]
    if isinstance(updates, list) and len(updates) == len(session.commits):
        texts = [str(update).strip() for update in updates]
        if all(texts):
            session.updates = [text[:600] for text in texts]


def task_id(session: Session) -> str:
    digest = hashlib.sha256(f"{session.repo}\0{session.commits[0].sha}".encode()).hexdigest()[:20]
    return f"gitbackfill_{digest}"


def factorylog_path(explicit_path: Path | None) -> Path:
    if explicit_path:
        return explicit_path
    installed = shutil.which("factorylog")
    return Path(installed) if installed else ROOT / ".build" / "release" / "factorylog"


def run_factorylog(executable: Path, store: Path | None, *arguments: str) -> subprocess.CompletedProcess[str]:
    command = [str(executable), *arguments]
    if store:
        command.extend(["--store", str(store)])
    return subprocess.run(command, capture_output=True, text=True, check=False)


def import_session(executable: Path, store: Path | None, session: Session) -> bool:
    task = task_id(session)
    commits = session.commits
    stamps = [commit.at.isoformat(timespec="seconds") for commit in commits]
    start_stamp = stamps[0]
    if len(commits) == 1:
        start_stamp = (commits[0].at - timedelta(seconds=1)).isoformat(timespec="seconds")

    result = run_factorylog(
        executable,
        store,
        "start",
        "--task-id", task,
        "--title", session.title,
        "--summary", session.updates[0],
        "--timestamp", start_stamp,
        "--project-name", session.repo.name,
        "--project-path", str(session.repo),
        "--source", session.source,
        "--session-id", "git-backfill",
    )
    if result.returncode != 0:
        if "already exists" in result.stderr:
            return False
        raise RuntimeError(result.stderr.strip())

    steps = [("report", index) for index in range(1, len(commits) - 1)]
    steps.append(("archive", len(commits) - 1))
    for command, index in steps:
        result = run_factorylog(
            executable,
            store,
            command,
            "--task-id", task,
            "--summary", session.updates[index],
            "--timestamp", stamps[index],
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip())
    return True


def main() -> None:
    args = parse_args()
    local_zone = datetime.now().astimezone().tzinfo
    start = datetime.combine(args.from_date, time.min, tzinfo=local_zone)
    end = min(datetime.combine(args.through_date, time.max, tzinfo=local_zone), datetime.now(timezone.utc))
    roots = [path.expanduser() for path in (args.root or [HOME / "www", HOME / "dev", HOME / "Documents"])]

    authors = {email.lower() for email in (args.author or [])}
    if not authors:
        configured = subprocess.run(["git", "config", "--global", "user.email"], capture_output=True, text=True)
        authors = {configured.stdout.strip().lower(), CURSOR_AGENT_EMAIL} - {""}

    executable = factorylog_path(args.factorylog)
    if not args.dry_run and not executable.exists():
        raise SystemExit("Work Tracebook CLI not found. Run zsh Scripts/install-cli.zsh first.")

    covered = coverage_spans(args.store or DEFAULT_STORE)
    codex = codex_sessions()
    commits: list[Commit] = []
    skipped = 0
    for repo in find_repositories(roots):
        for commit in load_commits(repo, start, end, authors):
            if within(commit.at, covered.get(str(repo.resolve()), [])):
                skipped += 1
            else:
                commits.append(commit)

    sessions = group_sessions(commits, timedelta(minutes=args.gap_minutes))
    for session in sessions:
        in_codex = all(within(commit.at, codex.get(str(session.repo.resolve()), [])) for commit in session.commits)
        by_agent = any(commit.email == CURSOR_AGENT_EMAIL for commit in session.commits)
        session.source = "codex" if in_codex and not by_agent else "cursor"

    model = None if args.no_titles else args.model
    with tempfile.TemporaryDirectory() as workspace, ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(lambda session: describe(session, model, Path(workspace)), sessions))

    imported = 0
    existing = 0
    for session in sorted(sessions, key=lambda item: item.commits[0].at):
        first = session.commits[0].at.astimezone()
        print(f"{first:%Y-%m-%d %H:%M}  {session.repo.name:<24} {len(session.commits):>3}  {session.source:<6}  {session.title}")
        if args.dry_run:
            continue
        if import_session(executable, args.store, session):
            imported += 1
        else:
            existing += 1

    if args.dry_run:
        print(f"Would import {len(sessions)} sessions ({len(commits)} commits).", end=" ")
    else:
        print(f"Imported {imported} sessions and skipped {existing} existing ones.", end=" ")
    print(
        f"Skipped {skipped} commits already covered by tasks, "
        f"from {args.from_date} through {args.through_date}."
    )


if __name__ == "__main__":
    main()
