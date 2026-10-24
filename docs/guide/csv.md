<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Delimited text

Quoting and escaping come from the `csv` module (RFC 4180). This layer adds
typing on read and formula-injection protection on write.

```jennifer
def wb as sheet.Workbook init sheet.readCsv(fs.readString("data.csv"), true);
fs.writeString("out.csv", sheet.writeCsv($wb, ""));
```

`readDelimited(body, delimiter, typed)` and
`writeDelimited(wb, sheetName, delimiter)` take any one-character separator;
TSV goes through the same code. A write takes one sheet, the first when
`sheetName` is `""`. A read produces one sheet named `CSV_SHEET_NAME`
(`"Sheet1"`).

## Typing

With `typed` set, a field becomes a boolean, an error code, a number or an ISO
date, tested in that order; anything else stays text:

```jennifer
sheet.readCsv("1,2.5,TRUE,2026-10-02,#N/A\n", true);
# number, number, bool, stamp, error
```

A number with a leading zero (`007`, `0123`) stays text, since it is almost
always an identifier. A plain `0` is a number. A field of only whitespace
stays text. An empty field is an empty cell whether or not `typed` is set.

With `typed` false every field is text.

## Formula injection

A field that starts like a formula is executed by a spreadsheet application
when someone opens the file (CWE-1236). For a file someone else will open, use
`writeCsvSafe`, which prefixes those fields so they cannot execute:

```jennifer
fs.writeString("export.csv", sheet.writeCsvSafe($wb, ""));
```

`writeCsv` writes fields unchanged, so a file you read back yourself
round-trips exactly.
