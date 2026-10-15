"""Real process checks for Async flushing, EOF, and parity with the pure gateway."""
import json
from pathlib import Path
import select
import subprocess
import sys


def run() -> None:
    synchronous, asynchronous = [str(Path(p).resolve()) for p in sys.argv[1:]]
    commands = ["place 0 1 buy 99 10 gtc", "place 1 2 sell 101 10 gtc", "quote",
                "place 1 3 sell 110 10 gtc", "quote", "place 0 4 buy 101 5 ioc",
                "quote", "cancel 1 2", "quote", "bogus", "accounts", "halt 0", "quote"]
    payload = "\n".join(commands + [""])
    expected = subprocess.run([synchronous], input=payload, text=True, capture_output=True,
                              check=True, timeout=30).stdout.splitlines()
    process = subprocess.Popen([asynchronous], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, bufsize=1)
    actual = []
    try:
        for command in commands:
            process.stdin.write(command + "\n")
            process.stdin.flush()
            ready, _, _ = select.select([process.stdout], [], [], 10)
            if not ready:
                raise RuntimeError(f"Async response not flushed before EOF: {command}")
            response = process.stdout.readline()
            assert response, "unexpected EOF"
            actual.append(response.rstrip("\n"))
        process.stdin.close()
        assert process.wait(timeout=10) == 0, process.stderr.read()
        assert actual == expected
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    parsed = [json.loads(line) for line in actual]
    assert parsed[2]["revision"] == 1 and parsed[4]["revision"] == 1
    assert parsed[6]["revision"] == 2 and parsed[8]["revision"] == 3
    assert parsed[-1]["quote"] is None and parsed[-1]["revision"] == 4
    bulk = ("quote\nbogus\naccounts\n" * 5000)
    a = subprocess.run([asynchronous], input=bulk, text=True, capture_output=True, check=True, timeout=30).stdout
    b = subprocess.run([synchronous], input=bulk, text=True, capture_output=True, check=True, timeout=30).stdout
    assert a == b and len(a.splitlines()) == 15000
    print("Async: live response flushing, Incremental quote parity, EOF and 15000-command streaming passed")


if __name__ == "__main__":
    run()
