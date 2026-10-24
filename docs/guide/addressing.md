<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Addressing

A `Ref` is zero-based on both axes; the A1 spelling is one-based on the row.
`cellRef` and `parseRef` convert between them.

```jennifer
sheet.cellRef(sheet.ref(6, 1));   # "B7"
sheet.parseRef("B7").row;         # 6
sheet.parseRef("B7").col;         # 1
```

## Column names

Column names are bijective base 26: there is no zero digit, so `Z` is followed
by `AA`.

```jennifer
sheet.columnName(0);     # "A"
sheet.columnName(25);    # "Z"
sheet.columnName(26);    # "AA"
sheet.columnName(701);   # "ZZ"
sheet.columnName(702);   # "AAA"

sheet.columnIndex("XFD");   # 16383
```

`columnIndex` is case-insensitive. The grid ends where XLSX ends:
`MAX_COLUMN` is 16383 (column `XFD`) and `MAX_ROW` is 1048575 (row 1048576).
A reference past either throws instead of wrapping.

## Dollar signs

`parseRef` accepts `$B$7`, `B$7` and `$B7` and drops the dollars: a `Ref` is a
position, not a formula's way of addressing it. Inside a formula they are kept;
see [Formulas](formulas.md).

## Areas

```jennifer
def box as sheet.Area init sheet.parseArea("A1:C7");
sheet.areaRef($box);                             # "A1:C7"
sheet.areaSize($box);                            # 21
sheet.areaContains($box, sheet.parseRef("B2"));  # true
```

Corners are normalised, so `C7:A1` gives the same area as `A1:C7`. A one-cell
area is written as the single reference, as both formats write it.
`area(a, b)` builds one from two corners in either order.

## Sheet-qualified references

```jennifer
sheet.sheetRef("Sheet1", "A1");         # "Sheet1!A1"
sheet.sheetRef("Second Sheet", "A1");   # "'Second Sheet'!A1"
sheet.sheetRef("Bob's", "A1");          # "'Bob''s'!A1"
sheet.sheetRef("2024", "A1");           # "'2024'!A1"
```

A name with a space or punctuation is quoted, an interior quote is doubled,
and an all-digit name is quoted because a bare `2024!A1` would read as a
cell. `splitSheetRef` is the inverse: it returns `[sheet, rest]`, with
`sheet` as `""` for an unqualified reference.
