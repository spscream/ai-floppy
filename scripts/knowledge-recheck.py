#!/usr/bin/env python3
"""Run the executable half of each knowledge note's recheck.

    python3 scripts/knowledge-recheck.py              # every runnable check
    python3 scripts/knowledge-recheck.py --only find  # notes whose name contains "find"
    python3 scripts/knowledge-recheck.py --json

A note may carry four optional fields beyond the reading contract:

    platforms:    linux, macos          where the claim is asserted to hold
    requires:     command -v claude     probe; non-zero exit means "cannot run here"
    recheck_cmd:  <shell>               the check itself, run under bash
    expect:       <text>                the check's exact stdout, whitespace-trimmed

`recheck` (prose, for a human) stays required. These four are what makes a note
machine-checkable, and most notes will never have them: a claim taken from vendor
documentation has nothing to execute. That is a fact about the note, not a defect,
and the report counts it separately rather than calling it a skip.

Why four fields and not the two that were planned. Without `requires`, a check that
needs a tool fails on every machine that lacks it, and a runner that is red by default
gets ignored. Without `platforms`, a POSIX-only claim fails on Windows and the failure
says nothing — the whole point of the matrix is that a claim is true *somewhere*.

Exit status is 1 if any check FAILED, 0 otherwise. Unlike knowledge-rot-check.py this
one is a gate: a failing check means the note is now false, or the check is broken, and
both need a person. Skips are never counted as passes — the four numbers are always
printed, because a runner that says "all green" while having run nothing is the exact
failure this repository has already paid for twice.
"""

import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTES = os.path.join(ROOT, "knowledge", "notes")
TIMEOUT = 120

KNOWN_PLATFORMS = ("linux", "macos", "windows")


def this_platform():
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "darwin":
        return "macos"
    if os.name == "nt" or sys.platform.startswith("win"):
        return "windows"
    return sys.platform


def unquote(value):
    """Strip matching surrounding quotes only.

    Stripping any leading or trailing quote character mangles a shell command that
    legitimately ends in one (`rm -rf "$d"`), and the damage shows up as a check that
    fails for a reason nowhere near the note.
    """
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def parse_front_matter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    data = {}
    for line in m.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        data[key.strip()] = unquote(value)
    return data


def collect():
    notes = []
    # followlinks for the reason docs/lessons.md records about `find`.
    for dirpath, _dirs, files in os.walk(NOTES, followlinks=True):
        for fn in sorted(files):
            if not fn.endswith(".md") or fn.startswith("_"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8") as fh:
                front = parse_front_matter(fh.read())
            notes.append(
                {"path": os.path.relpath(path, ROOT), "slug": fn[:-3], "front": front or {}}
            )
    return notes


def shell(command):
    return subprocess.run(
        ["bash", "-c", command],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
    )


def check(note, platform):
    front = note["front"]
    cmd = front.get("recheck_cmd")
    if not cmd:
        return {"state": "no-check", "why": "note carries no recheck_cmd"}

    if not front.get("expect"):
        return {"state": "failed", "why": "recheck_cmd without expect — nothing to compare"}

    declared = [p.strip() for p in (front.get("platforms") or "").split(",") if p.strip()]
    if declared and platform not in declared:
        return {"state": "skipped", "why": f"claim is asserted for {', '.join(declared)}; here is {platform}"}

    requires = front.get("requires")
    if requires:
        try:
            if shell(requires).returncode != 0:
                return {"state": "skipped", "why": f"requires `{requires}` — not satisfied here"}
        except subprocess.TimeoutExpired:
            return {"state": "skipped", "why": f"requires `{requires}` — timed out"}

    try:
        done = shell(cmd)
    except subprocess.TimeoutExpired:
        return {"state": "failed", "why": f"timed out after {TIMEOUT}s"}

    actual = done.stdout.strip()
    expect = front["expect"].strip()
    if actual == expect:
        return {"state": "passed", "why": ""}
    return {
        "state": "failed",
        "why": f"expected {expect!r}, got {actual!r}"
        + (f" (stderr: {done.stderr.strip()[:200]})" if done.stderr.strip() else ""),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="run notes whose path contains this")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    platform = this_platform()
    results = []
    for note in collect():
        if args.only and args.only not in note["path"]:
            continue
        outcome = check(note, platform)
        results.append({"path": note["path"], **outcome})

    counts = {s: sum(1 for r in results if r["state"] == s) for s in ("passed", "failed", "skipped", "no-check")}

    if args.json:
        json.dump({"platform": platform, "counts": counts, "results": results}, sys.stdout,
                  ensure_ascii=False, indent=2)
        print()
        return 1 if counts["failed"] else 0

    print(f"platform: {platform}\n")
    for r in results:
        mark = {"passed": "ok  ", "failed": "FAIL", "skipped": "skip", "no-check": "--  "}[r["state"]]
        print(f"  {mark} {r['path']}")
        if r["why"] and r["state"] != "no-check":
            print(f"         {r['why']}")

    # All four numbers, always. "N passed" alone is the sentence that let a check
    # which looked at nothing pass for a week.
    print(
        f"\n{counts['passed']} passed, {counts['failed']} failed, "
        f"{counts['skipped']} skipped, {counts['no-check']} not machine-checkable"
    )
    if counts["failed"]:
        print("\nA failed check means the note is now false, or the check is broken. Both need a person.")
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
