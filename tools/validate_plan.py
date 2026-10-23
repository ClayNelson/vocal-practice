#!/usr/bin/env python3
"""Validate a song plan.json against docs/SONG_PLAN.md. Usage: python3 tools/validate_plan.py path/to/plan.json"""
import json
import re
import sys
from datetime import date, timedelta

BLOCKS = {"listen", "sections", "fullRun", "maintenance", "taper"}
GOALS = {"showcase", "recording", "lesson", "none"}
NOTE = re.compile(r"^[A-G](#|b)?[0-8]$")


def d(s):
    return date.fromisoformat(s)


def validate(plan):
    errors = []
    if plan.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    song = plan.get("song", {})
    for f in ("title", "artist", "originalKey", "minutesPerPass"):
        if not song.get(f):
            errors.append(f"song.{f} is required")
    rng = song.get("range", {})
    for f in ("low", "high"):
        if rng.get(f) and not NOTE.match(rng[f]):
            errors.append(f"song.range.{f} '{rng[f]}' is not a note like E3 or F#4")
    goal = plan.get("goal", {})
    if goal.get("type") not in GOALS:
        errors.append(f"goal.type must be one of {sorted(GOALS)}")
    section_ids = {s.get("id") for s in plan.get("sections", [])}
    for s in plan.get("sections", []):
        if s.get("difficulty") not in {"high", "medium", "low"}:
            errors.append(f"section {s.get('id')}: difficulty must be high, medium, or low")
    phases = plan.get("phases", [])
    if not phases:
        errors.append("at least one phase is required")
    prev_end = None
    for p in phases:
        start, end = d(p["start"]), d(p["end"])
        if end < start:
            errors.append(f"phase {p['id']}: ends before it starts")
        if prev_end and start != prev_end + timedelta(days=1):
            errors.append(f"phase {p['id']}: starts {start}, expected {prev_end + timedelta(days=1)} (gap or overlap)")
        if p.get("songBlock") not in BLOCKS:
            errors.append(f"phase {p['id']}: songBlock must be one of {sorted(BLOCKS)}")
        for sid in p.get("focusSections", []):
            if sid not in section_ids:
                errors.append(f"phase {p['id']}: unknown section '{sid}'")
        prev_end = end
    if phases and goal.get("date"):
        if phases[-1].get("songBlock") != "taper":
            errors.append("last phase must be a taper")
        if d(phases[-1]["end"]) != d(goal["date"]):
            errors.append("last phase must end on goal.date")
    for c in plan.get("checkpoints", []):
        d(c["due"])
    return errors


if __name__ == "__main__":
    plan = json.load(open(sys.argv[1]))
    errs = validate(plan)
    if errs:
        print("INVALID:\n- " + "\n- ".join(errs))
        sys.exit(1)
    print(f"OK: {plan['song']['title']}, {len(plan['phases'])} phases to {plan['goal'].get('date')}")
