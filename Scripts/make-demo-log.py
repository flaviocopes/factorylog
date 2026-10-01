#!/usr/bin/env python3
"""Writes four weeks of made-up agent work to an event log, for screenshots and demos.

    python3 Scripts/make-demo-log.py /tmp/factorylog-demo/events.jsonl

Every project, task and summary is invented, and the output is the same on
every run for a given day. Point the app at the file with FACTORYLOG_EVENTS_FILE.
"""

import json
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROJECTS = {
    "storefront": [
        ("Add the checkout summary", "Added an order summary step to checkout with taxes and shipping shown before payment."),
        ("Fix the cart badge count", "Fixed the cart badge so it updates after items are removed from another tab."),
        ("Speed up product search", "Cached search results and cut the median query time from 420 ms to 90 ms."),
        ("Add gift cards", "Added gift card redemption at checkout with balance checks and partial payments."),
    ],
    "ios-app": [
        ("Offline reading list", "Saved articles now download in the background and open without a connection."),
        ("Fix the login redirect", "Fixed the sign-in flow so it returns to the screen that asked for it."),
        ("Widget for today's stats", "Added a Home Screen widget with today's reading time and streak."),
    ],
    "billing-api": [
        ("Add invoice exports", "Added CSV and PDF exports for invoices, with filters by date and customer."),
        ("Retry failed webhooks", "Failed payment webhooks now retry with backoff and land in a dead letter queue."),
        ("Usage-based pricing", "Added metered usage records and a monthly rollup job for usage-based plans."),
    ],
    "docs": [
        ("Write the onboarding guide", "Wrote a five-minute onboarding guide with screenshots for each setup step."),
        ("Document the webhooks API", "Documented every webhook event with payload examples and retry rules."),
    ],
    "design-system": [
        ("Dark mode tokens", "Added dark mode color tokens and switched every component to semantic colors."),
        ("Accessible focus rings", "Gave every interactive component a visible focus ring that passes contrast checks."),
    ],
    "data-pipeline": [
        ("Nightly backfill job", "Added a nightly job that backfills missed events from the last 48 hours."),
        ("Deduplicate signups", "Merged duplicate signup events by email and device before they reach the warehouse."),
    ],
    "marketing-site": [
        ("New pricing page", "Rebuilt the pricing page with a plan comparison table and annual billing toggle."),
        ("Launch post draft", "Drafted the launch post with the feature list and three customer quotes."),
    ],
}

WEIGHTS = {"storefront": 9, "ios-app": 6, "billing-api": 5, "docs": 3, "design-system": 3, "data-pipeline": 2, "marketing-site": 2}
TOOLS = ["codex", "cursor"]


def iso(moment):
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: make-demo-log.py <events.jsonl>")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)

    now = datetime.now().astimezone()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    rng = random.Random(today.strftime("%Y%m%d"))
    home = Path.home()
    names = list(PROJECTS)
    weights = [WEIGHTS[name] for name in names]
    events = []
    counter = 0

    for offset in range(27, -1, -1):
        day = today - timedelta(days=offset)
        weekend = day.weekday() >= 5
        if weekend and rng.random() < 0.6:
            continue
        hour = 8.5 + rng.random()
        # Today runs right up to now, so the screenshots show a working day in progress.
        sessions = 8 if offset == 0 else rng.randint(1, 2) if weekend else rng.randint(3, 5)
        used = set()
        for _ in range(sessions):
            start = day + timedelta(hours=hour)
            minutes = rng.randint(25, 140)
            end = start + timedelta(minutes=minutes)
            if end > now - timedelta(minutes=5):
                break
            while True:
                project = rng.choices(names, weights)[0]
                title, summary = rng.choice(PROJECTS[project])
                if title not in used:
                    break
            used.add(title)
            counter += 1
            task_id = f"demo-{counter}"
            tool = rng.choice(TOOLS)
            base = {
                "schemaVersion": 1,
                "taskID": task_id,
                "project": {"name": project, "path": str(home / "Projects" / project)},
                "taskTitle": title,
                "source": {"tool": tool},
            }
            # Today's last session stays open, so the screenshots show work in progress.
            still_open = offset == 0 and rng.random() < 0.5
            moment = start
            step = 0
            while moment < end:
                kind = "task.started" if step == 0 else "task.reported"
                text = f"Started: {title.lower()}." if step == 0 else summary
                events.append({**base, "id": f"{task_id}-{step}", "timestamp": iso(moment), "kind": kind, "summary": text})
                step += 1
                moment += timedelta(minutes=rng.randint(8, 24))
            if not still_open:
                events.append({**base, "id": f"{task_id}-{step}", "timestamp": iso(end), "kind": "task.archived", "summary": summary})
            hour += minutes / 60 + 0.3 + rng.random() * (0.6 if offset == 0 else 1.6)
            if hour > 19.5:
                break

    events.sort(key=lambda event: event["timestamp"])
    with output.open("w") as file:
        for event in events:
            file.write(json.dumps(event, sort_keys=True) + "\n")
    print(f"{len(events)} events in {output}")


if __name__ == "__main__":
    main()
