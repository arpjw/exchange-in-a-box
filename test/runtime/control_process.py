"""Terminal control room smoke tests, including prompt-before-EOF behavior."""
import os
from pathlib import Path
import select
import subprocess
import sys
import time


def read_prompt(process: subprocess.Popen) -> bytes:
    output = bytearray()
    deadline = time.monotonic() + 10
    while not output.endswith(b"exchange> "):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("control-room prompt timeout")
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        if not ready:
            raise RuntimeError("control-room prompt timeout")
        chunk = os.read(process.stdout.fileno(), 65536)
        if not chunk:
            raise RuntimeError("unexpected EOF before prompt")
        output.extend(chunk)
    return bytes(output)


def main() -> None:
    executable = str(Path(sys.argv[1]).resolve())
    commands = "\n".join([
        "status", "place 0 1 buy 99 10 gtc", "place 1 2 sell 101 10 post", "book",
        "place 0 3 buy 101 5 ioc", "accounts", "quote", "scenario 42 100 4 250", "quote",
        "halt 0", "place 0 4 buy 98 1 gtc", "resume 0", "book 0", "scenario 1 100001",
        "unknown", "status", "quit", "place 0 5 buy 98 1 gtc", ""])
    first = subprocess.run([executable, "--accounts", "3", "--batch"], input=commands,
                           text=True, capture_output=True, check=True, timeout=30)
    second = subprocess.run([executable, "--accounts", "3", "--batch"], input=commands,
                            text=True, capture_output=True, check=True, timeout=30)
    assert first.stdout == second.stdout and first.stderr == ""
    output = first.stdout
    assert "BIDS\n" in output and "ASKS\n" in output
    assert "MAX_ORDER_NOTIONAL" in output and "POSITION" in output
    assert '"quantity":5' in output
    assert '"reason":"halted"' in output
    assert 'SCENARIO complete {"seed":42,"events":100' in output
    assert '"impact_cost_ticks_lots":450' in output
    assert output.count("QUOTE revision=2 bid=99 x 10 ask=101 x 5") == 3
    assert "ERROR: book depth must be 1..100" in output
    assert "ERROR: scenario SEED EVENTS" in output
    assert "ERROR: unknown command" in output
    assert "commands=6 accounts=3 resting_bids=0 resting_asks=1 accepted_ids=3" in output
    assert output.endswith("Session closed.\n")
    process = subprocess.Popen([executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    try:
        startup = read_prompt(process)
        assert b"Local exchange research control room" in startup
        process.stdin.write(b"quote\n")
        process.stdin.flush()
        assert b"two-sided book required" in read_prompt(process)
        process.stdin.close()
        assert process.wait(timeout=10) == 0
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    print("control room: deterministic batch, depth, risk, scenario isolation, prompts and EOF passed")


if __name__ == "__main__":
    main()
