#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# Compare this deck's rendering of a number format against what LibreOffice
# displays for the same cell.
#
# The comparison is on an HTML export rather than a CSV one, because CSV
# carries the value and HTML carries the text the application put on screen -
# which is the thing a number format decides. LibreOffice's CSV export
# applies some formats and not others, so it cannot answer this question.
import html
import os
import re
import sys


def displayed(path):
    """Every cell's displayed text, row by row, from an HTML export."""
    if not os.path.exists(path):
        return None
    raw = open(path, encoding="utf-8", errors="replace").read()
    out = []
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", raw, re.S):
        cells = [
            html.unescape(re.sub(r"<[^>]+>", "", cell))
            .replace("\xa0", " ")
            .strip()
            for cell in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)
        ]
        if cells:
            out.append(cells)
    return out


def main():
    work = sys.argv[1]
    ours = [
        line.rstrip("\n").split("\t")
        for line in open(os.path.join(work, "ours.tsv"), encoding="utf-8")
        if line.strip()
    ]

    bad = []
    checked = 0
    compared = []
    # Every writer that carries a format, so a regression in any of them
    # shows up here and not only in the deck's own round trip.
    for kind in ("xlsx", "gnumeric", "ods"):
        theirs = displayed(os.path.join(work, "lo", "probe-%s.html" % kind))
        if not theirs:
            continue
        compared.append(kind)
        for index, row in enumerate(ours):
            if index >= len(theirs):
                break
            for column in range(1, len(row)):
                if column >= len(theirs[index]):
                    continue
                checked += 1
                if row[column].strip() != theirs[index][column].strip():
                    bad.append(
                        (kind, row[0], row[column], theirs[index][column])
                    )

    # The German pass, when the locale is installed: same codes, spelled the
    # way a German-locale application spells them.
    german = displayed(os.path.join(work, "lo-de", "probe-xlsx.html"))
    if german:
        mine_de = [
            line.rstrip("\n").split("\t")
            for line in open(
                os.path.join(work, "ours-de.tsv"), encoding="utf-8"
            )
            if line.strip()
        ]
        compared.append("xlsx in German")
        for index, row in enumerate(mine_de):
            if index >= len(german):
                break
            for column in range(1, len(row)):
                if column >= len(german[index]):
                    continue
                checked += 1
                if row[column].strip() != german[index][column].strip():
                    bad.append(
                        ("de", row[0], row[column], german[index][column])
                    )

    if not compared:
        print("no HTML export to compare - skipping the format oracle")
        return 0
    if not bad:
        print(
            "all %d formatted cells match what libreoffice displays, "
            "written as %s" % (checked, " and ".join(compared))
        )
        return 0
    for kind, code, mine, shown in bad:
        print(
            "disagreement: format %s, written as %s\n  ours: %s\n"
            "  libreoffice: %s" % (code, kind, mine, shown),
            file=sys.stderr,
        )
    print(
        "\n%d of %d formatted cells differ from what libreoffice displays."
        % (len(bad), checked),
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
