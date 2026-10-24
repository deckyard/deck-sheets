#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# Open every written file in a real spreadsheet application and compare the
# values it reads back, cell for cell.
#
# Why this exists: the deck's own readers share every assumption its writers
# made, so they cannot tell us whether a file is one a real application will
# accept. This check has already earned itself twice over - it found a
# Gnumeric document that LibreOffice read happily and Gnumeric itself refused
# ("inconsistent SheetNameIndex element"), and a formula cell that LibreOffice
# turned into NaN.
#
# Two converters, used for different reasons:
#
#   soffice     LibreOffice, the application most people will open the file
#               in. Forgiving, so it proves the file is usable.
#   ssconvert   Gnumeric, which is the reference implementation for the
#               Gnumeric format and much stricter about all three. It proves
#               the file is correct.
#
# Both are run when present and each is optional, so this is useful on a host
# with only one of them. With neither it skips rather than fails, which keeps
# it safe to run locally; the CI job in .github/workflows/validate.yml
# installs LibreOffice.
#
# LC_ALL=C throughout: ssconvert writes a decimal comma under a European
# locale, and a value comparison should not depend on the runner's language.
#
# Usage: tools/validate-output.sh
set -euo pipefail
cd "$(dirname "$0")/.."

JENNIFER="${JENNIFER:-jennifer}"
export LC_ALL=C

have_soffice=""
for candidate in soffice libreoffice; do
    if command -v "$candidate" >/dev/null 2>&1; then
        have_soffice="$candidate"
        break
    fi
done
have_ssconvert=""
command -v ssconvert >/dev/null 2>&1 && have_ssconvert=ssconvert

if [[ -z "$have_soffice" && -z "$have_ssconvert" ]]; then
    echo "no soffice and no ssconvert on PATH - skipping the output validation"
    echo "(this is the only check that catches a file a real application"
    echo " rejects; CI installs one, see .github/workflows/validate.yml)"
    exit 0
fi

# Inside the repository, not /tmp: in CI the interpreter runs in a container
# that only has the workspace mounted, so a /tmp path would be written where
# the converters on the runner cannot read it. Gitignored as .validate-*.
work="$(mktemp -d "${PWD}/.validate-XXXXXX")"
trap 'rm -rf "$work"' EXIT
rel="$(basename "$work")"

echo "--- writing fixtures"
"$JENNIFER" run tools/write-fixtures.j "$rel"

# Two renderings are the application's business rather than the file's, and
# both are normalised on *both* sides so a real change still shows up:
#
#   dates     a date renders per application and per locale, so the expected
#             file carries <DATE> on that row
#   booleans  LibreOffice renders a Gnumeric boolean as 1 and an ODS or XLSX
#             one as TRUE. Checked: a Gnumeric file written by Gnumeric itself
#             also reads back as 1 through LibreOffice, so this is its import
#             filter and not something this deck can write differently.
#
# Everything else is compared exactly.
normalise() {
    sed -E \
        -e 's/\r$//' \
        -e 's@[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}@<DATE>@g' \
        -e 's@[0-9]{2}/[0-9]{2}/[0-9]{4}@<DATE>@g' \
        -e 's/"([^"]*)"/\1/g' \
        -e 's/(^|,)TRUE($|,)/\1<TRUE>\2/g' \
        -e 's/(^|,)1($|,)/\1<TRUE>\2/g' \
        -e 's/(^|,)FALSE($|,)/\1<FALSE>\2/g' \
        -e 's/[[:space:]]+$//' "$1" | sed -e '/^$/d'
}

failed=0

check() {
    local tool="$1" fixture="$2" produced="$3" expected="$4" label="$5"
    if [[ ! -s "$produced" ]]; then
        echo "    ${label}: REJECTED - no output"
        failed=1
        return
    fi
    if diff -u <(normalise "$expected") <(normalise "$produced") > "${work}/diff" 2>&1; then
        echo "    ${label}: values match"
    else
        echo "    ${label}: VALUES DIFFER"
        sed 's/^/        /' "${work}/diff"
        failed=1
    fi
}

for fixture in "${work}"/fixture.*; do
    name="$(basename "$fixture")"
    kind="${name#fixture.}"
    expected="${work}/expected-${kind}.csv"
    echo "--- ${name}"
    if [[ ! -f "$expected" ]]; then
        echo "    no expected-${kind}.csv - tools/write-fixtures.j is out of step"
        failed=1
        continue
    fi

    if [[ -n "$have_soffice" ]]; then
        out="${work}/lo-${kind}"
        if "$have_soffice" --headless --norestore \
            -env:UserInstallation="file://${work}/profile-${kind}" \
            --convert-to csv --outdir "$out" "$fixture" \
            >"${work}/log-lo-${kind}" 2>&1; then
            check "$have_soffice" "$fixture" "${out}/fixture.csv" "$expected" \
                "libreoffice"
        else
            echo "    libreoffice: REJECTED the file"
            sed 's/^/        /' "${work}/log-lo-${kind}"
            failed=1
        fi
    fi

    if [[ -n "$have_ssconvert" ]]; then
        out="${work}/gnm-${kind}.csv"
        if ssconvert "$fixture" "$out" >"${work}/log-ss-${kind}" 2>&1; then
            check ssconvert "$fixture" "$out" "$expected" "gnumeric  "
        else
            echo "    gnumeric  : REJECTED the file"
            sed 's/^/        /' "${work}/log-ss-${kind}"
            failed=1
        fi
    fi
done

# Values are only half of it. A CSV export drops every style and applies only
# a date format, so the styles are checked through an HTML export, which is the
# one LibreOffice filter that carries formatting. This is what proves phase 7
# reached the application rather than merely surviving this deck's own reader -
# it already caught an ODS font written as `style:font-name`, which needs a
# font-face declaration LibreOffice silently ignored.
if [[ -n "$have_soffice" ]]; then
    for kind in ods xlsx gnumeric; do
        fixture="${work}/fixture.${kind}"
        [[ -f "$fixture" ]] || continue
        echo "--- fixture.${kind} formatting"
        out="${work}/html-${kind}"
        if ! "$have_soffice" --headless --norestore \
            -env:UserInstallation="file://${work}/htmlprofile-${kind}" \
            --convert-to html --outdir "$out" "$fixture" \
            >"${work}/log-html-${kind}" 2>&1; then
            echo "    REJECTED by the HTML filter"
            sed 's/^/        /' "${work}/log-html-${kind}"
            failed=1
            continue
        fi
        page="${out}/fixture.html"
        [[ -s "$page" ]] || page="${out}/fixture.htm"
        if [[ ! -s "$page" ]]; then
            echo "    no HTML output"
            failed=1
            continue
        fi
        lower="${work}/html-${kind}.lower"
        tr 'A-Z' 'a-z' < "$page" > "$lower"
        for probe in \
            'fff2cc:the header fill' \
            '19.98:the formula result' \
            '2026-10-02:the yyyy-mm-dd date format'; do
            needle="${probe%%:*}"
            label="${probe#*:}"
            if grep -qF -- "$needle" "$lower"; then
                echo "    kept ${label}"
            else
                echo "    LOST ${label}"
                failed=1
            fi
        done
        # Bold and centring are rendered as markup rather than as the words,
        # so they are matched as either spelling an exporter may choose.
        if grep -qE 'font-weight:[[:space:]]*(bold|[6-9]00)|<b[ >]' "$lower"; then
            echo "    kept the bold header"
        else
            echo "    LOST the bold header"
            failed=1
        fi
        if grep -qE 'text-align:[[:space:]]*center|align="center"' "$lower"; then
            echo "    kept the centred header"
        else
            echo "    LOST the centred header"
            failed=1
        fi
    done
fi

echo
if (( failed )); then
    echo "a written file was rejected or read back wrong - the file is wrong,"
    echo "not the job. Open it by hand to see what the application makes of it."
    exit 1
fi
tools="${have_soffice:-}${have_ssconvert:+ ${have_ssconvert}}"
echo "every written fixture opened in${tools:+ }${tools} with its values intact"
