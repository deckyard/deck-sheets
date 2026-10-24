<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Reading untrusted files

Each case below was tested with a file built to trigger it, and the tests are
in the overlays.

## Handled

**External entities are not resolved.** A document with
`<!ENTITY x SYSTEM "file:///etc/passwd">` and `&x;` in a cell reads back the
literal text `&x;`, and no file is opened. The deck decodes only the five
predefined entities and numeric character references itself (`core.j`) and
never uses a DTD-aware parser, so there is nothing that could resolve a SYSTEM
entity.

**Entity expansion cannot amplify.** A billion-laughs document reads back
`&e19;` as text, for the same reason.

**ZIP path traversal is refused.** `archive.unpack` rejects a member named
`../../../../tmp/evil.txt` before this deck sees it, and nothing is written
outside the working directory.

**A ZIP that declares too much is refused before inflating.** `archive.unpack`
inflates every member before returning, so the deck first sums the sizes the
central directory declares. A 1 MB file declaring 1 GiB is refused in 7 ms at
35 MB of memory. Limits: `MAX_INFLATED` (256 MiB) in total and `MAX_ENTRIES`
(4096) members.

**Run-length amplification is capped.** An ODS run carrying a value is
expanded up to `MAX_REPEAT` (4096) per axis. The two axes multiply: one cell
element with `table:number-rows-repeated="1048576"` and
`table:number-columns-repeated="16384"` asks for 16.7 million cells, and a
474-byte file built that way reached 7.1 GB before the kernel killed it. Each
element is clamped to `MAX_BLOCK_CELLS` (65536) cells, and a whole sheet past
`MAX_SHEET_CELLS` (1 000 000) is refused with an error pointing at the
streaming reader.

**Off-grid addresses are dropped.** A worksheet claiming `r="999999999999"`
used to set the sheet's extent to that, and any caller walking the sheet then
looped about a trillion times: a denial of service from a 657-byte file. A
cell outside `MAX_ROW` by `MAX_COLUMN` is discarded as damage and the rest of
the sheet reads.

**Nesting is bounded** by `MAX_NESTING` (100). Error messages quote input
through `quoted`, which truncates past 48 characters, so a megabyte-long
attribute does not become a megabyte-long message.

**Malformed markup is damage, not a refusal.** A truncated document returns
the rows before the truncation, an unknown entity is left as text, and a
number that will not parse falls back to the cell's text. The deck raises an
error only when continuing would mean inventing data.

Every refusal has `kind: "sheets"`. Tests cover this, including two cases that
used to escape as `kind: "runtime"`: a 20-letter column name and a 40-digit
row number overflowed `int64` during parsing, and both are now length-checked
first.

## Not handled

**Decompression is bounded by the declared sizes, not by measurement.** A file
that lies in its central directory is still inflated. 60 MB of declared
content measured 428 MB resident, since decoded text costs several times its
encoded size. The check stops the obvious bomb, not a determined one.

**There is no overall time or memory budget.** A large legitimate file and a
large hostile one look the same.

For untrusted input, **limit the input size before calling the deck, and read
it in a process you can afford to lose.** Only the operating system can
enforce a memory limit.

## Evaluating formulas from an untrusted file

Reading never evaluates a formula; `evaluate` and `recalculate` do. The
amplifications a hostile file can hold, each built and measured:

| Shape | Cost | Bound |
|---|---|---|
| `REPT("x",99999999)` | a huge string from a tiny formula | `MAX_TEXT_RESULT` (32 767 characters) |
| `REPT(...)&REPT(...)&...` | 2 000 terms in one cell reach about 65 MB | `MAX_FORMULA_TOKENS` (512), then `MAX_TEXT_GROWTH` (2 097 152 characters) |
| a column where each cell doubles the text above | 2^n characters | `MAX_TEXT_GROWTH` |
| a column where each cell adds the one above to itself | 2^n evaluations | each cell is resolved once |
| `SUM(A1:XFD1048576)` | 17 billion cells | `MAX_RANGE_CELLS`, which gives `#NUM!` |
| 2 000 brackets, or `----...-1` | crashed the interpreter with no catchable error | `MAX_FORMULA_DEPTH`, checked before the walk |

The total is not bounded: a hundred thousand legitimate formulas cost what
they cost. See [Evaluating formulas](evaluation.md#cycles-chains-and-limits).

## Gnumeric style regions

A Gnumeric style region states its own bounds; `ssconvert` writes one over
all 16 384 columns and 1 048 576 rows to fill a sheet's unused area. A region
is clipped to the cells the sheet has, and one whose style sets nothing is
never walked. A file declaring five hundred whole-grid regions reads in
300 ms.

## A format code is untrusted input too

Two scans over a format code are quadratic in its length: a code of 10 000
unclosed brackets measured 49 s, and one of 100 000 commas did not finish.
`MAX_FORMAT_CODE` (255, Excel's own limit and eight times the longest built-in
code) bounds it; a longer code renders the value plainly.

Reading a file never applies a format. This matters only once you call
`displayAt`, `displayRows`, `toHtml` or `toPdf` on content you did not write.

## Writing files for others

A CSV field that a spreadsheet reads as a formula runs when the file is
opened. Write text from elsewhere with `writeCsvSafe`:

```jennifer
fs.writeString("export.csv", sheet.writeCsvSafe($wb, ""));
```

See [Delimited text](csv.md). The XML formats type every cell, so text written
through this deck stays text and only a `Formula` value becomes a formula.
