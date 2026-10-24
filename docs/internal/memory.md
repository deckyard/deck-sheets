<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Memory

Why the readers scan instead of parsing, why the writers emit text, and the
measurements behind each decision. All figures are from one host.

## A tree costs 130 times its file

`xml.decode` builds a tree that is only useful whole. Decoding and walking
sheets of increasing size:

| Sheet | XML size | decode | walk | peak RSS |
|---|---|---|---|---|
| 1 000 cells | 26 KB | 4 ms | 2 ms | 31 MB |
| 10 000 cells | 275 KB | 27 ms | 19 ms | 127 MB |
| 100 000 cells | 2.8 MB | 372 ms | 257 ms | 1.16 GB |
| 500 000 cells | 15 MB | 2 590 ms | 1 237 ms | 5.11 GB |

About 12 KB per cell. Time is linear; memory is the limit, and an ordinary
100 000-cell export already needs a gigabyte.

## Scanning instead

`src/topics/scan.j` walks element boundaries over the raw `bytes`. The codecs
find each row with the scanner and hold no more than that row. Streaming the
500 000-cell sheet:

| | peak RSS |
|---|---|
| `xml.decode` of the whole sheet | 5.11 GB |
| `openRows` | 148 MB |

Three properties of the scanner are load-bearing:

1. **The hot primitives stay native.** `indexOfByte` wraps `binary.indexOf`;
   `matchesAt` is one `binary.slice` and a comparison, and takes `bytes` so a
   caller in a loop converts its probe once.
2. **Name matching respects boundaries.** `<row` occurs inside `<rowBreaks>`
   and `<c` inside `<cols>`, so `openTagAt` and `closeTagAt` check the byte
   after the probe. Without that every worksheet takes the nesting-aware slow
   path.
3. **Large child lists stream.** `nextChild` yields one child at a time.
   `childNodes` builds a list and is only for small, bounded cases; a
   `<sheetData>` has one child per row.

## Where a tree is still right

For an XLSX row, `decodeLeaf` passes the row to `xml.decode` once, which is
faster than scanning its cells:

| XLSX row values, 20-column sheet | per cell |
|---|---|
| interpreted scan, `nodeAttr` per attribute | 0.30 ms |
| one `xml.decode` per row, read from the tree | 0.08 ms |

ODS cannot do this, for correctness rather than speed: `xml.children` returns
only elements and `xml.text` concatenates all of an element's text, so
`<text:p>a<text:span>B</text:span>b` decoded to a tree reads as `abB`. Styled
cells are mixed content, so ODS is read by the byte walk.

## The `xml` builder is quadratic

Building output with `xml.element` / `setAttr` / `append` copies on write:

| rows (10 cells each) | `xml` builder | string assembly |
|---|---|---|
| 1 000 | 128 ms | 8 ms |
| 2 000 | 315 ms | 17 ms |
| 4 000 | 905 ms | 74 ms |
| 8 000 | **3 221 ms** | **89 ms** |

About 3.5x per doubling against linear. `src/topics/emit.j` appends pieces to
a `list of string` and joins once; `xml.encode` is kept for small bounded
parts.

## Accumulators passed through calls

Under value semantics a growing accumulator passed to a function is
deep-copied on every call.

**In the readers.** They used to pass the `Sheet` through a per-row call and
merge cells into it: 10 000 cells took **67 s**. Each row now returns its own
cells (`Placed`), and the sheet's map is filled once in a local loop:

| cells | before | after |
|---|---|---|
| 5 000 | 18.6 s | 1.4 s |
| 10 000 | 66.7 s | 2.9 s |
| 40 000 | did not finish | 12.3 s |

About 2x per doubling.

**At the API.** A consumer's call crosses the module boundary, so the cost is
higher:

| reading 5 000 cells | wall |
|---|---|
| `rows($s)` once | 70 ms |
| `cellAt($s, ...)` per cell | 10 882 ms |

155 times slower, which is why `rows`, `row` and `valuesIn` exist.

**In the XML emitter.** `emit.j` was written to avoid the builder's quadratic,
and its first design passed an `Emitter` struct in and out of every builder,
copying the accumulated list each time:

| | wall |
|---|---|
| 8 000 appends threaded through a struct | 14 792 ms |
| the same appends into a local list | 4 ms |

A 400-row ODS took **12 100 ms** to write. The builders are now pure string
functions and each writer keeps its list as a local:

| writer, 400 rows | before | after |
|---|---|---|
| ODS | 12 100 ms | 156 ms |
| XLSX | 831 ms | 127 ms |
| Gnumeric | 1 125 ms | 93 ms |

**In the formula tokeniser**, twice over. It passed its growing token list
through a helper, and it read characters with `strings.substring($s, $i,
$i + 1)`, which is rune-indexed and so walks i runes to reach the i-th:

| per-character scan, 64 000 characters | wall |
|---|---|
| `strings.substring($s, $i, $i + 1)` | 4 878 ms |
| indexing a `strings.chars($s)` list | 41 ms |

A 6 KB formula took 3 802 ms and a 96 KB one about 77 s. Both are linear now:
144 ms and 2.2 s.

## Building a sheet

`setRow` used to loop over `setCellAt`, copying the growing cell map per cell:

| building a sheet | row by row | `sheetOf` |
|---|---|---|
| 250 rows | 1 473 ms | 22 ms |
| 1 000 rows | 22 039 ms | 81 ms |
| 2 000 rows | 72 168 ms | 145 ms |

`setRow` now copies the map once per row, a 2.6x gain, but building a whole
sheet that way stays quadratic because every call returns a fresh `Sheet`.
`sheetOf` fills the map once and is linear, so it is the documented way to
build a sheet.

## Binding copies, indexing does not

The evaluator made every range quadratic. Reading one entry of a map held in
a struct in a list in a struct, 3 000 times, from a 3 000-entry map:

| shape | 3 000 reads |
|---|---|
| `$sc.book.sheets[$i].cells[$key]`: index the chain in place | **8 ms** |
| `cellOf(byName($sc.book, $name), $key)`: pass the sheet to a helper | 2 336 ms |
| `def s as Sheet init byName(...)`, then index `$s` | 4 643 ms |
| `def held as map init $s.cells`, then index `$held` | 2 476 ms |

Writing, 3 000 times:

| shape | 3 000 writes |
|---|---|
| `$work.sheets[0].cells[$key] = $v`: mutate a local in place | **12 ms** |
| `$acc = setOne($acc, $key, $v)`: a setter returning a fresh value | 3 758 ms |

**Binding or passing a compound value copies it; indexing through it does
not.** A struct parameter is free (passing `$sc` 3 000 times cost nothing),
but `def x init <compound>` and `Struct{field: <compound>}` deep-copy. In the
evaluator:

- `Scope{book: $wb, ...}` copied the workbook, once per nested reference;
- `for (def s in $wb.sheets)` copies every sheet it passes, so `hasSheet`
  alone took 2.4 s of a recalculation;
- `sheetByName` copies the sheet it returns, so reading one cell through it
  costs a map copy.

With the workbook out of `Scope`, the workbook loops in `model.j` indexing
instead of binding, and `recalculate` building its result map once:

| | before | after |
|---|---|---|
| `SUM` over 5 000 cells | 18 545 ms | 159 ms |
| `SUM` over 50 000 cells | - | 1 502 ms |
| recalculate 4 000 formulas | 79 199 ms | 1 506 ms |

Both linear.

## Iterative resolution

Following a reference by recursively evaluating its target caused two
defects.

A **fan-out** cost 2^n. In a column where each cell is `A{n-1}+A{n-1}`, every
level doubles the work:

| fan-out depth | re-evaluating | resolved once |
|---|---|---|
| 8 | 59 ms | 8 ms |
| 16 | 15 904 ms | 28 ms |
| 20 | did not finish | 25 ms |

A **chain** recursed as deep as it was long, and bounding the recursion at
`MAX_FORMULA_DEPTH` (64) to protect the interpreter made a 100-row running
total answer `#REF!`.

`resolveFrom` fixes both. It walks the dependency graph iteratively over an
explicit stack and writes each computed value into a working copy of the
workbook in place, which the table above shows is free. The formula is then
evaluated with every reference already a literal. Chain length is bounded by
`MAX_RESOLVED_CELLS`, not by the interpreter's stack.

The first version of the walk was itself quadratic. Popping with
`$stack = lists.slice($stack, 0, len($stack) - 1)` copies the list, and
removing a key by rebuilding the map copies the map, once per cell each.
Keeping a live length and setting `$onStack[$key] = false` instead:

| chain | first version | with a live length |
|---|---|---|
| 400 cells | 968 ms | 497 ms |
| 2 000 cells | 16 357 ms | 1 635 ms |

A list or a map is only cheap if you never replace it.

## Parsing stays quadratic in formula width

The one measured problem with no fix in this language. A left-associative
chain builds a left-leaning tree, and `Expr.Binary{parts: [$acc, $next]}`
deep-copies the subtree at every step. On a bare enum, no parser involved:

| nodes | time |
|---|---|
| 200 | 82 ms |
| 400 | 226 ms |
| 800 | 938 ms |
| 1 600 | 5 094 ms |

An arena (nodes in a flat list, children by index) would make it linear and
needs language support. Until then `MAX_FORMULA_TOKENS` (512) caps the width.
Reading and writing never parse a formula, so the cap does not affect them.

## Read cost per cell

An ODS read builds the model at about 0.78 ms per cell:

| rows (3 columns) | read |
|---|---|
| 500 | 866 ms |
| 1 000 | 1 793 ms |
| 2 000 | 4 046 ms |
| 4 000 | 9 426 ms |

Roughly linear with a slowly growing factor. The profile shows no copying to
remove: `binary.indexOf` runs about 39 times per cell, and the small `bytes`
probes in `matchingClose` and `nodeAttr` make most of the allocations. That is
about 1 300 cells a second, or a minute and a half for 100 000 cells. This
architecture buys memory, not throughput.

## Number format cost

Linear, and 15x the cost of reading values, because `formatSections`,
`visibleSection`, `scanNumShape` and `layOutNumber` each scan the code again
for every cell:

| cells with a format | `rows()` | `displayRows()` |
|---|---|---|
| 3 000 | 33 ms | 506 ms |
| 12 000 | 137 ms | 1 999 ms |
| 48 000 | 536 ms | 7 911 ms |

0.165 ms per formatted cell against 0.011 ms to read one. A cell with no
format goes straight to `asString`. If it is ever needed, `displayRows` could
parse each distinct code once and keep the parsed shapes in a local map.

## Bounded probes

`binary.indexOf` has no limit argument, so `indexOfByte` applied the limit to
its result, after a missing probe had already scanned the rest of the
document. Reading Gnumeric styles exposed it: 3 000 regions, each probing a
dozen attributes, turned a 110 KB document into hundreds of megabytes of
scanning.

A short range is now copied out and searched alone. Above `BOUNDED_SEARCH`
(4 096 bytes) the copy costs more than it saves, so whole-document searches
use the plain search.

| styled cells read | before | after |
|---|---|---|
| 1 500 | 1 071 ms | 1 123 ms |
| 6 000 | 4 864 ms | 4 410 ms |
| 24 000 | 27 290 ms | 17 615 ms |

The scaling matters more than the constant: 4.5x then 5.6x per doubling
before, 3.9x then 4.0x after. All readers share `indexOfByte`, so ODS improved
too: 12 000 cells went from 9 426 ms to 6 749 ms, and its per-doubling factor
(2.07x, 2.26x, 2.33x) flattened to 2.05x.

## Gnumeric styles

Measured while the writer still emitted one region per row (see the
verification pass below): one style over a three-column block, 24 000 styled
cells in 110 KB.

| styled cells | write |
|---|---|
| 1 500 | 207 ms |
| 6 000 | 784 ms |
| 24 000 | 3 113 ms |

Reading cost about 0.73 ms per styled cell, close to the 0.78 ms per cell of
an ODS read.

## Locale

Measured by running LibreOffice under `de_DE.UTF-8`.

Not locale-dependent:

- a format code: a German LibreOffice writes `#,##0.00` and `dd/mm/yyyy` into
  an XLSX as an English one does;
- a stored value: `office:value="1234.5"` and `<v>1234.5</v>` always use a
  dot;
- a date separator inside ODS, stored as a literal
  `<number:text>.</number:text>`, so the code reads back as `dd.mm.yyyy`.

Locale-dependent, and the reason `Locale` exists: the decimal separator, the
grouping separator, and month and weekday names. Of seven codes rendered, one
matched a German LibreOffice before and all seven do now.

Two traps:

- `time.format` ignores the process locale (`%B` is `May` under
  `LC_ALL=de_DE.UTF-8`), so the caller supplies the names.
- The plain fallback used wherever a format cannot be applied (`@` on a
  number, a value past `MAX_FORMATTED`, a date code on a non-date) went
  through `numberText`, which always writes a dot. Only the German pass of the
  format oracle caught it.

## ODS reader gaps found by a German file

Both pre-existing, both losing most of a real document's formats:

1. **Number styles are in `styles.xml` as well as `content.xml`.** The file
   had two in the content and forty-nine in `styles.xml` (48 in
   `<office:styles>`, one in `<office:automatic-styles>`). The reader looked
   only at the content and lost five of seven formats.
2. **A column can set its cells' style.**
   `<table:table-column table:default-cell-style-name="ce1"/>` is how an
   application stores a whole-column format, and the cells then name no style.

Seven of seven formats survive now, where two did.

## Found by a verification pass

With everything linear and green, a further pass found four problems.

**The Gnumeric writer emitted one region per row.** Merging along both axes
took 24 000 styled cells from 178 KB to 52 KB, the read from 28.7 s to 7.1 s
and the write from 4.6 s to 2.5 s. Gnumeric became the fastest of the three
readers: its file is a tenth the size and has no container.

**The formula parser kept its cursor in a struct with the token list.**
`Parse{tokens: $p.tokens, at: $at + 1}` copied the list to advance: a third
of the cost of a long parse. With both as parameters, 200 terms went from
102 ms to 65 ms.

**A helper extracted to satisfy lint was quadratic.**
`withColumnDefault($out, ...)` took the accumulator and returned it, the only
way to move an appending loop body into a function. 20 000 column elements
took 44.9 s, against 4.5 s with the loop in the caller and only a pure helper
extracted.

**`General` was stored as a format code.** It means no format, and the writers
disagreed: XLSX wrote it back, Gnumeric dropped it, and ODF, with no component
for it, wrote it as a literal, so the cell showed the word "General". It is
now normalised to `""` in `withFormat` and in each reader. Round-tripping 48
format codes through all three formats, 46 came back identical; the other two
were this bug and the documented ODF colour asymmetry.

## Remaining hot spot

In a run that reads and writes all three formats, about 10% of the time is the
bounded search in `indexOfByte` (`binary.slice` plus `indexOf`): one
allocation per attribute probe, which is what buys the bound. Slicing an
element's open tag once and probing every attribute against that slice would
save about 9%, since `nodeAttr` runs a dozen times per element. It needs a new
`nodeAttr` shape that every reader sees, and has not been worth it.

## Tools

`jennifer profile --allocs` finds the line that copies; `jennifer profile`
finds the line that spends time. Use both: the allocation profile called the
copies linear while the statement profile pointed at the API trap, and the
statement profile blamed the scanner while the allocation profile found the
emitter. There is no `jennifer perf`.
