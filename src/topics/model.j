# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# sheets - the format-independent workbook model.
# Spliced into sheets.j via include - not a standalone module.

/**
 * One sheet: a name and its cells.
 *
 * Cells are held sparsely, keyed by their A1 reference, because a spreadsheet
 * is mostly empty and both formats store it that way. `rowCount` and
 * `colCount` carry the extent, so a reader that walked a 10,000-row sheet does
 * not make a caller re-derive its shape from the keys.
 *
 * The map is keyed by the canonical A1 spelling `cellRef` produces, never by
 * what a file happened to write, so `$cells["B7"]` is the only spelling that
 * resolves. Reach cells through {@link cell} and {@link setCell} rather than
 * the map, and that stays true.
 *
 * Styles are interned. The sheet holds a table of the distinct `Style`s it
 * uses and a per-cell index into it, which is how both formats store them and
 * what stops a styled column costing one style per row. Index 0 is always the
 * default style, so a cell with no entry needs no entry.
 *
 * @field name {string} the sheet name as the file spells it
 * @field cells {map of string to Value} the non-empty cells, keyed by A1
 * @field cellStyles {map of string to int} the style index per cell, keyed by A1
 * @field styles {list of Style} the distinct styles, index 0 the default
 * @field rowCount {int} one past the highest row index used
 * @field colCount {int} one past the highest column index used
 * @field layout {SheetLayout} column widths and frozen panes
 */
export def struct Sheet {
    name as string,
    cells as map of string to Value,
    cellStyles as map of string to int,
    styles as list of Style,
    rowCount as int,
    colCount as int,
    layout as SheetLayout
};

/**
 * How a sheet is shown: its column widths and frozen panes.
 *
 * A width is in characters of the default font, the unit XLSX stores and
 * Excel shows; ODS stores a length, converted at 5.25 points a character
 * (a 7-pixel digit at 96 dpi). A column with no entry has the
 * application's default width. Gnumeric and CSV carry no layout.
 *
 * @field columnWidths {map of string to float} the width per column name (`"B"`)
 * @field frozenRows {int} how many rows at the top stay in view, 0 for none
 * @field frozenColumns {int} how many columns at the left stay in view, 0 for none
 */
export def struct SheetLayout {
    columnWidths as map of string to float,
    frozenRows as int,
    frozenColumns as int
};

/** How many points of ODS column width one character of XLSX width is. */
def const POINTS_PER_CHARACTER as float init 5.25;

/** The widest column XLSX allows, in characters. */
export def const MAX_COLUMN_WIDTH as float init 255.0;

/**
 * The layout of a sheet nobody has arranged.
 *
 * @return {SheetLayout} default widths, nothing frozen
 */
func plainLayout() {
    return SheetLayout{columnWidths: {}, frozenRows: 0, frozenColumns: 0};
}

/**
 * A workbook: an ordered list of sheets, and the date system they share.
 *
 * `date1904` belongs to the workbook rather than the cell because that is
 * where both formats keep it: one flag decides how every date serial in the
 * file is read. It is almost always false; old Mac workbooks set it.
 *
 * @field sheets {list of Sheet} the sheets, in the order the file lists them
 * @field date1904 {bool} whether date serials count from 1904 rather than 1900
 */
export def struct Workbook {
    sheets as list of Sheet,
    date1904 as bool
};

/**
 * One cell and where it goes.
 *
 * Lets a reader hand back a row's cells without being handed the sheet.
 * Threading a growing sheet through a per-row call deep-copies its cell map
 * on every call, which makes reading a sheet quadratic: 10,000 cells measured
 * 67 s that way against well under a second once each row returned only its
 * own cells.
 *
 * @field at {Ref} where the cell goes
 * @field value {Value} what it holds
 */
def struct Placed {
    at as Ref,
    value as Value
};

/**
 * An empty sheet with a name.
 *
 * @param name {string} the sheet name
 * @return {Sheet} the sheet, with no cells
 * @throws {Error} kind "sheets" when the name is empty or unusable
 * @example
 *   newSheet("Sheet1");
 */
export func newSheet(name as string) {
    checkSheetName($name);
    return Sheet{
        name: $name,
        cells: {},
        cellStyles: {},
        styles: defaultStyleTable(),
        rowCount: 0,
        colCount: 0,
        layout: plainLayout()
    };
}

/**
 * Refuse a sheet name no spreadsheet application would accept.
 *
 * The intersection of what both formats allow: non-empty, at most 31
 * characters, none of `[ ] * ? : / \`, and no quote at either end. Refusing
 * here means the deck never writes a file an application refuses to open.
 *
 * @param name {string} the proposed sheet name
 * @throws {Error} kind "sheets" when the name cannot be used
 */
func checkSheetName(name as string) {
    if ($name == "") {
        fail("a sheet name cannot be empty");
    }
    if (len($name) > 31) {
        fail("sheet name " + quoted($name) +
            " is longer than the 31 characters a sheet name may have");
    }
    for (def ch in strings.chars("[]*?:/\\")) {
        if (strings.contains($name, $ch)) {
            fail("sheet name " + quoted($name) + " holds " + quoted($ch) +
                ", which a sheet name may not");
        }
    }
    if (strings.startsWith($name, "'") or strings.endsWith($name, "'")) {
        fail("sheet name " + quoted($name) + " may not start or end with a quote");
    }
}

/**
 * An empty workbook.
 *
 * @return {Workbook} the workbook, with no sheets and the 1900 date system
 * @example
 *   newWorkbook();
 */
export func newWorkbook() {
    return Workbook{sheets: [], date1904: false};
}

/**
 * A workbook holding one empty sheet.
 *
 * The common starting point: every spreadsheet application opens a new file
 * with one sheet, and a workbook with none is invalid in both formats.
 *
 * @param name {string} the name of the first sheet
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the name is unusable
 * @example
 *   workbookWith("Sheet1");
 */
export func workbookWith(name as string) {
    def sheets as list of Sheet init [];
    $sheets[] = newSheet($name);
    return Workbook{sheets: $sheets, date1904: false};
}

/**
 * The most cells one sheet may hold when read whole.
 *
 * A per-element cap bounds how far one run can be amplified, but not how many
 * runs a file carries, so a hostile file can still ask for more cells than
 * fit in memory. The model costs roughly 9 KB a cell, so this is the point
 * past which a whole-sheet read would be the wrong tool anyway: it fails with
 * a message pointing at the streaming reader rather than being killed by the
 * kernel with nothing said.
 *
 * It is not a format limit. `MAX_ROW` times `MAX_COLUMN` is far larger, and a
 * sheet that big is read a row at a time with {@link openRows}.
 */
def const MAX_SHEET_CELLS as int init 1000000;

/**
 * Refuse a sheet with more cells than a whole-sheet read holds.
 *
 * @param name {string} the sheet name, for the message
 * @param count {int} how many cells have been collected
 * @throws {Error} kind "limit" when the count is past `MAX_SHEET_CELLS`
 */
func checkSheetCells(name as string, count as int) {
    if ($count > MAX_SHEET_CELLS) {
        failLimit("sheet " + quoted($name) + " holds at least " + convert.toString($count) +
            " cells, past the " + convert.toString(MAX_SHEET_CELLS) +
            " a whole-sheet read keeps in memory; read it a row at a time " +
            "with openRows");
    }
}

/**
 * One style and where it goes.
 *
 * The style-side counterpart of {@link Placed}, and it exists for the same
 * reason: a reader hands back the styles a row places rather than being
 * handed the sheet, so the sheet's tables are never copied per row.
 *
 * @field at {Ref} where the style goes
 * @field style {Style} the style
 */
def struct Styled {
    at as Ref,
    style as Style
};

/**
 * Build a sheet from placed cells and placed styles.
 *
 * Both tables are filled in one pass, with the styles interned as they are
 * seen, so a styled column costs one table entry.
 *
 * @param name {string} the sheet name
 * @param placed {list of Placed} the cells
 * @param styled {list of Styled} the styles
 * @return {Sheet} the sheet
 * @throws {Error} kind "sheets" when the name is unusable; kind "limit" when there are too many cells
 */
func styledSheetFrom(name as string, placed as list of Placed, styled as list of Styled) {
    def out as Sheet init sheetFrom($name, $placed);
    if (len($styled) == 0) {
        return $out;
    }
    def table as list of Style init $out.styles;
    def indices as map of string to int init $out.cellStyles;
    def rowCount as int init $out.rowCount;
    def colCount as int init $out.colCount;
    for (def one in $styled) {
        if (not onGrid($one.at) or isPlain($one.style)) {
            continue;
        }
        # Searched read-only and grown in place: handing the table to a
        # function and taking it back copied it once per styled cell.
        def index as int init styleIndexIn($table, $one.style);
        if ($index < 0) {
            $table[] = $one.style;
            $index = len($table) - 1;
        }
        $indices[cellRef($one.at)] = $index;
        if ($one.at.row + 1 > $rowCount) {
            $rowCount = $one.at.row + 1;
        }
        if ($one.at.col + 1 > $colCount) {
            $colCount = $one.at.col + 1;
        }
    }
    $out.styles = $table;
    $out.cellStyles = $indices;
    $out.rowCount = $rowCount;
    $out.colCount = $colCount;
    return $out;
}

/**
 * A fresh style table holding only the default style.
 *
 * Index 0 is the default by construction, everywhere, so a cell with no style
 * index and a cell pointing at 0 mean the same thing.
 *
 * @return {list of Style} the table
 */
func defaultStyleTable() {
    def out as list of Style init [];
    $out[] = style();
    return $out;
}

/**
 * Whether a reference is inside the addressable grid.
 *
 * The guard every reader funnels through. A file is free to claim
 * `r="999999999999"`, and taking it at face value makes that row count the
 * sheet's extent - after which any caller walking the sheet loops about a
 * trillion times. That is a denial of service out of a 657-byte file, so an
 * off-grid cell is dropped as damage and the rest of the sheet still reads.
 *
 * @param at {Ref} the reference
 * @return {bool} whether both indices are within the grid
 */
func onGrid(at as Ref) {
    return $at.row >= 0 and $at.row <= MAX_ROW and $at.col >= 0 and
        $at.col <= MAX_COLUMN;
}

/**
 * Build a sheet from cells that have already been placed.
 *
 * The map is filled in one local loop, so it is mutated in place rather than
 * copied per cell. This is the entry point every reader uses.
 *
 * @param name {string} the sheet name
 * @param placed {list of Placed} the cells, in any order
 * @return {Sheet} the sheet
 * @throws {Error} kind "sheets" when the name is unusable
 */
func sheetFrom(name as string, placed as list of Placed) {
    def cells as map of string to Value init {};
    def rowCount as int init 0;
    def colCount as int init 0;
    # Column letters by index, built as columns are first seen: spelling a
    # column per cell was most of the cost of building a sheet.
    def columns as list of string init [];
    checkSheetCells($name, len($placed));
    for (def p in $placed) {
        if (isEmpty($p.value) or not onGrid($p.at)) {
            continue;
        }
        while (len($columns) <= $p.at.col) {
            $columns[] = columnName(len($columns));
        }
        $cells[$columns[$p.at.col] + convert.toString($p.at.row + 1)] = $p.value;
        if ($p.at.row + 1 > $rowCount) {
            $rowCount = $p.at.row + 1;
        }
        if ($p.at.col + 1 > $colCount) {
            $colCount = $p.at.col + 1;
        }
    }
    return Sheet{
        name: $name,
        cells: $cells,
        cellStyles: {},
        styles: defaultStyleTable(),
        rowCount: $rowCount,
        colCount: $colCount,
        layout: plainLayout()
    };
}

/**
 * A cell's value, by A1 reference.
 *
 * An absent cell reads as `Empty`, so walking a rectangle needs no
 * presence test.
 *
 * **Do not call this per cell to read a whole sheet.** A `Sheet` is a value,
 * so every call across the module boundary copies its cell map. Reading 5,000
 * cells one at a time measured 10.9 s against 70 ms through {@link rows} -
 * about 155 times slower, and it gets worse with the size of the sheet. Use
 * {@link rows}, {@link row} or {@link valuesIn} to read in bulk, and keep
 * this for the handful of lookups where you know the reference.
 *
 * @param s {Sheet} the sheet
 * @param at {string} an A1 reference such as `"B7"`
 * @return {Value} the value, or `Empty` when the cell is not set
 * @throws {Error} kind "sheets" when the reference is malformed
 * @example
 *   cell($s, "B7");
 */
export func cell(s as Sheet, at as string) {
    return cellAt($s, parseRef($at));
}

/**
 * A cell's value, by reference.
 *
 * @param s {Sheet} the sheet
 * @param at {Ref} the reference
 * @return {Value} the value, or `Empty` when the cell is not set
 * @example
 *   cellAt($s, ref(6, 1));
 */
export func cellAt(s as Sheet, at as Ref) {
    def key as string init cellRef($at);
    if (maps.has($s.cells, $key)) {
        return $s.cells[$key];
    }
    return Value.Empty;
}

/**
 * Set a cell, by A1 reference.
 *
 * Setting a cell to `Empty` removes it, so a sheet never accumulates keys for
 * cells that hold nothing. The extent grows to cover the cell but never
 * shrinks: a sheet that held a thousand rows keeps that shape even after they
 * are cleared, which is what both formats do and what a caller walking the
 * sheet expects.
 *
 * @param s {Sheet} the sheet
 * @param at {string} an A1 reference such as `"B7"`
 * @param v {Value} the value to store
 * @return {Sheet} a fresh sheet with the cell set
 * @throws {Error} kind "sheets" when the reference is malformed
 * @example
 *   $s = setCell($s, "B7", number(42.5));
 */
export func setCell(s as Sheet, at as string, v as Value) {
    return setCellAt($s, parseRef($at), $v);
}

/**
 * Set a cell, by reference.
 *
 * @param s {Sheet} the sheet
 * @param at {Ref} the reference
 * @param v {Value} the value to store
 * @return {Sheet} a fresh sheet with the cell set
 * @example
 *   $s = setCellAt($s, ref(6, 1), number(42.5));
 */
export func setCellAt(s as Sheet, at as Ref, v as Value) {
    def key as string init cellRef($at);
    def cells as map of string to Value init $s.cells;
    if (isEmpty($v)) {
        if (maps.has($cells, $key)) {
            $cells = maps.delete($cells, $key);
        }
        return sheetWith($s, $cells, $s.cellStyles, $s.styles, NO_REACH);
    }
    $cells[$key] = $v;
    return sheetWith($s, $cells, $s.cellStyles, $s.styles, $at);
}

/**
 * The style a cell carries.
 *
 * A cell with no style of its own reads as the default, so a caller never has
 * to test for absence.
 *
 * @param s {Sheet} the sheet
 * @param at {string} an A1 reference such as `"B7"`
 * @return {Style} the style
 * @throws {Error} kind "sheets" when the reference is malformed
 * @example
 *   styleAt($s, "B7");
 */
export func styleAt(s as Sheet, at as string) {
    return styleAtRef($s, parseRef($at));
}

/**
 * The style a cell carries, by reference.
 *
 * @param s {Sheet} the sheet
 * @param at {Ref} the reference
 * @return {Style} the style
 * @example
 *   styleAtRef($s, ref(6, 1));
 */
export func styleAtRef(s as Sheet, at as Ref) {
    def key as string init cellRef($at);
    if (not maps.has($s.cellStyles, $key)) {
        return style();
    }
    def index as int init $s.cellStyles[$key];
    if ($index < 0 or $index >= len($s.styles)) {
        return style();
    }
    return $s.styles[$index];
}

/**
 * Set a cell's style.
 *
 * The style is interned into the sheet's table, so setting the same style on
 * a thousand cells costs one table entry and a thousand indices. Setting the
 * default style removes the entry.
 *
 * A style is independent of a value: styling an empty cell is allowed and is
 * how a blank cell gets a background or a border.
 *
 * @param s {Sheet} the sheet
 * @param at {string} an A1 reference such as `"B7"`
 * @param st {Style} the style
 * @return {Sheet} a fresh sheet with the style set
 * @throws {Error} kind "sheets" when the reference is malformed
 * @example
 *   $s = setStyle($s, "A1", withBold(style(), true));
 */
export func setStyle(s as Sheet, at as string, st as Style) {
    return setStyleAt($s, parseRef($at), $st);
}

/**
 * Set a cell's style, by reference.
 *
 * @param s {Sheet} the sheet
 * @param at {Ref} the reference
 * @param st {Style} the style
 * @return {Sheet} a fresh sheet with the style set
 * @example
 *   $s = setStyleAt($s, ref(0, 0), withBold(style(), true));
 */
export func setStyleAt(s as Sheet, at as Ref, st as Style) {
    checkRowCol($at.row, $at.col);
    def key as string init cellRef($at);
    def indices as map of string to int init $s.cellStyles;
    if (isPlain($st)) {
        if (maps.has($indices, $key)) {
            $indices = maps.delete($indices, $key);
        }
        return sheetWith($s, $s.cells, $indices, $s.styles, NO_REACH);
    }
    def table as list of Style init $s.styles;
    def index as int init styleIndexIn($table, $st);
    if ($index < 0) {
        $table[] = $st;
        $index = len($table) - 1;
    }
    $indices[$key] = $index;
    return sheetWith($s, $s.cells, $indices, $table, $at);
}

/**
 * Set one style across an area.
 *
 * The bulk form, and the one to use: it interns the style once and writes the
 * indices in a single pass, where calling {@link setStyle} per cell would
 * copy the sheet each time.
 *
 * @param s {Sheet} the sheet
 * @param ref {string} an A1 area such as `"A1:C1"`, or a single reference
 * @param st {Style} the style
 * @return {Sheet} a fresh sheet with the area styled
 * @throws {Error} kind "sheets" when the area is malformed
 * @example
 *   $s = setAreaStyle($s, "A1:C1", withBold(style(), true));
 */
export func setAreaStyle(s as Sheet, ref as string, st as Style) {
    def box as Area init parseArea($ref);
    if (isPlain($st)) {
        return sheetWith($s, $s.cells, withoutArea($s.cellStyles, $box), $s.styles, NO_REACH);
    }
    def table as list of Style init $s.styles;
    def index as int init styleIndexIn($table, $st);
    if ($index < 0) {
        $table[] = $st;
        $index = len($table) - 1;
    }
    def indices as map of string to int init $s.cellStyles;
    checkRowCol($box.to2.row, $box.to2.col);
    def columns as list of string init columnNames($box.to2.col + 1);
    for (def r in $box.from.row..($box.to2.row + 1)) {
        def rowText as string init convert.toString($r + 1);
        for (def c in $box.from.col..($box.to2.col + 1)) {
            $indices[$columns[$c] + $rowText] = $index;
        }
    }
    return sheetWith($s, $s.cells, $indices, $table, $box.to2);
}

/**
 * A style-index map with an area's entries removed.
 *
 * @param indices {map of string to int} the style indices
 * @param box {Area} the area to clear
 * @return {map of string to int} a fresh map without the area
 */
func withoutArea(indices as map of string to int, box as Area) {
    def kept as map of string to int init $indices;
    def columns as list of string init columnNames($box.to2.col + 1);
    for (def r in $box.from.row..($box.to2.row + 1)) {
        def rowText as string init convert.toString($r + 1);
        for (def c in $box.from.col..($box.to2.col + 1)) {
            def key as string init $columns[$c] + $rowText;
            if (maps.has($kept, $key)) {
                $kept = maps.delete($kept, $key);
            }
        }
    }
    return $kept;
}

/**
 * Where a style sits in a table.
 *
 * @param styles {list of Style} the table
 * @param st {Style} the style to find
 * @return {int} its index, or -1 when it is not there
 */
func styleIndexIn(styles as list of Style, st as Style) {
    for (def i in 0..len($styles)) {
        if ($styles[$i] == $st) {
            return $i;
        }
    }
    return -1;
}

/**
 * A reach that grows no extent, for {@link sheetWith}.
 */
def const NO_REACH as Ref init Ref{row: -1, col: -1};

/**
 * A sheet with new cell and style tables, its extent grown to cover a cell.
 *
 * Every changing function builds its result here, so a call copies the
 * sheet once: `def out as Sheet init $s` and then a changed table copied the
 * changed part twice. A field read into a literal is still deep-copied (the
 * interpreter's M30.2), so the cell map is copied once per call either way.
 *
 * A style can sit on an empty cell, so the extent follows styles as well as
 * values or a styled blank row would not be written.
 *
 * @param s {Sheet} the sheet it is based on
 * @param cells {map of string to Value} the cells
 * @param cellStyles {map of string to int} the style indices
 * @param styles {list of Style} the style table
 * @param reach {Ref} a cell the extent must cover, or {@link NO_REACH}
 * @return {Sheet} the sheet
 */
func sheetWith(
    s as Sheet,
    cells as map of string to Value,
    cellStyles as map of string to int,
    styles as list of Style,
    reach as Ref) {
    return Sheet{
        name: $s.name,
        cells: $cells,
        cellStyles: $cellStyles,
        styles: $styles,
        rowCount: math.max($s.rowCount, $reach.row + 1),
        colCount: math.max($s.colCount, $reach.col + 1),
        layout: $s.layout
    };
}

/**
 * Clear a cell.
 *
 * @param s {Sheet} the sheet
 * @param at {string} an A1 reference
 * @return {Sheet} a fresh sheet with the cell removed
 * @throws {Error} kind "sheets" when the reference is malformed
 * @example
 *   $s = clearCell($s, "B7");
 */
export func clearCell(s as Sheet, at as string) {
    return setCell($s, $at, Value.Empty);
}

/**
 * Set a column's width.
 *
 * @param s {Sheet} the sheet
 * @param column {string} the column name, such as `"B"`
 * @param width {float} the width in characters of the default font; `0.0`
 *   returns the column to the application's default
 * @return {Sheet} a fresh sheet with the width set
 * @throws {Error} kind "sheets" when the column name is malformed, or the
 *   width is negative or past `MAX_COLUMN_WIDTH`
 * @example
 *   $s = setColumnWidth($s, "B", 24.0);
 */
export func setColumnWidth(s as Sheet, column as string, width as float) {
    def key as string init columnName(columnIndex($column));
    if ($width < 0.0 or $width > MAX_COLUMN_WIDTH) {
        fail("a column width must be from 0 to " + convert.toString(MAX_COLUMN_WIDTH) +
            " characters, got " + convert.toString($width));
    }
    def layout as SheetLayout init $s.layout;
    if ($width == 0.0) {
        if (maps.has($layout.columnWidths, $key)) {
            $layout.columnWidths = maps.delete($layout.columnWidths, $key);
        }
    } else {
        $layout.columnWidths[$key] = $width;
    }
    return withLayout($s, $layout);
}

/**
 * A column's width.
 *
 * @param s {Sheet} the sheet
 * @param column {string} the column name, such as `"B"`
 * @return {float} the width in characters, `0.0` when the column has the default
 * @throws {Error} kind "sheets" when the column name is malformed
 * @example
 *   columnWidth($s, "B");   # 24.0
 */
export func columnWidth(s as Sheet, column as string) {
    def key as string init columnName(columnIndex($column));
    if (not maps.has($s.layout.columnWidths, $key)) {
        return 0.0;
    }
    return $s.layout.columnWidths[$key];
}

/**
 * Freeze the top rows and the left columns, so they stay in view.
 *
 * @param s {Sheet} the sheet
 * @param rows {int} how many rows to freeze, 0 for none
 * @param columns {int} how many columns to freeze, 0 for none
 * @return {Sheet} a fresh sheet with the panes frozen; `0, 0` unfreezes
 * @throws {Error} kind "sheets" when a count is negative or past the grid
 * @example
 *   $s = freezePanes($s, 1, 0);   # keep the header row in view
 */
export func freezePanes(s as Sheet, rows as int, columns as int) {
    checkRowCol($rows, $columns);
    def layout as SheetLayout init $s.layout;
    $layout.frozenRows = $rows;
    $layout.frozenColumns = $columns;
    return withLayout($s, $layout);
}

/**
 * A sheet with another layout, sharing everything else.
 *
 * @param s {Sheet} the sheet
 * @param layout {SheetLayout} the layout
 * @return {Sheet} the sheet
 */
func withLayout(s as Sheet, layout as SheetLayout) {
    return Sheet{
        name: $s.name,
        cells: $s.cells,
        cellStyles: $s.cellStyles,
        styles: $s.styles,
        rowCount: $s.rowCount,
        colCount: $s.colCount,
        layout: $layout
    };
}

/**
 * The columns that have a width, in column order.
 *
 * @param layout {SheetLayout} the layout
 * @return {list of int} the zero-based column indices
 */
func widenedColumns(layout as SheetLayout) {
    def out as list of int init [];
    for (def name in $layout.columnWidths) {
        $out[] = columnIndex($name);
    }
    return lists.sort($out);
}

/**
 * How many cells a sheet holds.
 *
 * The count of stored cells, not the area of the extent: a sheet with one
 * cell at Z100 has a count of 1.
 *
 * @param s {Sheet} the sheet
 * @return {int} the number of non-empty cells
 * @example
 *   cellCount($s);
 */
export func cellCount(s as Sheet) {
    return len($s.cells);
}

/**
 * The area a sheet's cells span.
 *
 * @param s {Sheet} the sheet
 * @return {Area} the extent, `A1:A1` for an empty sheet
 * @example
 *   areaRef(extent($s));   # "A1:C4"
 */
export func extent(s as Sheet) {
    if ($s.rowCount == 0 or $s.colCount == 0) {
        return Area{from: Ref{row: 0, col: 0}, to2: Ref{row: 0, col: 0}};
    }
    return Area{from: Ref{row: 0, col: 0}, to2: Ref{row: $s.rowCount - 1, col: $s.colCount - 1}};
}

/**
 * One row of values, left to right.
 *
 * Always `colCount` long, padded with `Empty`, so every row a sheet yields has
 * the same width and a caller can index it without a bounds test.
 *
 * To walk every row, call {@link rows} once rather than this in a loop: each
 * call from outside the module copies the sheet, so a per-row loop is
 * quadratic in the number of rows. See {@link cell} for the measurement.
 *
 * @param s {Sheet} the sheet
 * @param row {int} the zero-based row index
 * @return {list of Value} the row's values
 * @example
 *   row($s, 0);
 */
export func row(s as Sheet, row as int) {
    def out as list of Value init [];
    for (def c in 0..$s.colCount) {
        $out[] = cellAt($s, Ref{row: $row, col: $c});
    }
    return $out;
}

/**
 * Every row of a sheet, top to bottom.
 *
 * **The way to read a sheet.** One call hands back every row, so the sheet is
 * copied once instead of once per access - which is the difference between 70
 * ms and 10.9 s over 5,000 cells (see {@link cell}).
 *
 * Reads the whole sheet into memory. For a sheet too large for that, use the
 * streaming reader: {@link openRows}.
 *
 * @param s {Sheet} the sheet
 * @return {list of list of Value} the rows
 * @example
 *   for (def r in rows($s)) { process($r); }
 */
export func rows(s as Sheet) {
    # The column names are spelled once and each row number once per row:
    # going through cellAt built every reference from scratch.
    def columns as list of string init columnNames($s.colCount);
    def out as list of list of Value init [];
    for (def r in 0..$s.rowCount) {
        def rowText as string init convert.toString($r + 1);
        def line as list of Value init [];
        for (def c in 0..$s.colCount) {
            def key as string init $columns[$c] + $rowText;
            if (maps.has($s.cells, $key)) {
                $line[] = $s.cells[$key];
            } else {
                $line[] = Value.Empty;
            }
        }
        $out[] = $line;
    }
    return $out;
}

/**
 * Every value in an area, row by row.
 *
 * The bulk reader for part of a sheet: one call, one copy of the sheet, and a
 * rectangle of values back. Cells outside what the sheet holds read as
 * `Empty`, so the shape is always exactly the area asked for.
 *
 * @param s {Sheet} the sheet
 * @param ref {string} an A1 area such as `"A1:C7"`, or a single reference
 * @return {list of list of Value} the values, one list per row of the area
 * @throws {Error} kind "sheets" when the area is malformed
 * @example
 *   for (def r in valuesIn($s, "A1:C7")) { process($r); }
 */
export func valuesIn(s as Sheet, ref as string) {
    def box as Area init parseArea($ref);
    def out as list of list of Value init [];
    for (def r in $box.from.row..($box.to2.row + 1)) {
        def line as list of Value init [];
        for (def c in $box.from.col..($box.to2.col + 1)) {
            $line[] = cellAt($s, Ref{row: $r, col: $c});
        }
        $out[] = $line;
    }
    return $out;
}

/**
 * Replace a row's values, left to right from column A.
 *
 * The cell map is detached once for the whole row rather than once per cell,
 * where looping over {@link setCellAt} would copy the growing map per cell.
 *
 * **Building a whole sheet this way is still quadratic**, because a `Sheet` is
 * a value and each call has to copy its map once. A 2 000-row sheet measured
 * 72 s row by row against 0.4 s through {@link sheetOf}. Use `sheetOf` to
 * build a sheet from data you already have, and this to change a row of one
 * that exists.
 *
 * @param s {Sheet} the sheet
 * @param row {int} the zero-based row index
 * @param values {list of Value} the values to write
 * @return {Sheet} a fresh sheet with the row set
 * @example
 *   $s = setRow($s, 0, [text("Name"), text("Qty")]);
 */
export func setRow(s as Sheet, row as int, values as list of Value) {
    checkRowCol($row, 0);
    def cells as map of string to Value init $s.cells;
    def rowCount as int init $s.rowCount;
    def colCount as int init $s.colCount;
    def rowText as string init convert.toString($row + 1);
    for (def c in 0..len($values)) {
        checkRowCol($row, $c);
        def key as string init columnName($c) + $rowText;
        if (isEmpty($values[$c])) {
            if (maps.has($cells, $key)) {
                $cells = maps.delete($cells, $key);
            }
            continue;
        }
        $cells[$key] = $values[$c];
        if ($row + 1 > $rowCount) {
            $rowCount = $row + 1;
        }
        if ($c + 1 > $colCount) {
            $colCount = $c + 1;
        }
    }
    return Sheet{
        name: $s.name,
        cells: $cells,
        cellStyles: $s.cellStyles,
        styles: $s.styles,
        rowCount: $rowCount,
        colCount: $colCount,
        layout: $s.layout
    };
}

/**
 * A sheet built from rows of values in one pass.
 *
 * **The way to build a sheet.** The cell map is filled once, so this is linear
 * where calling {@link setRow} per row is quadratic: 2 000 rows measured 0.4 s
 * here against 72 s row by row, and the gap widens with size.
 *
 * Rows are taken top to bottom from row 1 and left to right from column A.
 * Ragged rows are fine, and an `Empty` is not stored.
 *
 * @param name {string} the sheet name
 * @param lines {list of list of Value} the rows, top to bottom
 * @return {Sheet} the sheet
 * @throws {Error} kind "sheets" when the name is unusable or the data is off the grid
 * @example
 *   def s as Sheet init sheetOf("Sales", [
 *       [text("Item"), text("Qty")],
 *       [text("Widget"), integer(4)]
 *   ]);
 */
export func sheetOf(name as string, lines as list of list of Value) {
    checkSheetName($name);
    def cells as map of string to Value init {};
    def rowCount as int init 0;
    def colCount as int init 0;
    def columns as list of string init [];
    for (def r in 0..len($lines)) {
        def line as list of Value init $lines[$r];
        def rowText as string init convert.toString($r + 1);
        for (def c in 0..len($line)) {
            if (isEmpty($line[$c])) {
                continue;
            }
            checkRowCol($r, $c);
            while (len($columns) <= $c) {
                $columns[] = columnName(len($columns));
            }
            $cells[$columns[$c] + $rowText] = $line[$c];
            if ($r + 1 > $rowCount) {
                $rowCount = $r + 1;
            }
            if ($c + 1 > $colCount) {
                $colCount = $c + 1;
            }
        }
    }
    return Sheet{
        name: $name,
        cells: $cells,
        cellStyles: {},
        styles: defaultStyleTable(),
        rowCount: $rowCount,
        colCount: $colCount,
        layout: plainLayout()
    };
}

/**
 * Append a row below everything the sheet holds.
 *
 * @param s {Sheet} the sheet
 * @param values {list of Value} the values to write
 * @return {Sheet} a fresh sheet with the row added
 * @example
 *   $s = addRow($s, [text("Gadget"), integer(2)]);
 */
export func addRow(s as Sheet, values as list of Value) {
    return setRow($s, $s.rowCount, $values);
}

# Every loop below walks `$wb.sheets` **by index**. `for (def s in $wb.sheets)`
# binds each sheet to `$s`, and Jennifer's value semantics deep-copy its whole
# cells map to do it - so a name lookup over a workbook of 3 000-cell sheets
# costs a 3 000-entry map copy per sheet it walks past. `hasSheet` alone
# measured 2.4 s of a recalculation that way. Indexing copies nothing, so a
# sheet is only ever materialised where one is returned.

/**
 * A sheet by name.
 *
 * @param wb {Workbook} the workbook
 * @param name {string} the sheet name, matched exactly
 * @return {Sheet} the sheet
 * @throws {Error} kind "sheets" when no sheet has that name
 * @example
 *   sheetByName($wb, "Q3");
 */
export func sheetByName(wb as Workbook, name as string) {
    for (def i in 0..len($wb.sheets)) {
        if ($wb.sheets[$i].name == $name) {
            return $wb.sheets[$i];
        }
    }
    fail("the workbook has no sheet named " + quoted($name) +
        " (it has " + sheetNameList($wb) + ")");
    return newSheet("unreachable");
}

/**
 * The sheet names, for an error message.
 *
 * @param wb {Workbook} the workbook
 * @return {string} the names quoted and joined, or a note that there are none
 */
func sheetNameList(wb as Workbook) {
    if (len($wb.sheets) == 0) {
        return "no sheets";
    }
    def names as list of string init [];
    for (def i in 0..len($wb.sheets)) {
        $names[] = quoted($wb.sheets[$i].name);
    }
    return strings.join($names, ", ");
}

/**
 * Whether a workbook has a sheet by that name.
 *
 * @param wb {Workbook} the workbook
 * @param name {string} the sheet name
 * @return {bool} whether it is there
 * @example
 *   hasSheet($wb, "Q3");
 */
export func hasSheet(wb as Workbook, name as string) {
    for (def i in 0..len($wb.sheets)) {
        if ($wb.sheets[$i].name == $name) {
            return true;
        }
    }
    return false;
}

/**
 * The sheet names, in file order.
 *
 * @param wb {Workbook} the workbook
 * @return {list of string} the names
 * @example
 *   sheetNames($wb);   # ["Sheet1", "Second Sheet"]
 */
export func sheetNames(wb as Workbook) {
    def out as list of string init [];
    for (def i in 0..len($wb.sheets)) {
        $out[] = $wb.sheets[$i].name;
    }
    return $out;
}

/**
 * Store a sheet, replacing the one of the same name or appending it.
 *
 * The round trip for an edit: take a sheet out with {@link sheetByName},
 * change it, and put it back. Renaming a sheet through this adds a second
 * sheet rather than renaming the first, which is why {@link renameSheet}
 * exists.
 *
 * @param wb {Workbook} the workbook
 * @param s {Sheet} the sheet to store
 * @return {Workbook} a fresh workbook holding the sheet
 * @example
 *   $wb = putSheet($wb, $s);
 */
export func putSheet(wb as Workbook, s as Sheet) {
    # One copy of the sheet list: copying the workbook first and then its
    # sheet list copied every sheet twice.
    def sheets as list of Sheet init $wb.sheets;
    def replaced as bool init false;
    for (def i in 0..len($sheets)) {
        if ($sheets[$i].name == $s.name) {
            $sheets[$i] = $s;
            $replaced = true;
            break;
        }
    }
    if (not $replaced) {
        $sheets[] = $s;
    }
    return Workbook{sheets: $sheets, date1904: $wb.date1904};
}

/**
 * Add a sheet, refusing a duplicate name.
 *
 * @param wb {Workbook} the workbook
 * @param s {Sheet} the sheet to add
 * @return {Workbook} a fresh workbook holding the sheet
 * @throws {Error} kind "sheets" when a sheet of that name is already there
 * @example
 *   $wb = addSheet($wb, newSheet("Q4"));
 */
export func addSheet(wb as Workbook, s as Sheet) {
    if (hasSheet($wb, $s.name)) {
        fail("the workbook already has a sheet named " + quoted($s.name));
    }
    def sheets as list of Sheet init $wb.sheets;
    $sheets[] = $s;
    return Workbook{sheets: $sheets, date1904: $wb.date1904};
}

/**
 * Remove a sheet by name.
 *
 * @param wb {Workbook} the workbook
 * @param name {string} the sheet to remove
 * @return {Workbook} a fresh workbook without it
 * @throws {Error} kind "sheets" when no sheet has that name, or it is the only sheet
 * @example
 *   $wb = removeSheet($wb, "Scratch");
 */
export func removeSheet(wb as Workbook, name as string) {
    if (not hasSheet($wb, $name)) {
        fail("the workbook has no sheet named " + quoted($name));
    }
    if (len($wb.sheets) == 1) {
        fail("cannot remove " + quoted($name) +
            ": a workbook must keep at least one sheet");
    }
    def kept as list of Sheet init [];
    for (def i in 0..len($wb.sheets)) {
        if ($wb.sheets[$i].name != $name) {
            $kept[] = $wb.sheets[$i];
        }
    }
    return Workbook{sheets: $kept, date1904: $wb.date1904};
}

/**
 * Rename a sheet, keeping its position.
 *
 * @param wb {Workbook} the workbook
 * @param from {string} the current name
 * @param to2 {string} the new name
 * @return {Workbook} a fresh workbook with the sheet renamed
 * @throws {Error} kind "sheets" when `from` is absent, `to2` is taken, or `to2` is unusable
 * @example
 *   $wb = renameSheet($wb, "Sheet1", "Q3");
 */
export func renameSheet(wb as Workbook, from as string, to2 as string) {
    if (not hasSheet($wb, $from)) {
        fail("the workbook has no sheet named " + quoted($from));
    }
    if ($from != $to2 and hasSheet($wb, $to2)) {
        fail("the workbook already has a sheet named " + quoted($to2));
    }
    checkSheetName($to2);
    def sheets as list of Sheet init $wb.sheets;
    for (def i in 0..len($sheets)) {
        if ($sheets[$i].name == $from) {
            $sheets[$i].name = $to2;
        }
    }
    return Workbook{sheets: $sheets, date1904: $wb.date1904};
}
