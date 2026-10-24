# @deckyard/sheets

[![test](https://github.com/deckyard/deck-sheets/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-sheets/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-sheets/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-sheets)](https://github.com/deckyard/deck-sheets/releases/latest)

Read, edit and write OpenDocument (`.ods`), Office Open XML (`.xlsx`),
Gnumeric and delimited text from [Jennifer](https://jennifer-lang.dev/), over
one `Workbook` model of typed cells. It translates formulas between the ODS and
XLSX dialects, evaluates about 110 spreadsheet functions, applies number
formats and styles, streams sheets too large to hold in memory, and exports to
HTML, JSON and PDF.

**[Documentation](https://deckyard.github.io/deck-sheets/)**

## Install

```sh
jvc add @deckyard/sheets
```

jvc vendors the deck's `src/` into `vendor/deckyard/sheets/`. Without jvc,
unpack `src/` from a release archive (`deckyard-sheets-<version>.tar.gz`) into
that directory.

Requires Jennifer 0.25.0 or newer. No capabilities: no network, subprocesses
or database. `open` and `save` use `fs`; every codec also has a `bytes` entry
point.

## Example

```jennifer
import "@deckyard/sheets/" as sheet;

def wb as sheet.Workbook init sheet.open("sales.xlsx");
def s as sheet.Sheet init sheet.sheetByName($wb, "Q3");

for (def line in sheet.rows($s)) {
    io.printf("%s: %f\n", sheet.asString($line[0]), sheet.asNumber($line[1]));
}

$s = sheet.addRow($s, [sheet.text("East"), sheet.number(1510.25)]);
$wb = sheet.putSheet($wb, $s);
sheet.save($wb, "sales.ods");     # the extension picks the format
```

## Development

```sh
tools/check-all.sh                   # the whole gate, as CI runs it
jennifer test src/sheets_test.j      # the test suite
tools/check-extra.sh                 # LibreOffice / Gnumeric validation and oracles
tools/pack.sh dist                   # the release archive
```

CI also opens every written file in LibreOffice and compares the values back
(`.github/workflows/validate.yml`): the only check that catches a file this
deck reads but a real application rejects.

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.
