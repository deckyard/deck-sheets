#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Evaluate tools/formula-oracle.txt here and hand the same formulas out.
 *
 * The deck's own tests cannot tell us whether this engine computes what a
 * spreadsheet computes - they share every assumption the engine made. So the
 * formulas also go into a file that LibreOffice and Gnumeric evaluate, and
 * tools/formula-oracle.sh diffs the three answers.
 *
 * Writes into the directory given as the first argument:
 *   ours.tsv    formula and this engine's answer, tab separated
 *   probe.ods   the same formulas for the applications to compute
 *
 * The fixture is small and fixed; it is documented at the top of
 * tools/formula-oracle.txt, which is the file to edit when adding a case.
 *
 * Usage: jennifer run tools/formula-oracle.j <directory>
 */

use io;
use os;
use fs;
use path;
use strings;

import "../src/sheets.j" as sheet;

if (len(os.ARGS) < 2) {
    io.printf("usage: jennifer run tools/formula-oracle.j <directory>\n");
    exit 2;
}
def dir as string init os.ARGS[1];
if (not fs.isDir($dir)) {
    fs.mkdirAll($dir);
}

/**
 * The inputs every formula in the list sees.
 *
 * Chosen to cover the cases that separate implementations: a whole number, a
 * float that rounds awkwardly, text, a blank, both booleans, a negative, a
 * near-duplicate string for EXACT, and a plain ascending row for the lookups.
 *
 * @return {list of list of sheet.Value} the fixture rows
 */
func fixtureRows() {
    return [
        [sheet.integer(4), sheet.integer(2), sheet.number(9.99), sheet.text("beta"), sheet.empty()],
        [
            sheet.boolean(true),
            sheet.boolean(false),
            sheet.integer(-7),
            sheet.text("Beta"),
            sheet.integer(1)
        ],
        [sheet.integer(1), sheet.integer(2), sheet.integer(3), sheet.integer(4), sheet.integer(5)]
    ];
}

/**
 * Read the formula list, dropping comments and blank lines.
 *
 * @param at {string} the path to formula-oracle.txt
 * @return {list of string} the formulas in file order
 */
func formulaList(at as string) {
    def out as list of string init [];
    for (def line in strings.split(fs.readString($at), "\n")) {
        def trimmed as string init strings.trim($line);
        if ($trimmed != "" and not strings.startsWith($trimmed, "#")) {
            $out[] = $trimmed;
        }
    }
    return $out;
}

/**
 * Build the row a probe formula sits in.
 *
 * The formula goes in column G so the fixture columns stay readable in the
 * CSV an application exports, and so the comparison can take one fixed
 * column rather than hunting for it.
 *
 * @param f {string} the formula
 * @return {list of sheet.Value} the row
 */
func probeRow(f as string) {
    def row as list of sheet.Value init [];
    for (def k in 0..6) {
        $row[] = sheet.empty();
    }
    $row[] = sheet.formula($f, "");
    return $row;
}

def listPath as string init path.join(path.dir(os.ARGS[0]), "formula-oracle.txt");
def formulas as list of string init formulaList($listPath);
def fixture as list of list of sheet.Value init fixtureRows();
def book as sheet.Workbook init sheet.addSheet(sheet.newWorkbook(), sheet.sheetOf("S", $fixture));

def lines as list of string init [];
def probeRows as list of list of sheet.Value init $fixture;
for (def i in 0..len($formulas)) {
    def f as string init $formulas[$i];
    def answer as string init "";
    try {
        $answer = sheet.asString(sheet.evaluate($book, "S", $f));
    } catch (e) {
        $answer = "!" + $e.message;
    }
    $lines[] = $f + "\t" + $answer;
    $probeRows[] = probeRow($f);
}

fs.writeString(path.join($dir, "ours.tsv"), strings.join($lines, "\n") + "\n");
sheet.save(
    sheet.addSheet(sheet.newWorkbook(), sheet.sheetOf("S", $probeRows)),
    path.join($dir, "probe.ods"));
io.printf("%d formulas evaluated into %s\n", len($formulas), $dir);
