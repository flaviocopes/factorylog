#!/usr/bin/env python3

import argparse
import hashlib
import os
import shutil
import subprocess
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, tzinfo
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_WORK_LOG = Path.home() / ".cursor" / "work-log.txt"


def system_time_zone() -> tzinfo:
    if configured := os.environ.get("TZ"):
        return ZoneInfo(configured)

    localtime = Path("/etc/localtime").resolve()
    marker = "zoneinfo/"
    if marker in str(localtime):
        return ZoneInfo(str(localtime).split(marker, 1)[1])

    return datetime.now().astimezone().tzinfo or ZoneInfo("UTC")


@dataclass(frozen=True)
class WorkEntry:
    day: date
    project: str
    at: time
    summary: str

    def timestamp(self, time_zone: tzinfo) -> datetime:
        return datetime.combine(self.day, self.at, tzinfo=time_zone)


def parse_args() -> argparse.Namespace:
    local_time_zone = system_time_zone()
    today = datetime.now(local_time_zone).date()
    parser = argparse.ArgumentParser(description="Import the Codex text work log into Factory Log.")
    parser.add_argument("--from-date", type=date.fromisoformat, default=today - timedelta(days=3))
    parser.add_argument("--through-date", type=date.fromisoformat, default=today)
    parser.add_argument("--log", type=Path, default=DEFAULT_WORK_LOG)
    parser.add_argument("--factorylog", type=Path)
    parser.add_argument("--store", type=Path)
    parser.add_argument("--timezone", help="IANA time zone for log entries; defaults to the system zone")
    parser.add_argument(
        "--project-root",
        action="append",
        type=Path,
        help="Directory to search for project folders; may be repeated",
    )
    parser.add_argument(
        "--project-map",
        action="append",
        default=[],
        metavar="NAME=/ABSOLUTE/PATH",
        help="Explicit project-name mapping; may be repeated",
    )
    return parser.parse_args()


def parse_work_log(path: Path) -> list[WorkEntry]:
    entries: list[WorkEntry] = []
    current_day: date | None = None
    current_project: str | None = None

    for line in path.read_text().splitlines():
        if line.startswith("[") and line.endswith("]"):
            current_day = date.fromisoformat(line[1:-1])
            current_project = None
            continue

        if line.startswith("  ") and not line.startswith("    "):
            current_project = line.strip()
            continue

        if line.startswith("    ") and current_day and current_project:
            value = line.strip()
            time_value, separator, summary = value.partition(" - ")
            if separator:
                entries.append(
                    WorkEntry(
                        day=current_day,
                        project=current_project,
                        at=time.fromisoformat(time_value),
                        summary=summary,
                    )
                )

    return entries


def factorylog_path(explicit_path: Path | None) -> Path:
    if explicit_path:
        return explicit_path

    installed = shutil.which("factorylog")
    if installed:
        return Path(installed)

    return ROOT / ".build" / "release" / "factorylog"


def parse_project_maps(values: list[str]) -> dict[str, Path]:
    mappings: dict[str, Path] = {}
    for value in values:
        name, separator, raw_path = value.partition("=")
        path = Path(raw_path).expanduser()
        if not separator or not name or not path.is_absolute():
            raise SystemExit(f"Invalid --project-map '{value}'. Use NAME=/absolute/path.")
        mappings[name] = path
    return mappings


def project_details(
    project: str,
    roots: list[Path],
    mappings: dict[str, Path],
) -> tuple[str, Path]:
    if project in mappings:
        return project, mappings[project]

    direct = Path(project).expanduser()
    if direct.is_absolute() and direct.exists():
        return direct.name, direct

    for base in roots:
        candidate = base / project
        if candidate.exists():
            return project, candidate

    raise RuntimeError(
        f"Could not locate project '{project}'. Add --project-root or "
        f"--project-map '{project}=/absolute/path'."
    )


def task_id(day: date, project: str) -> str:
    digest = hashlib.sha256(f"{day.isoformat()}\0{project}".encode()).hexdigest()[:20]
    return f"backfill_{digest}"


def run_factorylog(
    executable: Path,
    command: str,
    task: str,
    summary: str,
    timestamp: datetime,
    store: Path | None,
    project: tuple[str, Path] | None = None,
) -> subprocess.CompletedProcess[str]:
    arguments = [
        str(executable),
        command,
        "--task-id",
        task,
        "--summary",
        summary,
        "--timestamp",
        timestamp.isoformat(timespec="seconds"),
    ]

    if command == "start" and project:
        name, path = project
        arguments.extend(
            [
                "--title",
                f"{name} daily work",
                "--project-name",
                name,
                "--project-path",
                str(path),
                "--source",
                "codex",
                "--session-id",
                "work-log-backfill",
            ]
        )

    if store:
        arguments.extend(["--store", str(store)])

    return subprocess.run(arguments, capture_output=True, text=True, check=False)


def import_group(
    executable: Path,
    entries: list[WorkEntry],
    store: Path | None,
    time_zone: tzinfo,
    project_roots: list[Path],
    project_mappings: dict[str, Path],
) -> bool:
    entries.sort(key=lambda entry: entry.at)
    first = entries[0]
    task = task_id(first.day, first.project)
    project = project_details(first.project, project_roots, project_mappings)

    if len(entries) == 1:
        start_time = first.timestamp(time_zone) - timedelta(seconds=1)
        start_summary = "Started the recorded work."
    else:
        start_time = first.timestamp(time_zone)
        start_summary = first.summary

    result = run_factorylog(
        executable,
        "start",
        task,
        start_summary,
        start_time,
        store,
        project,
    )
    if result.returncode != 0:
        if "already exists" in result.stderr:
            return False
        raise RuntimeError(result.stderr.strip())

    for entry in entries[1:-1]:
        result = run_factorylog(
            executable,
            "report",
            task,
            entry.summary,
            entry.timestamp(time_zone),
            store,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip())

    final = entries[-1]
    result = run_factorylog(
        executable,
        "archive",
        task,
        final.summary,
        final.timestamp(time_zone),
        store,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return True


def main() -> None:
    args = parse_args()
    time_zone = ZoneInfo(args.timezone) if args.timezone else system_time_zone()
    project_roots = [path.expanduser() for path in (args.project_root or [
        Path.home() / "www",
        Path.home() / "dev",
        Path.home() / "Documents",
    ])]
    project_mappings = parse_project_maps(args.project_map)
    executable = factorylog_path(args.factorylog)
    if not executable.exists():
        raise SystemExit("Factory Log CLI not found. Run zsh Scripts/install-cli.zsh first.")

    selected = [
        entry
        for entry in parse_work_log(args.log)
        if args.from_date <= entry.day <= args.through_date
    ]
    grouped: dict[tuple[date, str], list[WorkEntry]] = defaultdict(list)
    for entry in selected:
        grouped[(entry.day, entry.project)].append(entry)

    imported = 0
    skipped = 0
    for key in sorted(grouped):
        if import_group(
            executable,
            grouped[key],
            args.store,
            time_zone,
            project_roots,
            project_mappings,
        ):
            imported += 1
        else:
            skipped += 1

    print(
        f"Imported {imported} project-day threads and skipped {skipped} existing threads "
        f"from {args.from_date} through {args.through_date}."
    )


if __name__ == "__main__":
    main()
