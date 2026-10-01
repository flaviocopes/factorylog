#!/usr/bin/env python3

import argparse
import json
import statistics
import subprocess
import tempfile
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Measure Factory Log write latency on a long history.")
    parser.add_argument("--cli", type=Path, default=Path(".build/release/factorylog"))
    parser.add_argument("--events", type=int, default=10_000)
    parser.add_argument("--reports", type=int, default=5)
    return parser.parse_args()


def event(index: int, timestamp: datetime) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "id": f"benchmark-{index}",
        "taskID": "benchmark-task",
        "timestamp": timestamp.isoformat().replace("+00:00", "Z"),
        "kind": "task.started" if index == 0 else "task.reported",
        "project": {"name": "Benchmark", "path": "/tmp/factory-log-benchmark"},
        "taskTitle": "Benchmark event store",
        "source": {"tool": "other"},
        "summary": f"Benchmark event {index}",
    }


def main() -> None:
    args = parse_args()
    if args.events < 1 or args.reports < 1:
        raise SystemExit("--events and --reports must be positive")
    if not args.cli.is_file():
        raise SystemExit(f"CLI not found: {args.cli}")

    with tempfile.TemporaryDirectory() as directory:
        store = Path(directory) / "events.jsonl"
        started = datetime(2026, 1, 1, tzinfo=UTC)
        with store.open("w", encoding="utf-8") as file:
            for index in range(args.events):
                file.write(json.dumps(event(index, started + timedelta(seconds=index))) + "\n")

        samples: list[float] = []
        for index in range(args.reports):
            before = time.perf_counter()
            result = subprocess.run(
                [
                    str(args.cli.resolve()),
                    "report",
                    "--task-id",
                    "benchmark-task",
                    "--summary",
                    f"Measured report {index}",
                    "--store",
                    str(store),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                raise SystemExit(result.stderr.strip())
            samples.append((time.perf_counter() - before) * 1_000)

        print(
            f"event_store events={args.events} reports={args.reports} "
            f"median_ms={statistics.median(samples):.1f} max_ms={max(samples):.1f}"
        )


if __name__ == "__main__":
    main()
