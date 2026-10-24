<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Reading large sheets

`open` builds the whole workbook in memory. For a sheet of hundreds of
thousands of cells, walk it a row at a time instead:

```jennifer
def r as sheet.RowReader init sheet.openRows("huge.xlsx", "Sheet1");
while (sheet.hasRow($r)) {
    $r = sheet.nextRow($r);
    process(sheet.rowStrings($r));
}
```

`rowValues($r)` gives the current row as `Value`s and `rowStrings($r)` as
text. `rowNumber($r)` is one-based and 0 before the first row. For XLSX it is
the row's own `r` number, so skipped empty rows show as gaps. For ODS it counts
`<table:table-row>` elements, so a run written as one element with
`table:number-rows-repeated` counts once.

`""` as the sheet name takes the first sheet. `openRowsFromBytes(raw, kind,
name)` does the same over bytes already in memory. The reader is a value over
those bytes, not a file handle: advance it with `$r = nextRow($r)`, and there
is nothing to close.

You see each row once, in order. For random access, read the workbook.

## Memory

A 25 000-row, 20-column XLSX (500 000 cells, 15 MB of sheet XML), on one host:

| | peak RSS |
|---|---|
| `xml.decode` of the sheet into a tree | 5.11 GB |
| `openRows` | 148 MB |

Reading the whole workbook at this size is slower still, since it also builds
a cell map entry for every cell. See [Memory](../internal/memory.md).

## Formats

ODS and XLSX stream. Gnumeric and delimited text are read whole and handed
out row by row, so the same loop works for every format.
