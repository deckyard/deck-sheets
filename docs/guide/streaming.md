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
is copied on every call: its 256 KiB window of the sheet and the XLSX shared
strings. Put the loop in a function.

You see each row once, in order. For random access, read the workbook.

## Cost

A 25 000-row, 20-column XLSX (500 000 cells, 16 MB of sheet XML), on
Jennifer 0.27.0, on one host:

| | time | peak RSS |
|---|---|---|
| `open`, the whole workbook | 46 s | 4.9 GB |
| `openRows` loop in a function | 41 s | 510 MB |
| `openRows` loop at top level | 51 s | 490 MB |

A row costs about what it costs in a whole read, in a tenth of the memory.
See [Memory](../internal/memory.md).

## Formats

ODS and XLSX stream. Gnumeric™ and delimited text are read whole and handed
out row by row, so the same loop works for every format.
