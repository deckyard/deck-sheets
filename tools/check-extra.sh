#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# The per-deck gate the shared test workflow calls after its own checks.
#
# For this deck that is two things, both of which need a real spreadsheet
# application because neither can be checked from inside the deck:
#
#   the files it writes have to open in one (tools/validate-output.sh)
#   the formula engine has to agree with one (tools/formula-oracle.sh)
#   a formatted cell has to look the same (tools/format-oracle.sh)
#
# Both skip when no application is installed, so a developer host without them
# still gets a green gate. The validate workflow installs both.
#
# Usage: tools/check-extra.sh
set -euo pipefail
cd "$(dirname "$0")/.."
tools/validate-output.sh
echo ""
tools/formula-oracle.sh
echo ""
tools/format-oracle.sh
