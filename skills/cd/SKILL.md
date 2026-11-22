---
name: cd
description: Inspect Python project entry points and add a guarded `--debugwait` seconds-based startup gate to CLI or service launch paths so a debugger can attach before application initialization. Use when the user explicitly says "cd" for code-debug startup work, "code debug", or "ce code debug", or asks to scan a program entry for debugging. Do not apply to ordinary cd directory-change commands.
metadata:
  short-description: Add an attach-friendly startup wait
---

# CD: Code Debug

Add an opt-in startup wait to each intended runtime entry point without changing
normal startup behavior.

## Contract

- Support `--debugwait <seconds>` and `--debugwait=<seconds>`.
- Default to `0`; accept finite, non-negative seconds, including decimals.
- Consume the option before the application's normal argument parser so it does
  not reject the flag.
- When the value is greater than zero, print the current PID to `stderr` and
  flush immediately, sleep once, then print that startup is continuing.
- Keep the wait at the earliest practical application-controlled boot point.
  Do not put it in request handlers, worker loops, or other repeated paths.
- Preserve existing launch behavior, help output, exit codes, and service
  wiring when the value is `0`.

## Workflow

1. Inspect manifests, launch scripts, and source entry points. From this
   skill's directory, start with the deterministic scanner:

   ```bash
   python scripts/scan_python_entries.py <project-root>
   ```

   Use `--json` when another tool needs structured output. Review its warnings
   and launch hints; they are candidates, not proof of the user's intended
   runtime path.

2. Identify the effective CLI and service processes. Do not stop at shell or
   package-runner wrappers when the debugger must attach to a child process.
   When several unrelated executables exist, determine which one the user is
   debugging before editing all of them.

3. Add one shared helper in the project's existing source layout. Call it at the
   beginning of each selected entry function, before parser construction and
   application setup.

4. For an externally managed service such as an ASGI/WSGI server that imports an
   application object, use or add a project-owned service launcher that consumes
   `--debugwait` before running the server. Do not assume the server forwards its
   own CLI arguments to the imported application.

5. Verify both paths:
   - With no flag or `--debugwait 0`, startup must behave as before.
   - With a short positive value, the process must print its PID immediately and
     remain alive until the wait completes.
   - With an invalid value, startup must fail with a concise error.

## Minimal Python Gate

Adapt names and placement to the project; keep the parsing and wait behavior
equivalent:

```python
from __future__ import annotations

import math
import os
import sys
import time


def apply_debugwait(argv: list[str]) -> list[str]:
    cleaned: list[str] = []
    value: str | None = None
    index = 0

    while index < len(argv):
        argument = argv[index]
        if argument == "--debugwait":
            if index + 1 >= len(argv):
                raise SystemExit("--debugwait requires a number of seconds")
            if value is not None:
                raise SystemExit("--debugwait may be specified only once")
            value = argv[index + 1]
            index += 2
            continue
        if argument.startswith("--debugwait="):
            if value is not None:
                raise SystemExit("--debugwait may be specified only once")
            value = argument.split("=", 1)[1]
            index += 1
            continue
        cleaned.append(argument)
        index += 1

    if value is None:
        return cleaned

    try:
        seconds = float(value)
    except ValueError as error:
        raise SystemExit(f"--debugwait must be a number, got {value!r}") from error
    if not math.isfinite(seconds) or seconds < 0:
        raise SystemExit("--debugwait must be a finite, non-negative number")

    if seconds > 0:
        print(
            f"[debugwait] pid={os.getpid()} waiting {seconds:g}s; attach now",
            file=sys.stderr,
            flush=True,
        )
        time.sleep(seconds)
        print("[debugwait] wait complete; continuing", file=sys.stderr, flush=True)

    return cleaned
```

Call it in the selected entry before normal parsing:

```python
def main(argv: list[str] | None = None) -> None:
    arguments = list(sys.argv[1:] if argv is None else argv)
    arguments = apply_debugwait(arguments)
    # Build the existing parser or initialize the existing service here.
```

If the project exposes an argparse help screen, register a matching
`--debugwait` argument in the parser with default `0`; the early helper still
owns the actual wait and removes the flag before normal parsing.

## Scope Rules

- Include every entry point the user clearly wants covered, especially distinct
  CLI and service modes.
- Do not modify tests, unrelated executables, deployment environments, or debug
  configurations unless they are required to run the selected entry point.
- Do not add a production-only configuration toggle unless the project already
  has an environment/build boundary that makes that appropriate. Clearly
  document that a large nonzero delay affects startup time and orchestration
  health checks.
- Prefer one small helper over duplicated wait code.
