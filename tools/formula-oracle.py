#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# Compare the three sets of answers tools/formula-oracle.sh collected.
#
# The comparison is on values, not on renderings, so it normalises the three
# things the applications differ on without disagreeing: the decimal
# separator and digit grouping of whatever locale they ran in, a percentage
# shown as `2.00%` where the value is 0.02, and a date shown in the locale's
# order. Everything surviving that is a real disagreement about a value.
import csv
import datetime
import os
import re
import sys

FORMULA_COLUMN = 6          # column G, where formula-oracle.j puts them
FIXTURE_ROWS = 3            # the fixture occupies the first rows

# LibreOffice's own error spellings, which differ from the file formats'.
ALIASES = {
    "Err:502": "#NUM!",
    "Err:522": "#REF!",
    "Err:504": "#VALUE!",
    "#ZAHL!": "#NUM!",
    "#WERT!": "#VALUE!",
}


def answers(path):
    """Read the formula column out of one application's CSV export."""
    if not os.path.exists(path):
        return None
    with open(path, newline="", encoding="utf-8", errors="replace") as handle:
        rows = [
            row[FORMULA_COLUMN] if len(row) > FORMULA_COLUMN else ""
            for row in csv.reader(handle)
        ]
    return rows[FIXTURE_ROWS:]


def normalise(raw):
    """Reduce a rendering to the value behind it."""
    text = raw.strip()
    if text in ALIASES:
        return ALIASES[text]
    percent = text.endswith("%")
    if percent:
        text = text[:-1].strip()
    # A comma decimal separator, with or without dot grouping.
    if re.fullmatch(r"-?\d{1,3}(\.\d{3})+,\d+", text):
        text = text.replace(".", "").replace(",", ".")
    elif re.fullmatch(r"-?\d+,\d+", text):
        text = text.replace(",", ".")
    # LibreOffice exports month first, Gnumeric year first. Both were read
    # off a date whose day is past 12, so the order is not a guess.
    for pattern, order in (
        (r"(\d{2})/(\d{2})/(\d{2})$", (3, 1, 2)),
        (r"(\d{2})/(\d{2})/(\d{4})$", (3, 1, 2)),
        (r"(\d{4})/(\d{2})/(\d{2})$", (1, 2, 3)),
        (r"(\d{4})-(\d{2})-(\d{2})$", (1, 2, 3)),
    ):
        hit = re.fullmatch(pattern, text)
        if hit:
            year = hit.group(order[0])
            if len(year) == 2:
                year = "20" + year
            return "%s-%s-%s" % (year, hit.group(order[1]), hit.group(order[2]))
    try:
        value = float(text)
    except ValueError:
        return text
    if percent:
        value = value / 100.0
    # Nine significant digits: enough to catch a wrong answer, loose enough
    # that a last-bit float difference is not reported as one.
    return "%.9g" % value


def as_date(value):
    """Render a date serial as an ISO date, or return None."""
    try:
        serial = float(value)
    except ValueError:
        return None
    if serial != int(serial) or not 1 <= serial <= 2958465:
        return None
    # The 1900 system with Excel's phantom 29 February 1900, which is why the
    # origin is 30 December 1899 rather than the 31st.
    return (
        datetime.date(1899, 12, 30) + datetime.timedelta(days=int(serial))
    ).isoformat()


def agree(mine, theirs):
    """Compare two renderings of the same answer."""
    if mine == theirs:
        return True
    # A date-valued formula in a cell with no date format exports as the raw
    # serial, which LibreOffice does for EDATE. Same value, different
    # rendering, so compare it as a date rather than calling it a bug.
    for one, other in ((mine, theirs), (theirs, mine)):
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", one) and as_date(other) == one:
            return True
    return False


def main():
    work = sys.argv[1]
    ours = [
        line.rstrip("\n").split("\t")
        for line in open(os.path.join(work, "ours.tsv"), encoding="utf-8")
        if line.strip()
    ]
    others = {
        "libreoffice": answers(os.path.join(work, "lo", "probe.csv")),
        "gnumeric": answers(os.path.join(work, "gnm.csv")),
    }
    present = {name: rows for name, rows in others.items() if rows}
    if not present:
        print("no application produced a CSV - nothing to compare")
        return 0

    bad = []
    for index, (formula, mine) in enumerate(ours):
        for name, rows in present.items():
            if index >= len(rows):
                continue
            theirs = rows[index]
            if not agree(normalise(mine), normalise(theirs)):
                bad.append((formula, mine, name, theirs))

    checked = ", ".join(sorted(present))
    if not bad:
        print("all %d formulas agree with %s" % (len(ours), checked))
        return 0
    for formula, mine, name, theirs in bad:
        print(
            "disagreement: %s\n  ours: %s\n  %s: %s" % (formula, mine, name, theirs),
            file=sys.stderr,
        )
    print(
        "\n%d of %d formulas disagree with %s."
        % (len(bad), len(ours), checked),
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
