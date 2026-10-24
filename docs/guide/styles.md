<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Styles

A `Style` is a cell's font, colours, alignment, border and number format.

```jennifer
def header as sheet.Style init sheet.withBorder(
    sheet.withBackground(
        sheet.withAlign(sheet.withBold(sheet.style(), true), sheet.Align.Centre),
        "FFF2CC"),
    sheet.BorderStyle.Thin);

$s = sheet.setAreaStyle($s, "A1:C1", $header);
$s = sheet.setAreaStyle($s, "B2:B99", sheet.withFormat(sheet.style(), "#,##0.00"));
```

`style()` is the default, which leaves everything to the application. Each
builder returns a modified copy. Two styles that look the same are equal.

| | builder | notes |
|---|---|---|
| bold, italic, underline | `withBold`, `withItalic`, `withUnderline` | |
| font family and size | `withFont(st, name, points)` | `""` or `0.0` leaves that half unset; size 0 to 4000 |
| text colour | `withColour(st, "CC0000")` | `"#CC0000"` accepted; stored upper case |
| background fill | `withBackground(st, "FFF2CC")` | |
| horizontal alignment | `withAlign(st, Align.Centre)` | `General` (text left, numbers right) is not `Left` |
| vertical alignment | `withVerticalAlign(st, VAlign.Middle)` | |
| wrapping | `withWrap(st, true)` | |
| border | `withBorder(st, BorderStyle.Thin)` | one weight on all four edges |
| number format | `withFormat(st, "#,##0.00")` | applied by `displayAt` |

A colour that is not six hexadecimal digits throws.

## Interning

A sheet holds a table of its distinct styles and a per-cell index into it, as
both file formats do:

```jennifer
$s = sheet.setAreaStyle($s, "A1:A1000", $header);
len($s.styles);       # 2: the default, plus the header
len($s.cellStyles);   # 1000
```

Use `setAreaStyle` for more than a few cells. `setStyle` copies the sheet on
every call, the same cost as building a sheet with `setRow`; see
[The cell model](model.md#bulk-access).

Style and value are independent. Styling an empty cell gives a blank a
background or border, and clearing a cell keeps its style.

## Number formats

`withFormat` takes the code both formats use: `#,##0.00`, `yyyy-mm-dd`, `0%`,
and `;`-separated positive, negative, zero and text sections. `asString` never
applies it; `displayAt` does:

```jennifer
$s = sheet.setStyle($s, "B2", sheet.withFormat(sheet.style(), "#,##0.00"));
sheet.asString(sheet.cell($s, "B2"));   # "1234.5"
sheet.displayAt($s, "B2");              # "1,234.50"
```

See [Number formats](formats-applied.md).

Dates are the one place a format changes what is read. An XLSX date is a
number whose format says it is a date, so the reader consults
`isDateFormat`. A date cell with no style of its own still gets a date format
on write, or the application would show the serial.

## Round trips

| | ODS | XLSX | Gnumeric |
|---|---|---|---|
| font, colours, alignment, wrap, border | yes | yes | yes |
| number format code | through ODF's components | verbatim | verbatim |

ODF stores `#,##0.00` as a `number:number` element with two decimal places and
grouping; [Number formats](formats-applied.md) covers the translation and
what ODF cannot express. Gnumeric stores styles as rectangular regions; see
[Formats](formats.md#gnumeric).

`tools/validate-output.sh` exports all three formats to HTML through
LibreOffice and checks that the fill, bold, centring and two number formats
arrived. It is why the ODS writer uses `fo:font-family`: `style:font-name`
refers to a font face that must be declared separately, and LibreOffice
ignored it.

## Not carried

- Per-edge borders. One weight covers all four edges, so a box survives but a
  single underline rule becomes a box.
- Border colours, and dashed, dotted and double rules, which read back as the
  nearest weight.
- Row heights, column widths, merged cells, frozen panes.
- Conditional formatting and data validation: not read, and dropped on a
  round trip.
