#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# Cross-check the formula engine against LibreOffice and Gnumeric.
#
# The deck's own tests share every assumption the engine made, so they cannot
# say whether it computes what a spreadsheet computes. This writes the
# formulas in tools/formula-oracle.txt into an .ods, has both applications
# evaluate them, and diffs all three answers. It found real bugs: `^` leaning
# the wrong way, `0^-1`, and COUNTIF counting text against a numeric
# criterion.
#
# Skips when neither application is installed, so a developer host without
# them still gets a green gate. The validate workflow installs both.
#
# Usage: tools/formula-oracle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

have_lo=0
have_gnm=0
command -v soffice >/dev/null 2>&1 && have_lo=1
command -v ssconvert >/dev/null 2>&1 && have_gnm=1
if (( have_lo == 0 && have_gnm == 0 )); then
    echo "neither soffice nor ssconvert on PATH - skipping the formula oracle"
    exit 0
fi

# Inside the repository, not /tmp: in CI the interpreter runs in a container
# that only has the workspace mounted, so a /tmp path would be written inside
# the container and lost. Gitignored as .oracle-*.
work="$(mktemp -d "${PWD}/.oracle-XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Both applications render through the locale, so without this a dot decimal
# separator comes back as a comma and `TEXT` cases cannot be compared as text
# at all. This host runs LC_NUMERIC=de_DE, which is exactly that trap.
export LC_ALL=en_US.UTF-8

jennifer run tools/formula-oracle.j "$(basename "$work")"

if (( have_lo )); then
    # A private profile, so a desktop session already holding one does not
    # make the headless run bail out.
    soffice -env:UserInstallation="file://$work/lo-profile" \
        --headless --convert-to csv "$work/probe.ods" --outdir "$work/lo" \
        >/dev/null 2>&1 || true
fi
if (( have_gnm )); then
    ssconvert "$work/probe.ods" "$work/gnm.csv" >/dev/null 2>&1 || true
fi

python3 tools/formula-oracle.py "$work"
