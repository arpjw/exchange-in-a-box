#!/usr/bin/env python3
"""Run bounded reproducibility stress; any child failure fails the gate."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time


def main() -> None:
    executable = str(Path(sys.argv[1]).resolve())
    seeds, events = int(sys.argv[2]), int(sys.argv[3])
    if not (1 <= seeds <= 1000 and 0 <= events <= 10_000_000):
        raise SystemExit("invalid stress seed or event count")
    worker = str(Path(executable).with_name("worker.exe"))
    protocol = "\n".join([
        "place 0 1 buy 99 10 gtc", "place 1 2 sell 101 10 gtc", "quote",
        "place 0 3 buy 101 5 ioc", "accounts", "bogus", "halt 0", "quote", ""])
    process = subprocess.run([worker], input=protocol, text=True, capture_output=True, check=True, timeout=30)
    responses = [json.loads(line) for line in process.stdout.splitlines()]
    assert len(responses) == 8
    assert responses[2]["quote"]["bid"] == 99
    assert responses[3]["trades"][0]["quantity"] == 5
    assert sum(a["position"] for a in responses[4]["accounts"]) == 0
    assert sum(int(a["cash"]) for a in responses[4]["accounts"]) == 0
    assert responses[5]["reason"] == "invalid_command"
    assert responses[7]["quote"] is None
    print("worker protocol: subprocess/EOF, quotes, fills, conservation, malformed input passed", flush=True)
    started = time.monotonic()
    digest = hashlib.sha256()
    total_volume = 0
    for seed in range(seeds):
        command = [executable, "--seed", str(seed), "--events", str(events),
                   "--agents", "24", "--impact-lots", str(250 if seed % 2 else 0)]
        first = subprocess.run(command, check=True, capture_output=True, timeout=300).stdout
        second = subprocess.run(command, check=True, capture_output=True, timeout=300).stdout
        if first != second:
            raise RuntimeError(f"nondeterministic run at seed {seed}")
        result = json.loads(first)
        assert result["seed"] == seed and result["events"] == events
        assert result["volume"] >= 0 and result["fills"] >= 0
        assert result["impact_cost_ticks_lots"] == (450 if seed % 2 else 0)
        total_volume += result["volume"]
        digest.update(first)
        print(f"seed={seed} events={events} replay=identical volume={result['volume']}", flush=True)
    print(json.dumps({"stress": "passed", "seeds": seeds, "events_per_run": events,
                      "total_events": seeds * events * 2, "volume_first_runs": total_volume,
                      "sha256": digest.hexdigest(), "elapsed_seconds": round(time.monotonic() - started, 3)}))


if __name__ == "__main__":
    main()
