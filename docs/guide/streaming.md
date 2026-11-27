<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Reading large sheets

`open` builds the whole workbook in memory. For a sheet of hundreds of
thousands of cells, walk it a row at a time instead:

```jennifer
func importRows(filePath as string) {
    def r as sheet.RowReader init sheet.openRows($filePath, "Sheet1");
    while (sheet.hasRow($r)) {
        $r = sheet.nextRow($r);
        process(sheet.rowStrings($r));
    }
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

`nextRow` updates the cursor and hands it back, so inside a function
`$r = nextRow($r)` moves it without a copy. A cursor in a top-level variable
is copied on every call, but only its 64 KiB window of the sheet copies byte
by byte; the rest is strings, which copy in constant time. A loop in a
function is still somewhat faster.

You see each row once, in order. For random access, read the workbook.

## Cost

A 25 000-row, 20-column XLSX (500 000 cells, 16 MB of sheet XML, 5.6 MB of
shared strings), on a 0.28.0 development build, on one host:

| | time | peak RSS |
|---|---|---|
| `open`, the whole workbook | 27 s | 970 MB |
| `openRows` loop in a function | 19 s | 165 MB |
| `openRows` loop at top level | 22 s | 175 MB |

A row costs less than in a whole read, in a sixth of the memory.
See [Memory](../internal/memory.md).

## Formats

ODS and XLSX stream. Gnumeric™ and delimited text are read whole and handed
out row by row, so the same loop works for every format.
