# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - A1 addressing: column letters, cell references, ranges.
# Spliced into sheets.j via include - not a standalone module.

/** The letters a column name is built from. */
def const COLUMN_LETTERS as string init "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

/**
 * The largest column index either format addresses.
 *
 * XLSX stops at column XFD (16384 columns, 0-based 16383); ODS has no fixed
 * limit but no application goes past it either. Past this a reference is
 * refused rather than silently wrapping.
 */
export def const MAX_COLUMN as int init 16383;

/** The largest row index either format addresses (1048576 rows, 0-based). */
export def const MAX_ROW as int init 1048575;

/**
 * How many letters a column name may have.
 *
 * `XFD` is the last column, so three. The limit is enforced before the
 * base-26 accumulation rather than after, because 20 letters overflow
 * `int64` and an overflow is a `kind: "runtime"` error that would escape this
 * deck's contract.
 */
def const MAX_COLUMN_LETTERS as int init 3;

/**
 * How many digits a row number may have.
 *
 * `MAX_ROW + 1` is 1048576, so seven. Enforced before `convert.toInt` for the
 * same reason as `MAX_COLUMN_LETTERS`.
 */
def const MAX_ROW_DIGITS as int init 7;

/**
 * Where one cell sits, zero-based.
 *
 * The A1 spelling a user sees is one-based on the row; `cellRef` and
 * `parseRef` are the only places that convert.
 *
 * @field row {int} the row index, 0 for row 1
 * @field col {int} the column index, 0 for column A
 */
export def struct Ref {
    row as int,
    col as int
};

/**
 * A rectangular block of cells, inclusive on both corners.
 *
 * @field from {Ref} the top-left corner
 * @field to2 {Ref} the bottom-right corner, inclusive
 */
export def struct Area {
    from as Ref,
    to2 as Ref
};

/**
 * Build a cell reference.
 *
 * @param row {int} the zero-based row index
 * @param col {int} the zero-based column index
 * @return {Ref} the reference
 * @throws {Error} kind "sheets" when either index is negative or past its maximum
 * @example
 *   ref(0, 0);   # A1
 */
export func ref(row as int, col as int) {
    checkRowCol($row, $col);
    return Ref{row: $row, col: $col};
}

/**
 * Refuse a row or column index outside the addressable grid.
 *
 * @param row {int} the zero-based row index
 * @param col {int} the zero-based column index
 * @throws {Error} kind "sheets" when either index is negative or past its maximum
 */
func checkRowCol(row as int, col as int) {
    if ($row < 0 or $col < 0) {
        fail("cell indices are zero-based and cannot be negative (got row " +
            convert.toString($row) + ", column " + convert.toString($col) + ")");
    }
    if ($row > MAX_ROW) {
        fail("row " + convert.toString($row) + " is past the last addressable row");
    }
    if ($col > MAX_COLUMN) {
        fail("column " + convert.toString($col) + " is past the last addressable column");
    }
}

/**
 * The column name for a zero-based column index.
 *
 * Column names are bijective base 26: there is no zero digit, so after Z
 * comes AA rather than BA.
 *
 * @param col {int} the zero-based column index
 * @return {string} the column name in upper case
 * @throws {Error} kind "sheets" when `col` is negative or past `MAX_COLUMN`
 * @example
 *   columnName(0);    # "A"
 *   columnName(25);   # "Z"
 *   columnName(26);   # "AA"
 */
export func columnName(col as int) {
    checkRowCol(0, $col);
    def name as string init "";
    def n as int init $col;
    while (true) {
        def digit as int init $n % 26;
        $name = strings.substring(COLUMN_LETTERS, $digit, $digit + 1) + $name;
        $n = $n // 26 - 1;
        if ($n < 0) {
            break;
        }
    }
    return $name;
}

/**
 * The zero-based column index for a column name.
 *
 * Case-insensitive, so `a` and `A` are the same column.
 *
 * @param name {string} a column name such as `"A"` or `"XFD"`
 * @return {int} the zero-based column index
 * @throws {Error} kind "sheets" when the name is empty, holds a non-letter, or is past the
 *   last addressable column
 * @example
 *   columnIndex("A");    # 0
 *   columnIndex("AA");   # 26
 */
export func columnIndex(name as string) {
    if ($name == "") {
        fail("a column name cannot be empty");
    }
    # Bounded before the arithmetic, not after. No column name is longer than
    # three letters (`XFD` is the last), and accumulating 20 of them overflows
    # `int64` - which Jennifer raises as `kind: "runtime"`, escaping this
    # deck's error contract. A caller matching on `kind == "sheets"` would
    # then mis-handle a merely malformed reference.
    if (len($name) > MAX_COLUMN_LETTERS) {
        fail("column name " + quoted($name) + " is longer than the " +
            convert.toString(MAX_COLUMN_LETTERS) +
            " letters a column name may have");
    }
    def value as int init 0;
    for (def ch in strings.chars(strings.upper($name))) {
        def digit as int init strings.indexOf(COLUMN_LETTERS, $ch);
        if ($digit < 0) {
            fail("column name " + quoted($name) + " is not all letters");
        }
        $value = $value * 26 + $digit + 1;
    }
    def col as int init $value - 1;
    if ($col > MAX_COLUMN) {
        fail("column name " + quoted($name) + " is past the last addressable column");
    }
    return $col;
}

/**
 * The A1 spelling of a cell reference.
 *
 * @param at {Ref} the reference
 * @return {string} the A1 spelling, with a one-based row
 * @example
 *   cellRef(ref(0, 0));   # "A1"
 *   cellRef(ref(6, 1));   # "B7"
 */
export func cellRef(at as Ref) {
    return columnName($at.col) + convert.toString($at.row + 1);
}

/**
 * Read an A1 cell reference.
 *
 * Accepts the absolute spellings (`$B$7`, `B$7`, `$B7`) and discards the
 * dollars: this deck models where a cell is, not how a formula addressed it.
 * The dialect translator in `fdialect.j` is where absoluteness is preserved,
 * because that is the only place it changes the meaning of anything.
 *
 * @param text {string} an A1 reference such as `"B7"` or `"$B$7"`
 * @return {Ref} the zero-based reference
 * @throws {Error} kind "sheets" when the text is not a cell reference
 * @example
 *   parseRef("B7");     # row 6, column 1
 *   parseRef("$B$7");   # the same
 */
export func parseRef(text as string) {
    def bare as string init strings.replace($text, "$", "");
    if ($bare == "") {
        fail("cell reference " + quoted($text) + " is empty");
    }
    def letters as string init "";
    def digits as string init "";
    def inDigits as bool init false;
    for (def ch in strings.chars($bare)) {
        if (strings.indexOf(COLUMN_LETTERS, strings.upper($ch)) >= 0 and not $inDigits) {
            $letters = $letters + $ch;
        } elseif (strings.indexOf("0123456789", $ch) >= 0) {
            $inDigits = true;
            $digits = $digits + $ch;
        } else {
            fail("cell reference " + quoted($text) + " is malformed");
        }
    }
    if ($letters == "" or $digits == "") {
        fail("cell reference " + quoted($text) + " needs a column and a row");
    }
    # Same reason as in `columnIndex`: `MAX_ROW + 1` is seven digits, and
    # handing `convert.toInt` forty of them raises `kind: "runtime"` rather
    # than this deck's error.
    if (len($digits) > MAX_ROW_DIGITS) {
        fail("cell reference " + quoted($text) + " has a row number longer " +
            "than the " + convert.toString(MAX_ROW_DIGITS) + " digits a row " +
            "may have");
    }
    def row as int init convert.toInt($digits) - 1;
    if ($row < 0) {
        fail("cell reference " + quoted($text) + " has row 0; rows are one-based");
    }
    return ref($row, columnIndex($letters));
}

/**
 * Build an area from two corners, in either order.
 *
 * The corners are normalised, so `B7:A1` and `A1:B7` give the same area.
 *
 * @param a {Ref} one corner
 * @param b {Ref} the opposite corner
 * @return {Area} the normalised area
 * @example
 *   area(ref(0, 0), ref(6, 2));   # A1:C7
 */
export func area(a as Ref, b as Ref) {
    return Area{
        from: Ref{row: math.min($a.row, $b.row), col: math.min($a.col, $b.col)},
        to2: Ref{row: math.max($a.row, $b.row), col: math.max($a.col, $b.col)}
    };
}

/**
 * The A1 spelling of an area.
 *
 * A one-cell area is written as the single reference, which is how both
 * formats write it.
 *
 * @param box {Area} the area
 * @return {string} the A1 spelling, such as `"A1:C7"`
 * @example
 *   areaRef(area(ref(0, 0), ref(6, 2)));   # "A1:C7"
 */
export func areaRef(box as Area) {
    def start as string init cellRef($box.from);
    if ($box.from.row == $box.to2.row and $box.from.col == $box.to2.col) {
        return $start;
    }
    return $start + ":" + cellRef($box.to2);
}

/**
 * Read an A1 area, with or without a colon.
 *
 * @param text {string} an area such as `"A1:C7"`, or a single reference
 * @return {Area} the normalised area
 * @throws {Error} kind "sheets" when either half is not a cell reference
 * @example
 *   parseArea("A1:C7");
 *   parseArea("B2");      # the one-cell area at B2
 */
export func parseArea(text as string) {
    def colon as int init strings.indexOf($text, ":");
    if ($colon < 0) {
        def one as Ref init parseRef($text);
        return Area{from: $one, to2: $one};
    }
    def left as Ref init parseRef(strings.substring($text, 0, $colon));
    def right as Ref init parseRef(strings.substring($text, $colon + 1, len($text)));
    return area($left, $right);
}

/**
 * How many cells an area covers.
 *
 * @param box {Area} the area
 * @return {int} the cell count
 * @example
 *   areaSize(parseArea("A1:C7"));   # 21
 */
export func areaSize(box as Area) {
    return ($box.to2.row - $box.from.row + 1) * ($box.to2.col - $box.from.col + 1);
}

/**
 * Whether an area covers a cell.
 *
 * @param box {Area} the area
 * @param at {Ref} the cell
 * @return {bool} whether the cell is inside, edges included
 * @example
 *   areaContains(parseArea("A1:C7"), parseRef("B2"));   # true
 */
export func areaContains(box as Area, at as Ref) {
    return $at.row >= $box.from.row and $at.row <= $box.to2.row and
        $at.col >= $box.from.col and $at.col <= $box.to2.col;
}

/**
 * Split a sheet-qualified reference into its sheet name and the rest.
 *
 * Both formats qualify a cross-sheet reference with `Sheet!A1`, and quote the
 * sheet name when it holds a space or a punctuation mark (`'Second Sheet'!A1`),
 * doubling an interior quote. An unqualified reference gives an empty name.
 *
 * @param text {string} a reference, qualified or not
 * @return {list of string} two entries: the sheet name (`""` when absent) and
 *   the remaining reference
 * @example
 *   splitSheetRef("Sheet1!A1");         # ["Sheet1", "A1"]
 *   splitSheetRef("'Second Sheet'!A1"); # ["Second Sheet", "A1"]
 *   splitSheetRef("A1");                # ["", "A1"]
 */
export func splitSheetRef(text as string) {
    def out as list of string init [];
    if (len($text) > 0 and strings.substring($text, 0, 1) == "'") {
        def closing as int init closingSheetQuote($text);
        if ($closing < 0 or $closing + 1 >= len($text) or
            strings.substring($text, $closing + 1, $closing + 2) != "!") {
            fail("quoted sheet name in " + quoted($text) + " is not closed by \"'!\"");
        }
        $out[] = strings.replace(strings.substring($text, 1, $closing), "''", "'");
        $out[] = strings.substring($text, $closing + 2, len($text));
        return $out;
    }
    def bang as int init strings.indexOf($text, "!");
    if ($bang < 0) {
        $out[] = "";
        $out[] = $text;
        return $out;
    }
    $out[] = strings.substring($text, 0, $bang);
    $out[] = strings.substring($text, $bang + 1, len($text));
    return $out;
}

/**
 * The index of the quote that closes a quoted sheet name.
 *
 * An interior quote is doubled, so a run of two is literal and only a lone
 * quote closes the name.
 *
 * @param text {string} a reference whose first character is a quote
 * @return {int} the index of the closing quote, or `-1` when there is none
 */
func closingSheetQuote(text as string) {
    def i as int init 1;
    while ($i < len($text)) {
        if (strings.substring($text, $i, $i + 1) == "'") {
            if ($i + 1 < len($text) and strings.substring($text, $i + 1, $i + 2) == "'") {
                $i = $i + 2;
            } else {
                return $i;
            }
        } else {
            $i = $i + 1;
        }
    }
    return -1;
}

/**
 * Qualify a reference with a sheet name, quoting the name when it needs it.
 *
 * @param sheetName {string} the sheet name; `""` returns `cell` unqualified
 * @param cell {string} the reference or area to qualify
 * @return {string} the qualified reference
 * @example
 *   sheetRef("Sheet1", "A1");         # "Sheet1!A1"
 *   sheetRef("Second Sheet", "A1");   # "'Second Sheet'!A1"
 */
export func sheetRef(sheetName as string, cell as string) {
    if ($sheetName == "") {
        return $cell;
    }
    if (needsSheetQuotes($sheetName)) {
        return "'" + strings.replace($sheetName, "'", "''") + "'!" + $cell;
    }
    return $sheetName + "!" + $cell;
}

/**
 * Whether a sheet name has to be quoted inside a reference.
 *
 * A name that is all letters, digits and underscores and does not start with
 * a digit is written bare; anything else is quoted.
 *
 * @param sheetName {string} the sheet name
 * @return {bool} whether it needs quoting
 */
func needsSheetQuotes(sheetName as string) {
    if ($sheetName == "") {
        return false;
    }
    def safe as string init "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
    for (def ch in strings.chars($sheetName)) {
        if (strings.indexOf($safe, $ch) < 0) {
            return true;
        }
    }
    return strings.indexOf("0123456789", strings.substring($sheetName, 0, 1)) >= 0;
}
