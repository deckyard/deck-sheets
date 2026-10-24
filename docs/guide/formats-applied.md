<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Number formats

A cell holds a value and, in its style, a format code for showing it. `0.075`
with the code `0.0%` is still the value 0.075; `7.5%` is what a person sees.

```jennifer
sheet.asString(sheet.cell($s, "B2"));    # "0.075"
sheet.displayAt($s, "B2");               # "7.5%"
```

Use `asString` when a program reads the number and `displayAt` when a person
does.

## Applying a format

The `display` functions take the code from the cell's style:

```jennifer
sheet.displayAt($s, "B2");                 # by A1 reference
sheet.displayAtRef($s, sheet.ref(1, 1));   # by Ref
sheet.displayRow($s, 1);                   # one row, as list of string
sheet.displayRows($s);                     # the whole sheet
```

Prefer `displayRow` and `displayRows` to a loop of `displayAt`: one cell at a
time across the module boundary costs 155x as much as taking a row (see
[The cell model](model.md#bulk-access)).

`applyFormat` takes a code directly:

```jennifer
sheet.applyFormat(sheet.number(1234.5), "#,##0.00");       # "1,234.50"
sheet.applyFormat(sheet.number(-20.0), "0.00;(0.00)");     # "(20.00)"
sheet.applyFormat(sheet.date($when), "d mmm yyyy");        # "2 Oct 2026"
```

The formula function `TEXT` uses the same engine.

## Format codes

| | Code | 1234.567 shows as |
|---|---|---|
| fixed places | `0.00` | `1234.57` |
| optional places | `0.##` | `1234.57` |
| minimum digits | `00000` | `01235` |
| grouping | `#,##0.00` | `1,234.57` |
| scaling by a thousand | `0,` | `1` |
| per cent | `0.0%` | `123456.7%` |
| scientific | `0.00E+00` | `1.23E+03` |
| fractions | `# ?/?` | `1234 4/7` |
| literals | `$#,##0.00` | `$1,234.57` |
| quoted text | `"n="0` | `n=1234.57` |

Up to four `;`-separated sections apply to positive, negative, zero and text:

```
0.00;(0.00);"nil";"<"@">"
```

Conditions replace the sign rule, and the first matching section wins:

```
[>=1000]0.0,"k";[<0]"owed";0.0
```

Dates and times use `yyyy`, `mmm`, `dddd`, `hh:mm:ss`, `AM/PM` and so on.
`[h]` counts elapsed hours, so a timesheet can show 36 hours. `[Red]` and
`[$-409]` are dropped from the output: a colour in a code does not set
`Style.colour`.

`m` is the month in `mm/dd/yyyy` and the minute in `hh:mm`. As in both
applications, an `m` next to an hour or seconds token means minutes.

A fill (`*x`) contributes nothing, because it repeats to the column width and
there is no column here. A skip (`_x`) renders as one space.

A code longer than `MAX_FORMAT_CODE` (255) is not read and the value renders
plainly, as does a number larger than `MAX_FORMATTED` (1e15), past which the
digit arithmetic would overflow. See
[Reading untrusted files](untrusted.md#a-format-code-is-untrusted-input-too).

## Where the rules come from

The renderings were checked against the applications, not taken from a
specification. `tools/formula-oracle.sh` evaluates every code in
`tools/formula-oracle.txt` here, in LibreOffice and in Gnumeric, and diffs the
three. `tools/format-oracle.sh` writes a grid of formatted cells through the
writers, has LibreOffice export each file as HTML, and compares the displayed
text, once in English and once in German. Rules that look arbitrary but match
both applications:

- `#.##` shows a half as `.5`; `0.##` shows `0.5`.
- A negative that rounds to zero shows `0.00`, not `-0.00`.
- `?/8` with no whole-number part shows the whole value in eighths: 2.25 is
  `18/8`.
- With two sections the negative section renders the magnitude; the sign is
  whatever that section spells, which is the point of `0.00;(0.00)`.

Where the applications disagree the engine follows the majority, and the case
is listed at the top of `tools/formula-oracle.txt` with the reason. Three of
them:

- a serial below 61 falls on either side of Excel's 1900 leap-year bug;
- a fractional second is rounded here and by Gnumeric, truncated by
  LibreOffice;
- a negative serial is not a date, the two show different days for it, and
  this deck shows the number.

## Locales

A format code is the same in every locale: a German LibreOffice writes
`#,##0.00` and `dd/mm/yyyy` into an XLSX as an English one does, and stored
values always use a dot (`office:value="1234.5"`). Reading and writing do not
depend on locale.

What is shown does. The same file in a German-locale LibreOffice:

| code in the file | LibreOffice shows | `applyFormat` | `applyFormatIn`, German locale |
|---|---|---|---|
| `0.00` | `1234,50` | `1234.50` | `1234,50` |
| `#,##0.00` | `1.234,50` | `1,234.50` | `1.234,50` |
| `0.0%` | `123450,0%` | `123450.0%` | `123450,0%` |
| `$#,##0.00` | `$1.234,50` | `$1,234.50` | `$1.234,50` |
| `d mmm yyyy` | `18 Mai 1903` | `18 May 1903` | `18 Mai 1903` |
| `dddd` | `Montag` | `Monday` | `Montag` |

The decimal separator, the grouping separator and the month and weekday names
vary. `applyFormat` uses English; pass a `Locale` for anything else:

```jennifer
def german as sheet.Locale init sheet.withDayNames(
    sheet.withMonthNames(
        sheet.withSeparators(sheet.defaultLocale(), ",", "."),
        ["Januar", "Februar", ...],       # twelve
        ["Jan", "Feb", ...]),             # twelve, or [] to cut the full ones
    ["Sonntag", "Montag", ...],           # seven, Sunday first
    []);

sheet.applyFormatIn($v, "#,##0.00", $german);   # "1.234,50"
sheet.displayAtIn($s, "B2", $german);
sheet.displayRowsIn($s, $german);
```

Most regions need only the separators:

```jennifer
def swiss as sheet.Locale init sheet.withSeparators(
    sheet.defaultLocale(), ".", "'");           # 1'234'567.50
```

The deck ships English names only and has no locale database; the caller
supplies other names. `time.format` gives English names whatever the process
locale.

A date separator inside an ODS needs no locale. ODF stores it in the
components as a literal, so a German LibreOffice's

```
<number:day number:style="long"/><number:text>.</number:text>...
```

reads back as `dd.mm.yyyy` and renders as that application shows it. An XLSX
of the same sheet stores `dd/mm/yyyy` and the application substitutes its
locale's separator on display; this deck shows the slash.

## Cost

Linear in the cells, and about 15x the cost of reading the values, because the
code is scanned again for every cell:

| cells with a format | `rows()` | `displayRows()` |
|---|---|---|
| 3 000 | 33 ms | 506 ms |
| 12 000 | 137 ms | 1 999 ms |
| 48 000 | 536 ms | 7 911 ms |

A cell with no format costs nothing extra. Parsing each distinct code once per
sheet would remove most of the cost; it has not been needed.

## ODS

XLSX and Gnumeric store the code. ODF stores a tree of elements, so the code
is translated on write and rebuilt on read (`src/topics/odsfmt.j`):

```
#,##0.00   ->   <number:number-style style:name="N1">
                  <number:number number:decimal-places="2"
                                 number:min-integer-digits="1"
                                 number:grouping="true"/>
                </number:number-style>
```

Three details of that translation come from files LibreOffice wrote rather
than from the ODF specification:

- A code with several sections becomes several styles. The main style carries
  the **last** section, with a `<style:map>` per earlier section pointing at a
  sub-style marked `style:volatile="true"`.
- A four-section code's main style is a `number:text-style`, because the
  fourth section is the text one.
- `# ?/?` and `?/?` differ in whether `number:min-integer-digits` is
  **present**, not in its value: absent means the value is all fraction, `0`
  means the whole part is optional.

What ODF cannot express, and so does not survive a round trip through ODS:

| code | what comes back |
|---|---|
| `mmmmm` (the month's initial) | `mmm`, the abbreviation |
| `_x` and `*x` padding | dropped |
| a colour on a single-section code | dropped from the code, written as `fo:color` |
