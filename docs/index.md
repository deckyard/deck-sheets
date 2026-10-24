<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/sheets

Read, edit and write OpenDocument (`.ods`), Office Open XML (`.xlsx`),
Gnumeric and delimited text over one cell model.

This deck is part of [Deckyard](https://github.com/deckyard), community decks for [Jennifer](https://jennifer-lang.dev/).

```jennifer
import "@deckyard/sheets/" as sheet;

def wb as sheet.Workbook init sheet.open("sales.xlsx");
def s as sheet.Sheet init sheet.sheetByName($wb, "Q3");

for (def line in sheet.rows($s)) {
    io.printf("%s\n", sheet.asString($line[0]));
}

sheet.save($wb, "sales.ods");
```

A conversion is a read and a write; nothing in between knows which format the
workbook came from. Install with `jvc add @deckyard/sheets`; it needs Jennifer
0.25.0 or newer and no capabilities beyond `fs` for `open` and `save`.

## What it covers

- [The cell model](guide/model.md): a `Workbook` of `Sheet`s of `Value`s
  (text, number, boolean, date, formula, error), the same in every format and
  direction.
- [Formats](guide/formats.md): ODS, XLSX and Gnumeric read and write in full,
  styles and number formats included; [CSV and TSV](guide/csv.md) are a
  one-sheet bridge.
- [Styles](guide/styles.md): font, colours, alignment, borders and number
  format, interned per sheet.
- [Formulas](guide/formulas.md): translated between the ODS dialect
  (`of:=[.B3]*[.C2]`) and the XLSX one (`B3*C2`) whenever a formula crosses
  formats.
- [Evaluating formulas](guide/evaluation.md): about 110 functions,
  checked against LibreOffice and Gnumeric.
- [Number formats](guide/formats-applied.md): `displayAt` shows what an
  application would display; `asString` gives the value.
- [Reading large sheets](guide/streaming.md): a row cursor that never holds
  the whole sheet.
- [Exporting](guide/exporting.md): HTML with inline styles, JSON keyed by the
  header row, paginated PDF.
- [Reading untrusted files](guide/untrusted.md): what a hostile file can and
  cannot do.

## What it does not do

- **Array formulas.** A range where one value is wanted (`A1:A5*2`,
  `OR(A1:A5>4)`) is `#VALUE!`, which is what both reference applications
  answer.
- **Defined names.** A bare name in a formula is `#NAME?`; a named range
  round-trips as text but is not resolved.
- **Some number formats through ODS.** ODF cannot express a month's initial
  (`mmmmm` comes back as `mmm`) or `_x` / `*x` padding (dropped).
- Charts, images, pivot tables, macros, and `.xls` (the old binary format).
