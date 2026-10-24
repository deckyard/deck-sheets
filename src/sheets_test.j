# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box unit tests for the sheets module.
 *
 * Runs as the co-located test overlay: `jennifer test src/sheets_test.j`.
 * The tests are split into topic files under `topics/`, spliced together here
 * with `include` - one test file per implementation topic file, in the same
 * order `sheets.j` splices the topics themselves.
 *
 * The deck is pure computation over text and bytes, so nearly all of it is
 * covered here directly: the entity codec, A1 addressing, the element scanner
 * against malformed markup, the ZIP container in both directions, every
 * format in both directions, and the round trip between them. The functions
 * that take a path (`open`, `openDetected`, `save`, `openRows`) are covered
 * only on the inputs they refuse before reading or writing a file; their
 * byte-level halves (`readFormat`, `writeFormat`, `openRowsFromBytes`) carry
 * the rest.
 */

use testing;
use strings;
use convert;
use math;
use time;
use xml;
use maps;
use binary;

include "topics/core_test.j";
include "topics/address_test.j";
include "topics/value_test.j";
include "topics/style_test.j";
include "topics/model_test.j";
include "topics/numfmt_test.j";
include "topics/odsfmt_test.j";
include "topics/emit_test.j";
include "topics/zip_test.j";
include "topics/scan_test.j";
include "topics/fdialect_test.j";
include "topics/flex_test.j";
include "topics/fparse_test.j";
include "topics/feval_test.j";
include "topics/ffn_test.j";
include "topics/ffntext_test.j";
include "topics/ffnlogic_test.j";
include "topics/odsread_test.j";
include "topics/xlsxread_test.j";
include "topics/odswrite_test.j";
include "topics/xlsxwrite_test.j";
include "topics/gnumeric_test.j";
include "topics/csvbridge_test.j";
include "topics/rows_test.j";
include "topics/export_test.j";
include "topics/file_test.j";
