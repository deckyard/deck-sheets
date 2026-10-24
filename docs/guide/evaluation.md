<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Evaluating formulas

`evaluate` computes one expression and returns a `Value`. `recalculate`
recomputes every formula cell on a sheet and writes the results into their
caches.

```jennifer
def answer as sheet.Value init sheet.evaluate($wb, "Sheet1", "SUM(A1:A10)*1.2");
io.printf("%s\n", sheet.asString($answer));

def done as sheet.Recalculated init sheet.recalculate($wb, "Sheet1");
io.printf("%d formulas, %d of them errors\n", $done.evaluated, $done.failed);
$wb = sheet.putSheet($wb, $done.sheet);
```

The sheet name says what an unqualified reference such as `A1` means; a
qualified one (`'Other Sheet'!A1`) reads that sheet. A leading `=` is
accepted. Cached results in referenced cells are not trusted: a cell holding
`=A1*2` is followed to `A1`.

`recalculate` writes back only the named sheet; formulas on other sheets are
read through. A formula that does not parse caches `#NAME?` and counts as
failed instead of refusing the sheet.

## Errors are values

A formula that cannot be computed yields an error value, as in a spreadsheet:

```jennifer
sheet.evaluate($wb, "S", "1/0");                        # Value.Err{code: "#DIV/0!"}
sheet.evaluate($wb, "S", "NOSUCH(1)");                  # Value.Err{code: "#NAME?"}
sheet.asString(sheet.evaluate($wb, "S", "1/0"));        # "#DIV/0!"
sheet.isErrorValue(sheet.evaluate($wb, "S", "1/0"));    # true
```

An error operand makes the whole expression that error (`1/0+1` is
`#DIV/0!`); `IFERROR` and `IFNA` catch one.

`evaluate` throws, with `kind: "sheets"`, only when the caller is at fault: a
sheet the workbook lacks, an expression that does not parse, or one past
`MAX_FORMULA_DEPTH` or `MAX_FORMULA_TOKENS`.

## Spreadsheet semantics

Each of these was checked against LibreOffice and Gnumeric, and
`tools/formula-oracle.sh` re-checks them.

| Expression | Answer | Why |
|---|---|---|
| `2^3^2` | 64 | `^` is **left**-associative |
| `-2^2` | 4 | unary minus binds tighter than `^` |
| `"beta"="BETA"` | TRUE | `=` on text ignores case; `EXACT` does not |
| `D1>A1` | TRUE | across types, number < text < boolean, so any text beats any number |
| `E1=0` and `E1=""` | both TRUE | a blank cell takes the type of what it is compared with |
| `MOD(-7,3)` | 2 | the sign follows the divisor |
| `COUNT(A1:E1)` | numbers only | a boolean in a cell is not counted; one written in the call is |
| `COUNTIF(r,">1")` | numbers only | an ordering criterion never matches text or blanks |
| `0^-1` | `#NUM!` | though `1/0` is `#DIV/0!` |
| `VLOOKUP(x,A3:E3,1,FALSE)` | often `#N/A` | it searches the first **column**, one cell of a single row |

## Cycles, chains and limits

A formula that depends on itself, directly or through other cells, yields
`#REF!`:

```jennifer
# A1 is =A1+1, A2 is =A3, A3 is =A2
sheet.asString(sheet.evaluate($wb, "C", "A1"));    # "#REF!"
```

Chain length is not limited by recursion. Dependencies are resolved first, by
an iterative walk, then the formula is evaluated, so a thousand-row running
total (`B3` is `B2+A3`, `B4` is `B3+A4`, ...) computes correctly. Each cell is
computed once, so a column where every cell refers to the one above twice is
linear, not 2^n.

| Limit | Value | Bounds | Past it |
|---|---|---|---|
| `MAX_FORMULA_DEPTH` | 64 | bracket nesting and runs of prefix operators such as `----1` (Excel's own nesting limit) | throws |
| `MAX_FORMULA_TOKENS` | 512 | tokens in one formula; parsing is quadratic in it | throws |
| `MAX_RESOLVED_CELLS` | 500 000 | cells one evaluation resolves | `#NUM!` |
| `MAX_RANGE_CELLS` | 1 000 000 | cells one range covers | `#NUM!` |

The first two are checked before the formula is walked: a long enough run of
prefix operators used to crash the interpreter with no catchable error. They
apply only to evaluation. Reading and writing a file never parses a formula,
so a formula of any size round-trips. The text limits are in
[Reading untrusted files](untrusted.md#evaluating-a-formula-from-an-untrusted-file).

## Functions

About 110, besides the arithmetic and comparison operators, `&` and `%`:

- **Aggregates**: `SUM`, `AVERAGE`, `MIN`, `MAX`, `PRODUCT`, `COUNT`,
  `COUNTA`, `COUNTBLANK`, `MEDIAN`, `SUMSQ`, `STDEV`, `STDEVP`, `VAR`, `VARP`
- **Rounding and number theory**: `ROUND`, `ROUNDUP`, `ROUNDDOWN`, `INT`,
  `TRUNC`, `CEILING`, `FLOOR`, `ABS`, `SIGN`, `SQRT`, `MOD`, `POWER`,
  `QUOTIENT`, `GCD`, `LCM`, `EVEN`, `ODD`, `FACT`
- **Transcendental**: `EXP`, `LN`, `LOG`, `LOG10`, `PI`, `SQRTPI`, `SIN`,
  `COS`, `TAN`, `ASIN`, `ACOS`, `ATAN`, `ATAN2`, `DEGREES`, `RADIANS`
- **Text**: `LEN`, `UPPER`, `LOWER`, `PROPER`, `TRIM`, `LEFT`, `RIGHT`, `MID`,
  `FIND`, `SEARCH`, `SUBSTITUTE`, `REPLACE`, `REPT`, `TEXT`, `VALUE`, `EXACT`,
  `CHAR`, `CODE`, `T`, `N`, `CONCATENATE`, `CONCAT`
- **Logic**: `IF`, `IFERROR`, `IFNA`, `AND`, `OR`, `NOT`, `XOR`, `TRUE`,
  `FALSE`, the `IS` family, `NA`
- **Criteria**: `SUMIF`, `COUNTIF`
- **Lookup**: `VLOOKUP`, `HLOOKUP`, `INDEX`, `MATCH` (match types 0, 1 and
  -1), `ROW`, `COLUMN`, `ROWS`, `COLUMNS`
- **Dates**: `TODAY`, `NOW`, `DATE` (`#NUM!` for a year outside 1900-9999),
  `YEAR`, `MONTH`, `DAY`, `HOUR`, `MINUTE`, `SECOND`, `WEEKDAY`, `DATEVALUE`,
  `DAYS`, `EDATE` (clamps to the end of a shorter month)

`TEXT` uses the same engine as [number formats](formats-applied.md).

`IF`, `IFERROR` and `IFNA` are lazy: the branch not taken is not evaluated, so
`IF(B1=0,0,A1/B1)` is safe.

An unknown function is `#NAME?`, as is a bare name that is not a call:
defined names are not resolved.

Array formulas are not computed. A range where one value is wanted
(`A1:A5*2`, `OR(A1:A5>4)`) is `#VALUE!`, as in both reference applications.
Taking the first cell instead would give answers that look right and are not.

## Cost

On one host:

| Work | Time |
|---|---|
| `SUM` over 5 000 cells | 160 ms |
| `SUM` over 50 000 cells | 1.5 s |
| recalculating 4 000 formula cells | 1.5 s |
| a 2 000-cell dependency chain | 1.6 s |
| parsing a 100-token formula | 28 ms |

Parsing is the only superlinear step, and `MAX_FORMULA_TOKENS` bounds it. See
[Memory](../internal/memory.md).
