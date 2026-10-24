#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# Check the number-format engine against what LibreOffice puts on screen.
#
# The formula oracle checks the engine through `TEXT`, which is one code and
# one value at a time. This checks a whole sheet of cells that carry their
# formats in their own styles, written to a file and exported as HTML - so it
# covers `displayAt`, the writers' format round trip and the engine together,
# in the arrangement a user has, through all three writers that carry a
# format at all.
#
# HTML rather than CSV deliberately: a CSV export carries the value, and this
# is a question about the text the application displayed. LibreOffice's CSV
# export applies some formats and ignores others.
#
# Skips when LibreOffice is not installed. The validate workflow installs it.
#
# Usage: tools/format-oracle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v soffice >/dev/null 2>&1; then
    echo "no soffice on PATH - skipping the format oracle"
    exit 0
fi

# Inside the repository, not /tmp: in CI the interpreter runs in a container
# that only has the workspace mounted, so a /tmp path would be written inside
# the container and lost. Gitignored as .oracle-*.
work="$(mktemp -d "${PWD}/.oracle-XXXXXX")"
trap 'rm -rf "$work"' EXIT

# A known locale, or the decimal separator and the month names move.
export LC_ALL=en_US.UTF-8

jennifer run tools/format-oracle.j "$(basename "$work")"

# Both formats that store a format code, so a regression in either writer
# shows up here rather than only in the deck's own round trip. One invocation
# for both: a second `soffice` started straight after the first attaches to
# the instance still shutting down and converts nothing.
soffice -env:UserInstallation="file://$work/profile" \
    --headless --convert-to html --outdir "$work/lo" \
    "$work/probe-xlsx.xlsx" "$work/probe-gnumeric.gnumeric" \
    "$work/probe-ods.ods" \
    >/dev/null 2>&1 || true

# And once more in German, to check the locale mechanism against an
# application rather than against itself. A format code is the same in every
# region; what is shown for one is not.
if locale -a 2>/dev/null | grep -qi '^de_DE'; then
    LC_ALL=de_DE.UTF-8 soffice -env:UserInstallation="file://$work/profile-de" \
        --headless --convert-to html --outdir "$work/lo-de" \
        "$work/probe-xlsx.xlsx" \
        >/dev/null 2>&1 || true
fi

python3 tools/format-oracle.py "$work"
