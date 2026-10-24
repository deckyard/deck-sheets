<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# The cell model

A `Workbook` holds an ordered list of `Sheet`s, a `Sheet` holds cells keyed by
A1 reference, and a cell holds a `Value`. Every format reads into and writes
from this model.

## Value

`Value` is a sum type, so a `match` over it is exhaustive:

```jennifer
def v as sheet.Value init sheet.cell($s, "B7");
match ($v) {
    when Empty { io.printf("nothing\n"); }
    when Text(t) { io.printf("text %s\n", $t.body); }
    when Number(n) { io.printf("number %f\n", $n.amount); }
    when Bool(b) { io.printf("bool %t\n", $b.flag); }
    when Stamp(st) { io.printf("date %s\n", time.iso($st.at)); }
    when Formula(f) { io.printf("=%s was %s\n", $f.source, $f.cached); }
    when Err(e) { io.printf("error %s\n", $e.code); }
}
```

An absent cell reads as `Empty`, the zero value, so walking a rectangle needs
no presence test. `Err` is spelled short because `Error` is Jennifer's own
error struct.

Constructors: `empty()`, `text(body)`, `number(amount)`, `integer(n)`,
`boolean(flag)`, `date(at)`, `stamp(at)`, `formula(source, cached)`,
`errorValue(code)`.

### Coercion

`asString`, `asNumber`, `asBool` and `asTime` convert where there is a
sensible reading:

```jennifer
sheet.asNumber(sheet.text("42"));     # 42.0
sheet.asString(sheet.number(4.0));    # "4", not "4.0"
sheet.asBool(sheet.text("TRUE"));     # true
sheet.asTime(sheet.number(46297.0));  # 2026-10-02, a 1900-system date serial
```

They throw where there is none (`asNumber` of `"north"`, anything numeric from
an error cell), so summing a column with a stray label fails instead of adding
zero. `kindOf(v)` names the variant.

## Sheet

```jennifer
def s as sheet.Sheet init sheet.newSheet("Q3");
$s = sheet.setCell($s, "A1", sheet.text("Name"));
$s = sheet.setRow($s, 1, [sheet.text("Widget"), sheet.integer(4)]);
$s = sheet.addRow($s, [sheet.text("Gadget"), sheet.integer(2)]);
```

Every mutator returns a fresh sheet and leaves its argument alone.

Cells are stored sparsely. `cellCount($s)` counts stored cells; `extent($s)`
is the area they span, also held as `$s.rowCount` / `$s.colCount`. Setting a
cell to `Empty` removes it. The extent grows to cover a cell and never shrinks,
as in both file formats.

## Bulk access

A `Sheet` is a value, so every call across the module boundary copies its
cell map. Reading 5 000 cells one `cellAt` at a time measured **10.9 s**; the
same cells through `rows()` took **70 ms**.

```jennifer
for (def line in sheet.rows($s)) { process($line); }      # every row
def block as list of list of sheet.Value init
    sheet.valuesIn($s, "A1:C7");                          # one rectangle
def line as list of sheet.Value init sheet.row($s, 0);     # one row
```

`cell()` and `cellAt()` are for a few lookups at known references, not loops.

Building has the same cost. Each `setRow` or `addRow` copies the map once, so
filling a 2 000-row sheet row by row measured 72 s against 0.4 s for
`sheetOf`, which builds a sheet from a list of rows in one pass. Use `sheetOf`
for data you already have and `setRow` to change a row of an existing sheet.

For a sheet too large to hold at all, see [Reading large sheets](streaming.md).

## Workbook

```jennifer
def wb as sheet.Workbook init sheet.workbookWith("Sheet1");
$wb = sheet.addSheet($wb, sheet.newSheet("Q4"));
$wb = sheet.putSheet($wb, $s);          # replace by name, or append
$wb = sheet.renameSheet($wb, "Sheet1", "Q3");
$wb = sheet.removeSheet($wb, "Q4");
```

`sheetByName`, `hasSheet` and `sheetNames` read it. `addSheet` refuses a
duplicate name. `putSheet` replaces the sheet of the same name or appends it,
which completes an edit. `removeSheet` refuses to remove the last sheet,
because neither format allows a workbook with none.

A sheet name is checked when it is set: non-empty, at most 31 characters, none
of `[ ] * ? : / \`, and no quote at either end. An application would refuse
the file otherwise.

Cells also carry styles, interned in a per-sheet table and set with `setStyle`
and `setAreaStyle`; see [Styles](styles.md).

`$wb.date1904` is the workbook's date system: false except in old Mac
workbooks. See [Formats](formats.md).
