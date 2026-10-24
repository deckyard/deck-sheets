<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Formulas

A formula cell holds the expression and the result the producing application
last computed. The deck reads both, translates the expression between the two
file dialects, and writes both back. Computing the expression is covered in
[Evaluating formulas](evaluation.md).

```jennifer
def v as sheet.Value init sheet.cell($s, "C3");
match ($v) {
    when Formula(f) {
        io.printf("=%s, last computed as %s\n", $f.source, $f.cached);
    }
    else { }
}
```

`asString` of a formula cell is its cached result.

## Stale results

Changing a cell a formula depends on leaves the formula's `cached` result
unchanged:

```jennifer
$s = sheet.setCell($s, "B3", sheet.integer(99));   # C3 is =B3*C2
# C3's cached result is now stale.
```

Either recompute it, or clear the cache and let the application recalculate
on open:

```jennifer
$s = sheet.recalculate($wb, "Sheet1").sheet;
$s = sheet.setCell($s, "C3", sheet.formula("B3*C2", ""));
```

Clear the cache when the expression uses something the engine does not
implement: an empty result is honest, a stale one is not.

## The two dialects

The model stores formulas in **A1** (`B3*C2`, `SUM(A1:A5)`), which is what a
user types and what XLSX and Gnumeric store. ODS stores **OpenFormula**:
bracketed, dot-qualified references and `;` between arguments.

| A1 | OpenFormula |
|---|---|
| `B3*C2` | `[.B3]*[.C2]` |
| `SUM(A1:A5)` | `SUM([.A1:.A5])` |
| `SUM(A1,A2)` | `SUM([.A1];[.A2])` |
| `$B$3` | `[.$B$3]` |
| `Sheet2!B3` | `[Sheet2.B3]` |
| `'Second Sheet'!B3` | `['Second Sheet'.B3]` |

The ODS codec calls `toA1Formula` and `toOpenFormula`, so a formula keeps its
meaning across formats. Without them an ODS-to-XLSX conversion would hand
Excel `[.B3]*[.C2]`.

The translator tokenises rather than searching and replacing:

```jennifer
sheet.toOpenFormula("CONCATENATE(A1,\"a,b\")");   # the comma in the string
                                                  # is not a separator
sheet.toOpenFormula("LOG10(A1)");                 # LOG10 is a function, not
                                                  # a reference to row 10
sheet.toOpenFormula("SUM(Revenue)");              # a named range, left alone
```

It tolerates damage: an unterminated string or an unclosed bracket keeps what
could be read, because its job is to round-trip whatever a file holds.
`evaluate` refuses the same input, so the two have separate lexers.

## Not handled

Array formulas and XLSX shared-formula groups (one expression stored for a
range, referenced by its siblings) read as their text. They round-trip but are
not understood. The `_xlfn.` prefix Excel puts on newer functions is kept in
the stored expression and stripped before evaluation, so `_xlfn.XOR(...)`
evaluates.
