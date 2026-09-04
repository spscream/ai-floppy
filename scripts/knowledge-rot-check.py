#!/usr/bin/env python3
"""Report notes that have gone stale, or that break the writing contract.

    python3 scripts/knowledge-rot-check.py               # default: 90 days
    python3 scripts/knowledge-rot-check.py --days 180
    python3 scripts/knowledge-rot-check.py --json

It REPORTS. It never fails the run, and that is deliberate: "old" and "wrong" are
different things, and only a person who knows the area can tell them apart. A note about
a stable POSIX behaviour is fine at three years; a note about a harness version is
suspect at three months. A gate would force the wrong answer for one of them.

No third-party dependencies on purpose — this has to run on a fresh machine and on macOS
with the system python3.
"""

import argparse
import datetime as dt
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTES = os.path.join(ROOT, "knowledge", "notes")

REQUIRED = ("name", "description", "area", "verified_on", "verified_against", "recheck")
NOTE_CHARS_MAX = 10000
AREAS = ("harness", "memory", "shell", "practice")
# The optional machine-checkable half, run by scripts/knowledge-recheck.py.
KNOWN_PLATFORMS = ("linux", "macos", "windows")


def unquote(value):
    """Strip matching surrounding quotes only.

    Stripping any leading or trailing quote mangles a shell command that legitimately
    ends in one (`rm -rf "$d"`), and the damage surfaces far from the note.
    """
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def parse_front_matter(text):
    """Minimal YAML-ish front matter reader: `key: value`, one per line."""
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    data = {}
    for line in m.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        data[key.strip()] = unquote(value)
    return data


def collect():
    notes = []
    # followlinks: the same trap docs/lessons.md records for `find` applies here —
    # os.walk does not descend a symlinked directory either, and an empty result is
    # indistinguishable from "nothing to check".
    for dirpath, _dirnames, filenames in os.walk(NOTES, followlinks=True):
        for fn in sorted(filenames):
            if not fn.endswith(".md") or fn.startswith("_"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            notes.append(
                {
                    "path": os.path.relpath(path, ROOT),
                    "slug": fn[:-3],
                    "chars": len(text),
                    "front": parse_front_matter(text),
                }
            )
    return notes


def audit(notes, days):
    today = dt.date.today()
    stale, broken = [], []

    for note in notes:
        front = note["front"]
        problems = []

        if front is None:
            broken.append({"path": note["path"], "problems": ["no front matter"]})
            continue

        for field in REQUIRED:
            if not front.get(field):
                problems.append(f"missing `{field}`")

        if front.get("name") and front["name"] != note["slug"]:
            problems.append(f"`name` is `{front['name']}` but the file is `{note['slug']}.md`")

        if front.get("area") and front["area"] not in AREAS:
            problems.append(f"unknown area `{front['area']}`")

        # The site page groups by `area`, the reader browses by directory. When the two
        # disagree the note is filed in one place and published in another, and neither
        # view is wrong enough for anyone to notice.
        parent = os.path.basename(os.path.dirname(note["path"]))
        if front.get("area") and parent in AREAS and front["area"] != parent:
            problems.append(f"`area` is `{front['area']}` but the file sits in `{parent}/`")

        # The machine-checkable half. Both fields or neither: a command with nothing to
        # compare against runs, produces output, and proves nothing — the worst of the
        # three states, because the runner would have to call it a pass.
        if front.get("recheck_cmd") and not front.get("expect"):
            problems.append("`recheck_cmd` without `expect` — nothing to compare the output to")
        if front.get("expect") and not front.get("recheck_cmd"):
            problems.append("`expect` without `recheck_cmd` — nothing produces that output")
        for name in [p.strip() for p in (front.get("platforms") or "").split(",") if p.strip()]:
            if name not in KNOWN_PLATFORMS:
                problems.append(f"unknown platform `{name}` (known: {', '.join(KNOWN_PLATFORMS)})")

        if note["chars"] > NOTE_CHARS_MAX:
            problems.append(
                f"{note['chars']} characters, cap is {NOTE_CHARS_MAX} — this is two notes"
            )

        raw = front.get("verified_on", "")
        try:
            verified = dt.date.fromisoformat(raw)
        except ValueError:
            problems.append(f"`verified_on` is not an ISO date: {raw!r}")
        else:
            age = (today - verified).days
            if age < 0:
                problems.append(f"`verified_on` is in the future ({raw})")
            elif age >= days:
                stale.append(
                    {
                        "path": note["path"],
                        "age_days": age,
                        "verified_on": raw,
                        "verified_against": front.get("verified_against", ""),
                        "recheck": front.get("recheck", ""),
                    }
                )

        if problems:
            broken.append({"path": note["path"], "problems": problems})

    stale.sort(key=lambda n: -n["age_days"])
    return stale, broken


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=90, help="staleness threshold, default 90")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    notes = collect()
    stale, broken = audit(notes, args.days)

    if args.json:
        json.dump(
            {"total": len(notes), "stale": stale, "broken": broken},
            sys.stdout,
            ensure_ascii=False,
            indent=2,
        )
        print()
        return

    print(f"{len(notes)} note(s) in {os.path.relpath(NOTES, ROOT)}\n")

    if broken:
        print(f"-- contract problems ({len(broken)})")
        for item in broken:
            print(f"  {item['path']}")
            for problem in item["problems"]:
                print(f"      {problem}")
        print()

    if stale:
        print(f"-- verification older than {args.days} days ({len(stale)})")
        print("   Not necessarily wrong. Re-verify, update the environment, or rewrite in place.\n")
        for item in stale:
            print(f"  {item['path']}  ({item['age_days']} days, checked {item['verified_on']})")
            if item["verified_against"]:
                print(f"      against: {item['verified_against']}")
            if item["recheck"]:
                print(f"      recheck: {item['recheck']}")
        print()

    if not stale and not broken:
        print("clean: every note carries its contract and none has aged out.")


if __name__ == "__main__":
    main()
