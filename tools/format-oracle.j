#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Write a sheet of number formats, and what this deck thinks each one shows.
 *
 * The formula oracle checks the format engine through `TEXT`, one code at a
 * time. This checks the other way in: a cell carrying a format in its own
 * style, written to a file, and compared against what the application
 * displays for it. That covers `displayAt`, the writers' format round trip,
 * and the engine, in the arrangement a user actually has.
 *
 * Writes into the directory given as the first argument:
 *   ours.tsv      the format code, then this deck's rendering of each value
 *   ours-de.tsv   the same, spelled the German way
 *   probe-xlsx.xlsx        the same grid for an application to display
 *   probe-gnumeric.gnumeric  and again, since Gnumeric stores a code too
 *   probe-ods.ods          and again, through ODF's component tree
 *
 * Usage: jennifer run tools/format-oracle.j <directory>
 */

use io;
use os;
use fs;
use path;
use strings;
use convert;

import "../src/sheets.j" as sheet;

if (len(os.ARGS) < 2) {
    io.printf("usage: jennifer run tools/format-oracle.j <directory>\n");
    exit 2;
}
def dir as string init os.ARGS[1];
if (not fs.isDir($dir)) {
    fs.mkdirAll($dir);
}

/**
 * The format codes to check.
 *
 * Only codes whose rendering both applications agree on. A code that one of
 * them reads differently belongs in the exclusion list at the top of
 * tools/formula-oracle.txt, not here.
 *
 * @return {list of string} the codes
 */
func formatCodes() {
    return [
        "0",
        "0.00",
        "#,##0",
        "#,##0.00",
        "#,##0.000",
        "0.0%",
        "0%",
        "0.00E+00",
        "$#,##0.00",
        "#,##0;(#,##0)",
        "0.00;[Red]-0.00",
        "000",
        "00000",
        "# ?/?",
        "@",
        "0.0,,"
    ];
}

/**
 * The values each code is applied to.
 *
 * Deliberately awkward: one that rounds, a negative, a small fraction, a
 * zero, and one with an exact quarter for the fraction formats.
 *
 * @return {list of sheet.Value} the values
 */
func formatValues() {
    return [
        sheet.number(1234.567),
        sheet.number(-12.5),
        sheet.number(0.075),
        sheet.number(0.0),
        sheet.number(2.25)
    ];
}

/**
 * A German locale, spelled as a German-locale LibreOffice spells it.
 *
 * The month and weekday names are a caller's job - the deck ships the
 * English ones and nothing else - so this is what a caller would write.
 *
 * @return {sheet.Locale} the locale
 */
func germanLocale() {
    return sheet.withDayNames(
        sheet.withMonthNames(
            sheet.withSeparators(sheet.defaultLocale(), ",", "."),
            [
                "Januar",
                "Februar",
                "Marz",
                "April",
                "Mai",
                "Juni",
                "Juli",
                "August",
                "September",
                "Oktober",
                "November",
                "Dezember"
            ],
            ["Jan", "Feb", "Mar", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]),
        ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"],
        []);
}

def codes as list of string init formatCodes();
def values as list of sheet.Value init formatValues();

def lines as list of list of sheet.Value init [];
for (def i in 0..len($codes)) {
    def row as list of sheet.Value init [sheet.text($codes[$i])];
    for (def v in $values) {
        $row[] = $v;
    }
    $lines[] = $row;
}

def grid as sheet.Sheet init sheet.sheetOf("Formats", $lines);
for (def i in 0..len($codes)) {
    def line as string init convert.toString($i + 1);
    $grid = sheet.setAreaStyle(
        $grid,
        "B" + $line + ":F" + $line,
        sheet.withFormat(sheet.style(), $codes[$i]));
}

def rendered as list of string init [];
for (def line in sheet.displayRows($grid)) {
    $rendered[] = strings.join($line, "\t");
}
fs.writeString(path.join($dir, "ours.tsv"), strings.join($rendered, "\n") + "\n");

# And the same grid spelled the German way. A format code is the same
# everywhere but what an application shows for one is not, so this is the only
# way to know the locale mechanism agrees with a real application rather than
# only with itself.
def germanRows as list of string init [];
for (def line in sheet.displayRowsIn($grid, germanLocale())) {
    $germanRows[] = strings.join($line, "\t");
}
fs.writeString(path.join($dir, "ours-de.tsv"), strings.join($germanRows, "\n") + "\n");

# XLSX rather than ODS: it stores a format as the code itself, where ODF wants
# a tree of components this deck does not build. See odsNumberStyle.
# All three. XLSX and Gnumeric store a format as the code itself; ODS stores
# ODF's tree of components, which odsfmt.j builds from the code - so a
# disagreement there is a fault in that translation and is exactly what this
# should catch.
def book as sheet.Workbook init sheet.addSheet(sheet.newWorkbook(), $grid);
sheet.save($book, path.join($dir, "probe-xlsx.xlsx"));
sheet.save($book, path.join($dir, "probe-gnumeric.gnumeric"));
sheet.save($book, path.join($dir, "probe-ods.ods"));
io.printf("%d codes x %d values into %s\n", len($codes), len($values), $dir);
