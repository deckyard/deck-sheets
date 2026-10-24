# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0
# ci-no-overlay

# sheets - the deck version.
# Spliced into sheets.j via include - not a standalone module.

/**
 * The version of this deck.
 *
 * Kept in step with `deck.toml`; the release workflow refuses a tag that
 * disagrees with the manifest.
 */
export def const VERSION as string init "0.1.0";
