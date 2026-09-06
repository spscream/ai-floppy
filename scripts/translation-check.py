#!/usr/bin/env python3
"""Report translations that have fallen behind their source, or break the contract.

    python3 scripts/translation-check.py
    python3 scripts/translation-check.py --json
    python3 scripts/translation-check.py --stamp docs/memory-model.ru.md

It REPORTS. It never fails the run, and that is deliberate: gating on freshness
would turn every typo fix in an English document into bilingual work, and would
teach whoever is in a hurry to bump the record without re-reading the source —
destroying the only signal the record carries. The same reasoning is frozen for
`metadata.as_of` in the memory linter.

The language is never named here. A translation is discovered by its file name
(`<stem>.<two letters>.md`) and confirmed by its marker, so this file does not
become the first place a specific language leaks into the plugin.

No third-party dependencies on purpose — this has to run on a fresh machine and
on macOS with the system python3.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# `<stem>.<lang>.md`. The shape is the candidate filter; the marker below is the
# confirmation. A file matching the shape without a marker is reported rather
# than ignored — silently ignoring it is how a translation whose marker was lost
# disappears from the report.
TRANSLATION_NAME = re.compile(r"^(?P<stem>.+)\.(?P<lang>[a-z]{2})\.md$")
MARKER = re.compile(r"^<!--\s*floppy:translation\s+(?P<fields>.*?)\s*-->\s*$")
FIELD = re.compile(r"(\w+)=(\S+)")
BLOB = re.compile(r"^[0-9a-f]{40}$")

# CHANGELOG.md is deliberately absent: the owner scoped the translation to
# README.md and docs/ (spec, decision 1). Without this comment a later reader
# would read the omission as an oversight and "fix" it.
SOURCE_ROOTS = ("README.md", "docs")

# An evening at UTC+3 is already tomorrow for the runners. One day of slack, and
# the same rule the memory linter freezes for `metadata.as_of`.
FUTURE_SLACK_DAYS = 1


def blob_sha(data):
    """The git blob sha of these bytes — a pure function of content, no git needed.

    Recorded instead of a plain sha256 because it is a pointer into history:
    `git cat-file blob <sha>` resolves it, so "what changed since this was
    translated" has an answer.
    """
    header = ("blob %d\0" % len(data)).encode()
    return hashlib.sha1(header + data).hexdigest()


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def sources(root):
    """The English documents that should have a translation."""
    out = []
    readme = os.path.join(root, "README.md")
    if os.path.isfile(readme):
        out.append("README.md")
    docs = os.path.join(root, "docs")
    if os.path.isdir(docs):
        for fn in sorted(os.listdir(docs)):
            # Subdirectories are skipped: docs/statuses/ is the project's working
            # state and docs/specs/ and docs/plans/ are design records.
            if not fn.endswith(".md") or TRANSLATION_NAME.match(fn):
                continue
            if not os.path.isfile(os.path.join(docs, fn)):
                continue
            out.append(os.path.join("docs", fn))
    return out


def translations(root):
    """Every file whose name is shaped like a translation, in the same two places."""
    out = []
    for fn in sorted(os.listdir(root)):
        if TRANSLATION_NAME.match(fn) and os.path.isfile(os.path.join(root, fn)):
            out.append(fn)
    docs = os.path.join(root, "docs")
    if os.path.isdir(docs):
        for fn in sorted(os.listdir(docs)):
            # isfile, not just the name: a directory wearing a translation's name
            # crashed the read below, and the crash came out as a non-zero exit.
            if TRANSLATION_NAME.match(fn) and os.path.isfile(os.path.join(docs, fn)):
                out.append(os.path.join("docs", fn))
    return out


def parse_marker(text):
    line = text.split("\n", 1)[0]
    m = MARKER.match(line)
    if not m:
        return None
    return dict(FIELD.findall(m.group("fields")))


def sibling_source(rel):
    """`docs/lessons.ru.md` -> `docs/lessons.md`."""
    name = os.path.basename(rel)
    m = TRANSLATION_NAME.match(name)
    return os.path.join(os.path.dirname(rel), m.group("stem") + ".md")


def audit(root):
    today = dt.date.today()
    broken, behind = [], []
    translated_sources = set()

    for rel in translations(root):
        path = os.path.join(root, rel)
        problems = []
        front = parse_marker(read_bytes(path).decode("utf-8", "replace"))

        if front is None:
            broken.append({"path": rel, "problems": ["no floppy:translation marker on line 1"]})
            continue

        expected_source = sibling_source(rel)
        source = front.get("of", "")
        if source != expected_source:
            problems.append(
                "`of` is `%s` — it does not name its sibling `%s`" % (source, expected_source)
            )
        else:
            # Only a marker that names its real sibling counts as translating it.
            # Crediting whatever `of` says let one broken marker delete a genuinely
            # untranslated document from the report.
            translated_sources.add(source)

        recorded = front.get("blob", "")
        if not BLOB.match(recorded):
            problems.append("`blob` is `%s` — that is not a git blob sha" % recorded)

        raw = front.get("on", "")
        try:
            made = dt.date.fromisoformat(raw)
        except ValueError:
            problems.append("`on` is not an ISO date: %r" % raw)
        else:
            if (made - today).days > FUTURE_SLACK_DAYS:
                problems.append("`on` is in the future (%s)" % raw)

        source_path = os.path.join(root, source)
        if not os.path.isfile(source_path):
            problems.append("`of` names `%s`, which does not exist" % source)
        elif BLOB.match(recorded):
            current = blob_sha(read_bytes(source_path))
            if current != recorded:
                behind.append(
                    {"path": rel, "source": source, "recorded": recorded,
                     "current": current, "on": raw}
                )

        if problems:
            broken.append({"path": rel, "problems": problems})

    untranslated = [s for s in sources(root) if s not in translated_sources]
    return broken, behind, untranslated


def stamp(root, rel):
    """Rewrite a translation's marker to the source's current blob and today's date."""
    path = os.path.join(root, rel)
    if not TRANSLATION_NAME.match(os.path.basename(rel)):
        print("%s is not shaped like a translation (<stem>.<two letters>.md)" % rel)
        return
    if not os.path.isfile(path):
        print("%s does not exist" % rel)
        return
    source = sibling_source(rel)
    source_path = os.path.join(root, source)
    if not os.path.isfile(source_path):
        print("%s names the source %s, which does not exist" % (rel, source))
        return

    raw = read_bytes(path)
    previous = parse_marker(raw.decode("utf-8", "replace"))
    current = blob_sha(read_bytes(source_path))
    line = "<!-- floppy:translation of=%s blob=%s on=%s -->" % (
        source, current, dt.date.today().isoformat()
    )
    # Bytes all the way through, deliberately. Decoding the body with
    # errors="replace" and writing the result back would silently rewrite every
    # byte the decoder could not represent — a checker that corrupts the document
    # it was pointed at is worse than no checker.
    if previous and b"\n" in raw:
        rest = raw.split(b"\n", 1)[1]
    elif previous:
        rest = b""
    else:
        rest = raw
    with open(path, "wb") as fh:
        fh.write(line.encode("utf-8") + b"\n" + rest)

    print("stamped %s against %s (%s)" % (rel, source, current))
    if previous and BLOB.match(previous.get("blob", "")):
        # Printed on success, not only on failure: stamping without reading what
        # changed is the failure this whole arrangement exists to make visible,
        # and the affordance should not be quieter than the thing it can hide.
        print("what changed since the previous stamp:")
        print("  git cat-file blob %s | diff - %s" % (previous["blob"], source))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=ROOT, help="repository to check, default: this one")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--stamp", metavar="PATH", help="re-record a translation against its source")
    args = ap.parse_args()

    if not os.path.isdir(args.root):
        print("-- the checker itself failed")
        print("   --root %s is not a directory" % args.root)
        return

    try:
        if args.stamp:
            stamp(args.root, args.stamp)
            return

        broken, behind, untranslated = audit(args.root)

        if args.json:
            json.dump(
                {"broken": broken, "behind": behind, "untranslated": untranslated},
                sys.stdout, ensure_ascii=False, indent=2,
            )
            print()
            return

        if broken:
            print("-- contract problems (%d)" % len(broken))
            for item in broken:
                print("  %s" % item["path"])
                for problem in item["problems"]:
                    print("      %s" % problem)
            print()

        if behind:
            print("-- behind the source (%d)" % len(behind))
            print("   The source changed after the translation was made. Read what changed,")
            print("   bring the translation up to it, then re-stamp.\n")
            for item in behind:
                print("  %s  (stamped %s against %s)" % (item["path"], item["on"], item["recorded"][:12]))
                print("      git cat-file blob %s | diff - %s" % (item["recorded"], item["source"]))
                print("      then: python3 scripts/translation-check.py --stamp %s" % item["path"])
            print()

        if untranslated:
            print("-- untranslated (%d)" % len(untranslated))
            for path in untranslated:
                print("  %s" % path)
            print()

        if not broken and not behind and not untranslated:
            print("clean: every translation names its source and matches it.")
    except Exception as exc:
        # The one rule this script may never break is its exit code. A crash is
        # still a report: name it loudly and leave the run green, rather than
        # letting a checker that reports turn into a gate that fails.
        print("-- the checker itself failed")
        print("   %s: %s" % (type(exc).__name__, exc))


if __name__ == "__main__":
    main()
