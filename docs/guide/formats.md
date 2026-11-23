<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Formats

```jennifer
sheet.save(sheet.open("in.xlsx"), "out.ods");
```

`open` and `save` choose the format by extension, `openDetected` by the
file's bytes. `readFormat` and `writeFormat` take a `Format`, and each codec
has its own `bytes` entry point (`readOds`, `writeXlsx`, ...).

```jennifer
sheet.formatOf("sales.xlsx");                  # Format.Xlsx
sheet.formatOfBytes(fs.readBytes("x.bin"));    # by signature
sheet.formatName(sheet.Format.Ods);            # "ods"
```

Extensions: `.ods`, `.xlsx`, `.xlsm`, `.gnumeric`, `.gnm`, `.csv`, `.tsv`,
`.tab`. `formatOfBytes` recognises the two ZIP containers by their members, a
gzip stream as Gnumeric, and uncompressed Gnumeric XML by its first 512 bytes.
Delimited text has no signature and is not detected. Through `readFormat` and
`writeFormat`, CSV and TSV are UTF-8, read with typing on, and written from the
first sheet.

## What each format keeps

| | ODS | XLSX | Gnumeric | CSV / TSV |
|---|---|---|---|---|
| text, numbers, booleans | yes | yes | yes | yes |
| several sheets | yes | yes | yes | no, one |
| dates as dates | yes | yes | as a serial number | as ISO text |
| error codes | yes | yes | yes | as text |
| formula expression | yes | yes | yes | no |
| formula cached result | yes | yes | **no** | the result only |
| sheet names | yes | yes | yes | no |
| styles (fonts, colours, borders) | yes | yes | yes | no |
| number format code | yes | yes | yes | no |
| column widths, frozen panes | yes | yes | no | no |

ODS and XLSX keep everything the model holds, in a round trip and in a
conversion between them. Gnumeric loses a formula's cached result and turns a
date into its serial number. ODS stores a format code as a tree of components,
so the code is taken apart on write and rebuilt on read; see
[Number formats](formats-applied.md). Tests assert each of these losses.

## OpenDocument (.ods)

A ZIP container of XML. The reader tolerates a missing `mimetype` member
(some writers omit it) and refuses one that declares another document type.

- **Run-length encoding.** ODS compresses empty space; a row is routinely
  padded with `table:number-columns-repeated="16384"`. Runs that carry a value
  are expanded; empty runs only advance the position, so a small file does not
  become millions of cells. The writer compresses runs again.
- **Mixed content.** Styled text inside a cell is a `<text:span>`, a run of
  spaces is `<text:s/>`, and tabs and line breaks have their own elements. The
  reader keeps document order, so `a<text:span>B</text:span>b` reads as `aBb`,
  not `abB`.
- **Number styles** are read from both `content.xml` and `styles.xml`, and a
  column's `table:default-cell-style-name` applies to cells that name no style.

The writer puts `mimetype` first and uncompressed, as ODF requires; see
[The ZIP container](../internal/zip.md).

ODF has no error type, so an error is written as the cell's text with no value
type, and the reader turns it back into an error. A text cell that looks like
an error code (`#N/A`) therefore reads back as an error.

## Office Open XML (.xlsx)

A ZIP container of XML with `[Content_Types].xml`, relationship parts, a
shared string table and an indexed style sheet.

- **Sheets are found through relationships**, not by part name. Nothing says
  `sheet1.xml`, `sheet2.xml` are in tab order; the workbook's sheet list is.
- **Text is in a shared table**, one entry per distinct string. Rich text is
  split into `<r>` runs, which the reader joins.
- **A date is a number with a date format.** The reader resolves `c/@s`
  through `cellXfs` to a `numFmtId`, treats built-in formats 14-22 and 45-47 as
  dates, and checks a custom format code for date tokens outside quoted
  literals. `46297` and `2026-10-02` differ only in that style. The writer adds
  the two date formats it needs.
- **Absent cells are not written.** A cell carries its own reference, and the
  reader trusts `r` over position.
- **Excel's extension attributes** (`x14ac:dyDescent` on nearly every row of a
  file Excel 2010 or later saved) are declared on `<worksheet>`; both readers
  carry those declarations into each row they decode.
- **Built-in number formats** are written by their id, as Excel writes them:
  `@` is 49, `0.00` is 2. Date and time codes are always written as the file's
  own formats, because Excel draws its built-in date ids in each reader's
  locale.

### Changing cells of an existing file

A read and a write rebuild every part from the model, so whatever the model
does not hold (charts, defined names, conditional formats) is gone, and the
styles and shared strings are renumbered. To fill in a few cells of someone
else's workbook, patch it instead:

```jennifer
def raw as bytes init fs.readBytes("report.xlsx");
fs.writeBytes("report.xlsx", sheet.patchXlsx($raw, "Summary", {
    "D2": sheet.number(1250.0),
    "D3": sheet.text("checked")
}));
```

Every other part keeps its bytes, and so do the untouched rows and cells of
the sheet. A replaced cell keeps its style. Text is written inline, so the
shared string table is not touched; `Empty` clears a value and keeps the
style. A formula goes in with the cached result its `Value` carries.

Refused rather than written wrong: the cell holding a shared formula other
cells use, a cell inside an array formula, and a date in a cell without a
date format. When a formula cell gets a plain value, `calcChain.xml` would
point at a cell with no formula, so it is dropped and Excel rebuilds it.
A worksheet written with a namespace prefix, or one cut short, is not patched.

## Gnumeric

One gzipped XML document; an uncompressed one is read too.

Cells are addressed by zero-based `Row` and `Col` attributes. A formula is
stored as its expression with a leading `=`, and Gnumeric recalculates on
open, so there is no cached result to store.

Styles are a `<gnm:Styles>` block of rectangular regions before the cells,
each naming a span of rows and columns and the style its cells take. The
writer emits regions for styled cells only and merges adjacent cells with the
same style into one region, the shape `ssconvert` writes. The reader never
expands a region whose style sets nothing: Gnumeric fills a sheet's unused
area with one region over all 16 384 columns and 1 048 576 rows, which would
be 17 billion entries.

## Delimited text

See [Delimited text](csv.md).
