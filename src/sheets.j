# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * sheets - read, edit and write spreadsheet formats over one cell model.
 *
 * Three formats over one workbook model, plus the layers on top:
 *
 *   model       {@link Workbook} / {@link Sheet} / {@link Value}
 *   addressing  {@link cellRef} / {@link parseRef} / {@link parseArea}
 *   any format  {@link open} / {@link save} / {@link formatOf}
 *   ODS         {@link readOds} / {@link writeOds}
 *   XLSX        {@link readXlsx} / {@link writeXlsx}
 *   Gnumeric    {@link readGnumeric} / {@link writeGnumeric}
 *   CSV         {@link readCsv} / {@link writeCsv} / {@link writeCsvSafe}
 *   streaming   {@link openRows} / {@link nextRow} / {@link rowValues}
 *   styles      {@link Style} / {@link setStyle} / {@link styleAt}
 *   display     {@link applyFormat} / {@link displayAt} / {@link Locale}
 *   formulas    {@link toA1Formula} / {@link toOpenFormula}
 *   evaluation  {@link evaluate} / {@link recalculate}
 *   exports     {@link toHtml} / {@link toJson} / {@link toPdf}
 *
 * {@link Workbook} is the same struct for all three formats, in both
 * directions, so a conversion is a read and a write.
 *
 * The XML codecs stream. No whole sheet is decoded into a tree; a scanner
 * walks the element boundaries and `xml.decode` reads one row at a time, so
 * peak memory follows the result rather than the file size. The measurements
 * are in `docs/internal/memory.md`.
 *
 * Everything is value-semantic: a function that changes a cell, a sheet or a
 * workbook returns a fresh value and leaves its argument alone, so the
 * calling shape is `$x = something($x, ...)`.
 *
 * The implementation is split into topic files under `topics/`, spliced in
 * here with `include`; this file is the only compilable unit. The white-box
 * tests are spliced the same way into `sheets_test.j`.
 *
 * @module sheets
 * @see https://docs.oasis-open.org/office/OpenDocument/v1.3/
 * @see https://ecma-international.org/publications-and-standards/standards/ecma-376/
 * @example
 *   import "@deckyard/sheets/" as sheet;
 *
 *   def wb as sheet.Workbook init sheet.open("sales.xlsx");
 *   def s as sheet.Sheet init sheet.sheetByName($wb, "Q3");
 *
 *   io.printf("%s\n", sheet.asString(sheet.cell($s, "B7")));
 *
 *   $s = sheet.setCell($s, "B8", sheet.number(42.5));
 *   $wb = sheet.putSheet($wb, $s);
 *   sheet.save($wb, "out.ods");
 */

use strings;
use convert;
use math;
use time;
use maps;
use lists;
use stats;
use fs;
use path;
use binary;
use archive;
use compress;
use crc;
use xml;
use json;

import "csv.j" as csv;
import "pdf.j" as pdf;

include "topics/version.j";
include "topics/core.j";
include "topics/address.j";
include "topics/value.j";
include "topics/style.j";
include "topics/model.j";
include "topics/numfmt.j";
include "topics/odsfmt.j";
include "topics/emit.j";
include "topics/zip.j";
include "topics/scan.j";
include "topics/fdialect.j";
include "topics/flex.j";
include "topics/fparse.j";
include "topics/feval.j";
include "topics/ffn.j";
include "topics/ffntext.j";
include "topics/ffnlogic.j";
include "topics/odsread.j";
include "topics/odswrite.j";
include "topics/xlsxread.j";
include "topics/xlsxwrite.j";
include "topics/gnumeric.j";
include "topics/csvbridge.j";
include "topics/export.j";
include "topics/rows.j";
include "topics/file.j";
