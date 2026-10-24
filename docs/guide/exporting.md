<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Exporting

HTML, JSON and PDF output for destinations that are not spreadsheets. None of
them is read back; use ODS, XLSX or CSV for a file that has to round-trip.

Every export lays out its whole result in memory and refuses a sheet of more
than `MAX_EXPORT_ROWS` (100 000) rows. For larger sheets, see
[Reading large sheets](streaming.md).

## HTML

```jennifer
fs.writeString("q3.html", sheet.toHtmlDocument($s, "Q3 revenue"));
fs.writeString("table.html", sheet.toHtml($s));          # the <table> only
fs.writeString("book.html", sheet.workbookToHtml($wb));  # every sheet
```

Styles become inline CSS: weight, slant, underline, font family and size,
colour, background, alignment, wrapping and borders. Cells are shown through
their number formats, so `0.075` formatted `0.0%` shows `7.5%`. Content is
escaped, so a cell holding `<script>` is text.

## JSON

The first row is the header and supplies the keys:

```jennifer
fs.writeString("rows.json", sheet.toJson($s));
fs.writeString("rows.jsonl", sheet.toJsonLines($s));   # one object per line
def records as list of map of string to string init sheet.toRecords($s);
```

Every value is a string, the same text `asString` gives. A column holding
`12`, `12.5` and `n/a` has no single JSON type, and guessing per cell would
give a schema that changes with the data. Number formats are not applied; for
formatted text, build records from `displayRows`.

A blank header cell becomes its column letter and a repeated header is
disambiguated, so every key is distinct. A sheet with no rows has no header
and throws. Jennifer's JSON encoder writes `&` as `&`, which decodes back
to `&`.

## PDF

```jennifer
fs.writeBytes("q3.pdf", sheet.toPdf($s, sheet.a4()));
fs.writeBytes("wide.pdf", sheet.toPdf($s, sheet.a4Landscape()));
fs.writeBytes("us.pdf", sheet.toPdf($s, sheet.letter()));
```

All three page sizes use a 40 pt margin and 9 pt text; build a `PageSize` for
anything else. Column widths follow the widest cell in each column, measured
in the page font on the formatted text and scaled to fit the paper. Text too
wide for its column is truncated. A row that does not fit starts a new page,
which repeats the header row.

Bold and italic select the matching standard PDF font, a background is a
filled rectangle, and a border is drawn lines. A font family is not used:
embedding one needs the font file.
