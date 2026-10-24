<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Cheatsheet

Every exported name, written bare. In your code they carry the alias you
import the deck under (`sheet.cell(...)` in these docs). Every mutator returns
a fresh value: `$s = setCell($s, ...)`.

## Errors and version

| Constant | Value | Meaning |
| --- | --- | --- |
| `ERROR_KIND` | `"sheets"` | The `kind` of every error this deck raises |
| `MAX_NESTING` | 100 | Element depth past which a reader refuses the document |
| `VERSION` | `"0.1.0"` | The deck version, kept in step with `deck.toml` |

## Styles

| Signature | What it does |
| --- | --- |
| `style()` | The default style: everything left to the application |
| `isPlain(st as Style)` | Whether a style sets nothing |
| `withBold(st as Style, on as bool)` | Bold on or off |
| `withItalic(st as Style, on as bool)` | Italic on or off |
| `withUnderline(st as Style, on as bool)` | Underline on or off |
| `withFont(st as Style, name as string, size as float)` | Font family and size in points; `""` or `0.0` leaves that half alone |
| `withColour(st as Style, rgb as string)` | Text colour, `"RRGGBB"` (a leading `#` is accepted) |
| `withBackground(st as Style, rgb as string)` | Background fill, `"RRGGBB"` |
| `withAlign(st as Style, how as Align)` | Horizontal alignment |
| `withVerticalAlign(st as Style, how as VAlign)` | Vertical alignment |
| `withWrap(st as Style, on as bool)` | Wrap long text or not |
| `withBorder(st as Style, weight as BorderStyle)` | One border weight on all four edges |
| `withFormat(st as Style, code as string)` | Number format code; `General` is stored as `""` |
| `isDateFormat(st as Style)` | Whether the style's format code shows a date |

### `Style`

Two styles that look the same are equal, which is what lets a sheet intern
them. `""` and `0.0` mean "not set", so the application default applies.

| Field | What it holds |
| --- | --- |
| `bold as bool` | bold text |
| `italic as bool` | italic text |
| `underline as bool` | underlined text |
| `fontName as string` | font family, `""` for the default |
| `fontSize as float` | size in points, `0.0` for the default |
| `colour as string` | text colour `"RRGGBB"`, `""` for the default |
| `background as string` | fill colour `"RRGGBB"`, `""` for none |
| `align as Align` | horizontal alignment |
| `valign as VAlign` | vertical alignment |
| `wrap as bool` | wrap long text |
| `border as BorderStyle` | weight drawn on all four edges |
| `format as string` | number format code, `""` for General |

### `Align`

| Variant | Meaning |
| --- | --- |
| `General` | The format's default: text left, numbers right. Not the same as `Left` |
| `Left` | Left |
| `Centre` | Centred |
| `Right` | Right |

### `VAlign`

| Variant | Meaning |
| --- | --- |
| `Bottom` | Bottom |
| `Middle` | Middle |
| `Top` | Top |

### `BorderStyle`

Dashed, dotted and double rules read back as the nearest of these.

| Variant | Meaning |
| --- | --- |
| `NoBorder` | No border |
| `Thin` | Thin rule |
| `Medium` | Medium rule |
| `Thick` | Thick rule |

## Values

| Signature | What it does |
| --- | --- |
| `empty()` | An empty cell |
| `text(body as string)` | A text cell |
| `number(amount as float)` | A numeric cell |
| `integer(amount as int)` | A numeric cell from an int (stored as a float) |
| `boolean(flag as bool)` | A boolean cell |
| `date(at as time.Time)` | A date cell, no time of day |
| `stamp(at as time.Time)` | A date-and-time cell |
| `formula(source as string, cached as string)` | A formula cell: A1 expression without `=`, and its last result |
| `errorValue(code as string)` | An error cell such as `"#N/A"` |
| `isEmpty(v as Value)` | Whether a cell holds nothing |
| `kindOf(v as Value)` | The variant's name |
| `asString(v as Value)` | The value as text; a formula gives its cached result |
| `asNumber(v as Value)` | The value as a number; throws when there is no numeric reading |
| `asBool(v as Value)` | The value as a boolean; throws when there is none |
| `asTime(v as Value)` | The value as an instant; a number is read as a 1900 date serial |
| `parseIsoDate(body as string)` | Read an ODS `date-value` attribute |
| `toSerial(at as time.Time, date1904 as bool)` | The date serial for an instant |
| `fromSerial(serial as float, date1904 as bool)` | The instant a date serial names |

### `Value`

The zero value is `Empty`, which is also what an absent cell reads as.

| Variant | Payload |
| --- | --- |
| `Empty` | - |
| `Text` | `body as string` |
| `Number` | `amount as float` |
| `Bool` | `flag as bool` |
| `Stamp` | `at as time.Time, dateOnly as bool` |
| `Formula` | `source as string, cached as string` |
| `Err` | `code as string` |

## Workbooks and sheets

| Signature | What it does |
| --- | --- |
| `newSheet(name as string)` | An empty sheet; throws on a name no application accepts |
| `newWorkbook()` | A workbook with no sheets |
| `workbookWith(name as string)` | A workbook holding one empty sheet |
| `cell(s as Sheet, at as string)` | A cell's value by A1 reference; not for loops |
| `cellAt(s as Sheet, at as Ref)` | A cell's value by reference; not for loops |
| `setCell(s as Sheet, at as string, v as Value)` | Set a cell; `Empty` removes it |
| `setCellAt(s as Sheet, at as Ref, v as Value)` | Set a cell by reference |
| `styleAt(s as Sheet, at as string)` | A cell's style; the default when it has none |
| `styleAtRef(s as Sheet, at as Ref)` | A cell's style by reference |
| `setStyle(s as Sheet, at as string, st as Style)` | Set a cell's style; the default style removes the entry |
| `setStyleAt(s as Sheet, at as Ref, st as Style)` | Set a cell's style by reference |
| `setAreaStyle(s as Sheet, ref as string, st as Style)` | One style across an area, in one copy of the sheet |
| `clearCell(s as Sheet, at as string)` | Remove a cell's value; extent and style stay |
| `cellCount(s as Sheet)` | How many cells are stored |
| `extent(s as Sheet)` | The area the cells span |
| `row(s as Sheet, row as int)` | One row of values, padded to the sheet width |
| `rows(s as Sheet)` | Every row, top to bottom |
| `valuesIn(s as Sheet, ref as string)` | Every value in an area, row by row, `Empty` outside the sheet |
| `setRow(s as Sheet, row as int, values as list of Value)` | Replace a row from column A |
| `sheetOf(name as string, lines as list of list of Value)` | Build a sheet from rows in one pass |
| `addRow(s as Sheet, values as list of Value)` | Append a row below everything |
| `sheetByName(wb as Workbook, name as string)` | A sheet by name; throws naming the sheets there are |
| `hasSheet(wb as Workbook, name as string)` | Whether the sheet exists |
| `sheetNames(wb as Workbook)` | The sheet names in file order |
| `putSheet(wb as Workbook, s as Sheet)` | Replace the sheet of the same name, or append |
| `addSheet(wb as Workbook, s as Sheet)` | Append; throws on a duplicate name |
| `removeSheet(wb as Workbook, name as string)` | Remove; throws on the last sheet |
| `renameSheet(wb as Workbook, from as string, to2 as string)` | Rename in place |

### `Sheet`

Read and write cells through the functions above, not the maps: the keys are
the canonical A1 spelling `cellRef` produces.

| Field | What it holds |
| --- | --- |
| `name as string` | sheet name |
| `cells as map of string to Value` | non-empty cells, keyed by A1 |
| `cellStyles as map of string to int` | style index per cell, keyed by A1 |
| `styles as list of Style` | interned styles, index 0 the default |
| `rowCount as int` | one past the highest row index used |
| `colCount as int` | one past the highest column index used |

### `Workbook`

| Field | What it holds |
| --- | --- |
| `sheets as list of Sheet` | sheets in file order |
| `date1904 as bool` | date serials count from 1904 (old Mac files) rather than 1900 |

## Addressing

All indices are zero-based: `B7` is row 6, column 1.

| Signature | What it does |
| --- | --- |
| `ref(row as int, col as int)` | A reference; throws off the grid |
| `columnName(col as int)` | `0` -> `"A"`, `26` -> `"AA"` |
| `columnIndex(name as string)` | `"XFD"` -> `16383`, case-insensitive |
| `cellRef(at as Ref)` | The A1 spelling |
| `parseRef(text as string)` | Read an A1 reference; `$` markers are dropped |
| `area(a as Ref, b as Ref)` | An area from two corners in either order |
| `areaRef(box as Area)` | The A1 spelling; a one-cell area is the single reference |
| `parseArea(text as string)` | Read an area, with or without a colon |
| `areaSize(box as Area)` | How many cells it covers |
| `areaContains(box as Area, at as Ref)` | Whether it covers a cell |
| `splitSheetRef(text as string)` | `[sheet, rest]`, sheet `""` when unqualified |
| `sheetRef(sheetName as string, cell as string)` | `Sheet!A1`, quoting the name when needed |

| Constant | Value | Meaning |
| --- | --- | --- |
| `MAX_COLUMN` | 16383 | Last column index (`XFD`) |
| `MAX_ROW` | 1048575 | Last row index (row 1048576) |

### `Ref`

| Field | What it holds |
| --- | --- |
| `row as int` | row index, 0 for row 1 |
| `col as int` | column index, 0 for column A |

### `Area`

Inclusive on both corners.

| Field | What it holds |
| --- | --- |
| `from as Ref` | top-left corner |
| `to2 as Ref` | bottom-right corner |

## Formats and files

| Signature | What it does |
| --- | --- |
| `formatOf(name as string)` | The format the extension names; throws on an unknown one |
| `formatOfBytes(raw as bytes)` | The format the bytes identify (not CSV/TSV) |
| `readFormat(raw as bytes, kind as Format)` | Read bytes as a format |
| `writeFormat(wb as Workbook, kind as Format)` | Write a format to bytes; CSV/TSV write the first sheet |
| `open(filePath as string)` | Read a file, format by extension |
| `openDetected(filePath as string)` | Read a file, format by content |
| `save(wb as Workbook, filePath as string)` | Write a file, format by extension |
| `formatName(kind as Format)` | `"ods"`, `"xlsx"`, `"gnumeric"`, `"csv"` or `"tsv"` |

### `Format`

| Variant | Extensions |
| --- | --- |
| `Ods` | `.ods` |
| `Xlsx` | `.xlsx`, `.xlsm` |
| `Gnumeric` | `.gnumeric`, `.gnm` |
| `Csv` | `.csv` |
| `Tsv` | `.tsv`, `.tab` |

## Streaming rows

| Signature | What it does |
| --- | --- |
| `openRows(filePath as string, sheetName as string)` | A cursor over a sheet of a file; `""` for the first sheet |
| `openRowsFromBytes(raw as bytes, kind as Format, sheetName as string)` | The same over bytes in memory |
| `hasRow(r as RowReader)` | Whether another row is waiting |
| `nextRow(r as RowReader)` | Advance to the next row |
| `rowValues(r as RowReader)` | The current row as values |
| `rowNumber(r as RowReader)` | The current row's one-based number |
| `rowStrings(r as RowReader)` | The current row as text |

### `RowReader`

Treat it as opaque and use the functions above.

| Field | What it holds |
| --- | --- |
| `src as bytes` | the part holding the sheet |
| `at as int` | scan position |
| `limit as int` | end of the sheet's rows |
| `rowIndex as int` | zero-based index of the current row |
| `values as list of Value` | the current row |
| `more as bool` | whether another row is waiting |
| `kind as Format` | which markup is being walked |
| `shared as list of string` | XLSX shared string table |
| `dateStyles as map of string to bool` | XLSX styles that mean a date |
| `date1904 as bool` | the workbook's date system |

## OpenDocument

| Signature | What it does |
| --- | --- |
| `readOds(raw as bytes)` | Read an ODS container |
| `readOdsContent(content as bytes)` | Read an ODS `content.xml` on its own |
| `odsFormulaSource(raw as string)` | An ODS formula attribute in the model's A1 dialect |
| `writeOds(wb as Workbook)` | Write an ODS container |
| `writeOdsContent(wb as Workbook)` | Write only `content.xml` |

| Constant | Value | Meaning |
| --- | --- | --- |
| `ODS_MIMETYPE` | `application/vnd.oasis.opendocument.spreadsheet` | The media type in the `mimetype` member |

## Office Open XML

| Signature | What it does |
| --- | --- |
| `readXlsx(raw as bytes)` | Read an XLSX container |
| `writeXlsx(wb as Workbook)` | Write an XLSX container |

## Gnumeric

| Signature | What it does |
| --- | --- |
| `readGnumeric(raw as bytes)` | Read a Gnumeric file, gzipped or not |
| `writeGnumeric(wb as Workbook)` | Write a gzipped Gnumeric file |
| `writeGnumericXml(wb as Workbook)` | Write the uncompressed document |

## Delimited text

| Signature | What it does |
| --- | --- |
| `readCsv(body as string, typed as bool)` | Read CSV into a one-sheet workbook |
| `readDelimited(body as string, delimiter as string, typed as bool)` | The same with any one-character separator |
| `writeCsv(wb as Workbook, sheetName as string)` | One sheet as CSV; `""` for the first |
| `writeDelimited(wb as Workbook, sheetName as string, delimiter as string)` | The same with any one-character separator |
| `writeCsvSafe(wb as Workbook, sheetName as string)` | CSV with formula injection neutralised |

| Constant | Value | Meaning |
| --- | --- | --- |
| `CSV_SHEET_NAME` | `"Sheet1"` | The name of the sheet a CSV read produces |

## Formula dialects

| Signature | What it does |
| --- | --- |
| `toA1Formula(source as string)` | OpenFormula (`[.B3]*[.C2]`) to A1 (`B3*C2`) |
| `toOpenFormula(source as string)` | A1 to OpenFormula |

## Number formats

`asString` gives the value; these give what an application shows. See
[Number formats](guide/formats-applied.md).

| Signature | What it does |
| --- | --- |
| `applyFormat(v as Value, code as string)` | A value through a format code |
| `displayAt(s as Sheet, at as string)` | A cell through its own style's format |
| `displayAtRef(s as Sheet, at as Ref)` | The same by reference |
| `displayRow(s as Sheet, row as int)` | One row as shown |
| `displayRows(s as Sheet)` | Every row as shown |
| `builtinFormat(id as int)` | The code an XLSX built-in `numFmtId` stands for |
| `defaultLocale()` | Dot, comma and English names |
| `withSeparators(it as Locale, decimal as string, grouping as string)` | Other separators |
| `withMonthNames(it as Locale, full as list of string, short as list of string)` | Other month names |
| `withDayNames(it as Locale, full as list of string, short as list of string)` | Other weekday names |
| `applyFormatIn(v as Value, code as string, locale as Locale)` | `applyFormat` in a locale |
| `displayAtIn(s as Sheet, at as string, locale as Locale)` | `displayAt` in a locale |
| `displayRowsIn(s as Sheet, locale as Locale)` | `displayRows` in a locale |

| Constant | Value | Meaning |
| --- | --- | --- |
| `MAX_FORMATTED` | 1e15 | Above this magnitude a number renders plainly |
| `MAX_FORMAT_CODE` | 255 | A longer code is not read; the value renders plainly |

### `Locale`

| Field | What it holds |
| --- | --- |
| `decimal as string` | decimal separator |
| `grouping as string` | thousands separator |
| `months as list of string` | twelve month names, January first; `[]` for English |
| `monthAbbrevs as list of string` | their short forms; `[]` cuts the full names |
| `days as list of string` | seven weekday names, Sunday first; `[]` for English |
| `dayAbbrevs as list of string` | their short forms; `[]` cuts the full names |

## Formula evaluation

See [Evaluating formulas](guide/evaluation.md).

| Signature | What it does |
| --- | --- |
| `evaluate(wb as Workbook, sheetName as string, source as string)` | Compute one A1 expression; a leading `=` is ignored |
| `recalculate(wb as Workbook, sheetName as string)` | Recompute every formula cell on a sheet |
| `isErrorValue(v as Value)` | Whether a value is an error |
| `tokenize(source as string)` | Split a formula into tokens |
| `parseFormula(source as string)` | Parse a formula into a tree |

| Constant | Value | Meaning |
| --- | --- | --- |
| `ERR_DIV0` | `#DIV/0!` | Division or modulo by zero |
| `ERR_VALUE` | `#VALUE!` | An argument of the wrong type |
| `ERR_REF` | `#REF!` | A reference to nothing |
| `ERR_NAME` | `#NAME?` | Unknown function or defined name |
| `ERR_NUM` | `#NUM!` | A number outside the operation's domain, or a range over `MAX_RANGE_CELLS` |
| `ERR_NA` | `#N/A` | A lookup found nothing |
| `ERR_CIRCULAR` | `#REF!` | A formula depends on itself |
| `MAX_FORMULA_DEPTH` | 64 | Bracket nesting and prefix-operator runs |
| `MAX_FORMULA_TOKENS` | 512 | Tokens in one formula; parsing is quadratic in it |
| `MAX_RESOLVED_CELLS` | 500000 | Cells one evaluation may resolve |
| `MAX_RANGE_CELLS` | 1000000 | Cells one range may cover |
| `MAX_TEXT_RESULT` | 32767 | Characters in one text result, which bounds `REPT` |
| `MAX_TEXT_GROWTH` | 2097152 | Characters one evaluation may build by concatenation |

### `Recalculated`

| Field | What it holds |
| --- | --- |
| `sheet as Sheet` | the sheet with results written into the caches |
| `evaluated as int` | formula cells computed |
| `failed as int` | of those, how many yielded an error |

### `Token`

A range such as `A1:B2` is one `Reference`; a bare `TRUE` is a `Logical`.

| Variant | Payload |
| --- | --- |
| `Number` | `amount as float` |
| `Text` | `body as string` |
| `Logical` | `flag as bool` |
| `Reference` | `body as string` |
| `Name` | `body as string` |
| `Operator` | `symbol as string` |
| `OpenParen` | - |
| `CloseParen` | - |
| `Separator` | - |
| `ErrorToken` | `code as string` |

### `Expr`

| Variant | Payload |
| --- | --- |
| `Num` | `amount as float` |
| `Str` | `body as string` |
| `Logic` | `flag as bool` |
| `ErrLit` | `body as string` |
| `Cell` | `body as string` |
| `Span` | `body as string` |
| `NameRef` | `name as string` |
| `Unary` | `symbol as string, parts as list of Expr` |
| `Binary` | `symbol as string, parts as list of Expr` |
| `Call` | `name as string, parts as list of Expr` |

## Exports

One-way; see [Exporting](guide/exporting.md).

| Signature | What it does |
| --- | --- |
| `toHtml(s as Sheet)` | One `<table>`, styles inline |
| `workbookToHtml(wb as Workbook)` | Every sheet as a labelled table |
| `toHtmlDocument(s as Sheet, title as string)` | A standalone page |
| `toRecords(s as Sheet)` | Rows as maps keyed by the header row |
| `toJson(s as Sheet)` | The records as indented JSON |
| `toJsonLines(s as Sheet)` | The records, one JSON object per line |
| `toPdf(s as Sheet, size as PageSize)` | A paginated PDF table |
| `a4()` | A4 portrait: 595 x 842 pt, margin 40, 9 pt text |
| `a4Landscape()` | A4 landscape: 842 x 595 pt, margin 40, 9 pt text |
| `letter()` | US Letter portrait: 612 x 792 pt, margin 40, 9 pt text |

| Constant | Value | Meaning |
| --- | --- | --- |
| `MAX_EXPORT_ROWS` | 100000 | Rows past which every export refuses the sheet |

### `PageSize`

All in PDF points.

| Field | What it holds |
| --- | --- |
| `width as int` | page width |
| `height as int` | page height |
| `margin as int` | margin on every side |
| `fontSize as int` | text size |
