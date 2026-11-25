<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck reads, edits and writes OpenDocument (`.ods`), Office Open XML
(`.xlsx`) and Gnumeric™ spreadsheets, plus CSV and TSV, through one
value-semantic `Workbook` model. Around that model it translates formulas
between the A1 and OpenFormula dialects, evaluates about 110 functions,
applies number formats the way an application displays them, reads large
sheets row by row, sets cells of an existing XLSX file in place, and exports
to HTML, JSON and PDF.

It is pure computation over bytes: it writes its own ZIP container and
never shells out to an office suite. Only `open`, `save` and `openRows`
touch the disk, through `fs`; every codec has a `bytes` entry point. It
needs no capability.

Out of scope:

- **Array formulas.** A range where one value is wanted is `#VALUE!`, as
  both reference applications answer.
- **Defined names.** A named range round-trips as text but is not resolved;
  a bare name in a formula is `#NAME?`.
- **Charts, images, pivot tables, macros** and the old binary `.xls`
  format.
- **ZIP64.** Archives past the classic ZIP limits are refused rather than
  written corrupt.

## Decisions

- **One model for every format.** `Value` is an enum (`Empty`, `Text`,
  `Number`, `Bool`, `Stamp`, `Formula{source, cached}`, `Err{code}`); a
  `Sheet` holds a sparse map of cells keyed by canonical A1, interned
  styles and its size; a `Workbook` is its sheets plus the 1900/1904 date
  system. A conversion is a read and a write, and nothing in between knows
  which format the workbook came from.
- **Formulas are stored in A1.** The ODS reader translates OpenFormula to
  A1 and the writer translates back, so a formula crosses formats intact.
  The translation is lexical and leaves anything it does not know as
  written. Reading never evaluates: a formula's cached value round-trips
  and stays as the file had it until `recalculate`.
- **Errors in formulas are values.** `evaluate` returns an error value
  (`#DIV/0!`, `#NAME?`, a cycle as `#REF!`) and throws only when the caller
  is at fault: a missing sheet, an unparseable expression, a formula past
  the parser's caps. Dependency resolution memoises and walks an explicit
  stack, so a chain of formulas is bounded by `MAX_RESOLVED_CELLS`, not by
  recursion depth. IF, IFERROR and the lookups receive unevaluated argument
  trees, so only the branch taken is evaluated.
- **LibreOffice™ and Gnumeric are the reference, not the specification.**
  Evaluation and number-format display follow what those applications do,
  and the ODF number-style shapes were read off LibreOffice output.
  `General` is normalised to an empty format code, or ODF would write it as
  a literal word.
- **A byte-level XML walker, and native decoding of leaves.** The readers
  scan the XML as bytes instead of decoding whole documents into a tree,
  which keeps memory proportional to the data. An XLSX row and a shared
  string are then handed to `xml.decode` whole: one native parse per row
  instead of an interpreted walk per cell, about thirty times faster. The
  worksheet's namespace declarations go with them, because Excel™ declares
  its extension prefixes (`x14ac`) on `<worksheet>` and uses them on the rows.
  A row that does not decode is walked by the scanner, which reads what a
  damaged file still has. ODS cells are mixed content (`a<span>B</span>b`),
  which a tree's text accessor flattens out of order, so ODS stays on the
  scanner. Element names are matched on their local part, since ODS prefixes
  everything and XLSX may. The walker was forked from `@deckyard/geo` and may
  diverge from it.
- **A hand-written ZIP writer.** ODS requires `mimetype` to be the first
  member and stored uncompressed, which `archive.pack` cannot do. Reading
  uses `archive.unpack` behind a check of the central directory's declared
  sizes.
- **Streaming where the format allows.** `openRows` decodes an XLSX sheet
  one row at a time. Gnumeric and CSV are not streamed: their reader holds
  the sheet and hands it out row by row behind the same cursor.
- **Performance comes from avoiding value copies.** Binding or passing a
  compound value deep-copies it, so the code keeps accumulators local
  instead of threading them through helpers, walks sheets by index, reads
  cells through an inline chain, and lexes over a character list. A
  function that returns a changed sheet or workbook copies it once, not
  twice. `nextRow` updates the cursor in place, and a cursor held in a
  top-level variable is still copied for every row, so it carries the sheet
  as strings (a string copies in constant time) and only a 256 KiB window of
  it as `bytes`; the shared strings are `bytes`, one block move where a
  list copies per element. A reference is
  spelled once per row from the column names, not rebuilt per use. `sheetOf`
  is the way to build a sheet; `setRow` per row is quadratic, as its
  docblock says. A consumer should read with `rows`, `row` or `valuesIn`
  rather than `cell` per cell. The measurements are in the Memory chapter.
- **Layout is part of the sheet.** Column widths are in characters of the
  default font, XLSX's unit; ODS stores a length, converted at 5.25 points
  a character (a 7-pixel digit at 96 dpi). A frozen pane is a count of rows
  and columns; ODS keeps it in `settings.xml`, written only when a sheet has
  one. Gnumeric and CSV carry no layout.
- **Patching keeps bytes, not the model.** `patchXlsx` rewrites only the
  rows holding a changed cell and leaves every other part alone, so a
  workbook from another application keeps what the model cannot hold. Text
  goes in inline to leave the shared strings untouched; a change that would
  break another cell (a shared formula's anchor, an array formula) or show
  wrong (a date without a date format) is refused. It is XLSX only: an ODS
  cell's place in its row depends on repeat runs, which patching would have
  to split.
- **ODS repeat runs are clamped, not refused.** Empty runs only advance the
  position; value runs expand up to a per-axis bound, and one element's
  product of both axes is clamped, because real files use huge empty runs.

## Errors

The deck throws `Error{kind: "sheets"}` (`ERROR_KIND`) for malformed files,
bad arguments and format rules (a number-format code over
`MAX_FORMAT_CODE`, an archive past the ZIP writer's member or size limits).
A reached cap is kind `"limit"`: `MAX_NESTING`, the sheet-cell cap,
`MAX_EXPORT_ROWS`, `MAX_FORMULA_TOKENS` and `MAX_FORMULA_DEPTH` at parse
time, the ZIP reader's member and inflated-size caps (including
`archive`'s own), a Gnumeric gzip member past `compress`'s output cap, and
a row past the XML decoder's nesting or node cap. The readers' wrappers
pass the generic kinds (`"limit"`, `"timeout"`, `"closed"`, `"net"`,
`"cancelled"`) on unchanged. Caps met during evaluation (`MAX_RANGE_CELLS`,
`MAX_RESOLVED_CELLS`, `MAX_TEXT_RESULT`) stay error values in the cell, as
an application shows them. Input quoted in a message is cut to 48
characters. The deck reads no server, so there is no error struct;
file-system errors from `open` and `save` pass through from `fs`.

## Security and limits

The Reading untrusted files guide documents each case; in short:

- External entities are never resolved and entity expansion cannot
  amplify: the deck decodes only the predefined entities and numeric
  references itself.
- ZIP path traversal is refused by `archive.unpack`; an archive that
  declares more than 256 MiB in total or more than 4096 members is refused
  before anything is inflated.
- ODS run-length amplification is clamped per element, and a sheet past
  one million cells is refused with a pointer to the streaming reader.
- Off-grid addresses (past `MAX_ROW` or `MAX_COLUMN`) are dropped.
- Formulas are bounded in tokens, depth, text growth (`MAX_TEXT_GROWTH`),
  range size and resolved cells; number formatting is bounded by
  `MAX_FORMATTED` and the code length; exports by `MAX_EXPORT_ROWS`.
- `writeCsvSafe` neutralises cells that a spreadsheet application would
  run as a formula.

## Testing and validation

- One overlay per topic, about 600 tests, all run through
  `src/sheets_test.j`. Fixtures are built in memory: ODS content through a
  document helper, XLSX containers member by member (deliberately not with
  the deck's own writer), so the readers are not tested only against the
  writers' assumptions. There is no `testdata/`.
- `tools/check-extra.sh` runs three external oracles when LibreOffice
  (`soffice`) and Gnumeric (`ssconvert`) are installed, as the validate
  workflow does: files written by the deck are read back by both
  applications; a list of formulas is evaluated in all three engines and
  compared; and `displayAt` is compared with LibreOffice's HTML export.
  Without them the oracles are skipped.
- The examples need nothing external and run in the gate.

Not covered: Microsoft™ Excel itself is not an oracle; XLSX output is checked
through LibreOffice and Gnumeric.

## Known limitations and open questions

- Decompression is bounded by the sizes the central directory declares; a
  directory that lies about them is still inflated (up to `archive`'s own
  cap).
- ODF cannot express a month's initial (`mmmmm` comes back as `mmm`) or
  `_x` / `*x` padding, so those formats change through ODS.

## Dependencies on the interpreter

- Floor `>=0.28.0` (the calls 0.29.0 removes are replaced by their 0.28.0 forms): the UTF-8 codecs of `encoding.encode` / `decode` and
  `strings.replicate` arrived in 0.27.0.
- `binary`'s integer readers for the ZIP structures (0.26.0).
- The bundled `csv` and `pdf` modules, and the `archive` and `compress`
  libraries.
- Caps as kind `"limit"` (`jennifer`'s M28.54, a reached cap is kind
  "limit", and M28.57, the decks follow the error conventions).
- Recalculating from a consumer program is about ten times faster on 0.26.0
  than on 0.25.0 because of fewer copies at the module boundary.
