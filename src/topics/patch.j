# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# sheets - setting cells of an existing XLSX file in place.
# Spliced into sheets.j via include - not a standalone module.
#
# A read and a write rebuild every part from the model, which drops whatever
# the model does not hold (charts, defined names, conditional formats, the
# calculation chain) and renumbers the styles and shared strings. Filling a
# few cells of someone else's workbook wants the opposite: every byte left as
# it was except the cells asked for.

/**
 * One cell to set, by position and canonical reference.
 *
 * @field at {Ref} the cell
 * @field ref {string} its A1 spelling
 * @field value {Value} what to put there
 */
def struct CellChange {
    at as Ref,
    ref as string,
    value as Value
};

/**
 * What a cell keeps of its old markup when it is replaced.
 *
 * @field style {string} its `s` attribute, `""` for none
 * @field hadFormula {bool} whether it held a formula
 */
def struct OldCell {
    style as string,
    hadFormula as bool
};

/**
 * A patched worksheet part, and whether a formula was overwritten.
 *
 * @field part {string} the worksheet XML
 * @field formulaRemoved {bool} whether a formula cell now holds a value
 */
def struct PatchedSheet {
    part as string,
    formulaRemoved as bool
};

/**
 * What the cell markup needs from the rest of the workbook.
 *
 * @field dateStyles {map of string to bool} which `cellXfs` indices mean a date
 * @field date1904 {bool} whether the workbook counts dates from 1904
 */
def struct PatchContext {
    dateStyles as map of string to bool,
    date1904 as bool
};

/** The attribute text that marks an array formula. */
def const ARRAY_PROBE as bytes init encoding.encode("utf-8", "t=\"array\"");

/**
 * Set cells of an existing XLSX workbook, leaving everything else as it was.
 *
 * Every other part of the container keeps its bytes: styles, shared strings,
 * charts, defined names, the other sheets. In the sheet itself only the rows
 * holding a changed cell are rewritten, and in them only the changed cells; a
 * replaced cell keeps its style, so a value written into a formatted column
 * shows with the column's format.
 *
 * Text is written inline (`t="inlineStr"`) so the shared string table stays
 * untouched. `Empty` clears a cell's value and keeps its style. A formula is
 * written with the cached result its `Value` carries; Excel recalculates
 * it when the workbook is next calculated. A cell whose formula is
 * replaced by a value leaves `calcChain.xml` pointing at it, so that part is
 * dropped and Excel rebuilds it on load.
 *
 * Refused rather than written wrong: the cell holding a shared formula other
 * cells use (they would lose theirs), a cell inside an array formula, and a
 * date in a cell whose format is not a date (it would show as a number).
 *
 * @param raw {bytes} the `.xlsx` file
 * @param sheetName {string} the sheet to change; `""` takes the first
 * @param changes {map of string to Value} the cells to set, by A1 reference
 * @return {bytes} the changed file
 * @throws {Error} kind "sheets" when the container, the sheet or a reference
 *   is unusable, or a change is refused as above
 * @example
 *   def out as bytes init patchXlsx(fs.readBytes("in.xlsx"), "Sheet1", {"D2": number(42.0)});
 */
export func patchXlsx(raw as bytes, sheetName as string, changes as map of string to Value) {
    def entries as list of archive.Entry init unpackEntries($raw);
    def parts as map of string to bytes init {};
    for (def entry in $entries) {
        $parts[$entry.name] = $entry.data;
    }
    if (not maps.has($parts, XLSX_WORKBOOK)) {
        fail("the container has no " + quoted(XLSX_WORKBOOK) +
            ", so it is not an XLSX workbook");
    }
    def targets as map of string to string init readRelationships($parts);
    def chosen as SheetEntry init pickSheetEntry(
        readSheetEntries($parts[XLSX_WORKBOOK]),
        $sheetName);
    def path as string init sheetPartPath($parts, $targets, $chosen);
    if ($path == "") {
        fail("the sheet " + quoted($chosen.name) +
            " names a part that is not in the container");
    }
    def context as PatchContext init PatchContext{
        dateStyles: readDateStyles($parts, $targets),
        date1904: readDate1904($parts[XLSX_WORKBOOK])
    };
    def patched as PatchedSheet init patchWorksheet(
        $parts[$path],
        plannedChanges($changes),
        $context);
    def calcChain as string init "";
    if ($patched.formulaRemoved) {
        $calcChain = findPartBySuffix($parts, $targets, "calcChain.xml");
    }
    def members as list of Member init [];
    for (def entry in $entries) {
        if ($entry.name == $path) {
            $members[] = member($path, encoding.encode("utf-8", $patched.part));
        } elseif ($calcChain == "") {
            $members[] = member($entry.name, $entry.data);
        } elseif ($entry.name != $calcChain) {
            $members[] = member($entry.name, withoutCalcChainMention($entry, $calcChain));
        }
    }
    return zip($members);
}

/**
 * The changes, checked and in row-major order.
 *
 * @param changes {map of string to Value} the cells to set, by A1 reference
 * @return {list of CellChange} one per cell, sorted by row then column
 * @throws {Error} kind "sheets" when a reference is malformed or two name the same cell
 */
func plannedChanges(changes as map of string to Value) {
    def byPosition as map of string to CellChange init {};
    def positions as list of int init [];
    for (def key in $changes) {
        def at as Ref init parseRef($key);
        def position as int init $at.row * (MAX_COLUMN + 1) + $at.col;
        def slot as string init convert.toString($position);
        if (maps.has($byPosition, $slot)) {
            fail("two changes name the cell " + cellRef($at));
        }
        $byPosition[$slot] = CellChange{at: $at, ref: cellRef($at), value: $changes[$key]};
        $positions[] = $position;
    }
    def out as list of CellChange init [];
    for (def position in lists.sort($positions)) {
        $out[] = $byPosition[convert.toString($position)];
    }
    return $out;
}

/**
 * A worksheet part with the changes made.
 *
 * Walks the rows in order: a row with no change is copied as it was, one
 * with changes is rewritten cell by cell, and a change in a row the sheet
 * does not have yet gets a new row in its place.
 *
 * @param src {bytes} the worksheet part
 * @param plan {list of CellChange} the changes, row-major
 * @param context {PatchContext} the workbook's date styles and system
 * @return {PatchedSheet} the part and whether a formula was overwritten
 * @throws {Error} kind "sheets" when the part is unusable or a change is refused
 */
func patchWorksheet(src as bytes, plan as list of CellChange, context as PatchContext) {
    def root as Node init rootNode($src);
    def sheetData as Node init childNamed($src, $root, "sheetData");
    if (not isNode($sheetData)) {
        fail("the worksheet has no <sheetData>");
    }
    if ($sheetData.name != "sheetData") {
        fail("a worksheet written with a namespace prefix (<" + $sheetData.name +
            ">) cannot be patched in place");
    }
    def hasArrays as bool init indexOfByte($src, ARRAY_PROBE, 0, len($src)) >= 0;
    def arrays as list of Area init [];
    def out as list of string init [];
    $out[] = headWithDimension($src, $root, $sheetData, $plan);
    $out[] = "<sheetData>";
    def next as int init 0;
    def removed as bool init false;
    def at as int init $sheetData.openEnd;
    def rowIndex as int init 0;
    if (not $sheetData.closed) {
        fail("the worksheet's <sheetData> is cut short; a damaged file is not patched");
    }
    def rowNode as Node init missingNode();
    if ($sheetData.innerEnd >= $sheetData.openEnd) {
        $rowNode = nextChild($src, $sheetData.openEnd, $sheetData.innerEnd);
    }
    while (isNode($rowNode)) {
        if (not $rowNode.closed) {
            fail("a <row> in the worksheet is cut short; a damaged file is not patched");
        }
        $rowIndex = xlsxRowIndex($src, $rowNode, $rowIndex);
        if ($hasArrays and indexOfByte($src, ARRAY_PROBE, $rowNode.start, $rowNode.end) >= 0) {
            for (def box in arrayRangesIn($src, $rowNode, $rowIndex)) {
                $arrays[] = $box;
            }
        }
        $out[] = byteText($src, $at, $rowNode.start);
        def first as int init $next;
        while ($next < len($plan) and $plan[$next].at.row < $rowIndex) {
            $next = $next + 1;
        }
        $out[] = newRowsMarkup($plan, $first, $next, $context);
        $first = $next;
        while ($next < len($plan) and $plan[$next].at.row == $rowIndex) {
            refuseInsideArray($plan[$next], $arrays);
            $next = $next + 1;
        }
        if ($first == $next) {
            $out[] = byteText($src, $rowNode.start, $rowNode.end);
        } else {
            def row as PatchedSheet init patchedRow(
                $src,
                $rowNode,
                $rowIndex,
                $plan[$first..$next],
                $context);
            $out[] = $row.part;
            $removed = $removed or $row.formulaRemoved;
        }
        $at = $rowNode.end;
        $rowIndex = $rowIndex + 1;
        $rowNode = nextChild($src, $rowNode.end, $sheetData.innerEnd);
    }
    if ($sheetData.innerEnd > $at) {
        $out[] = byteText($src, $at, $sheetData.innerEnd);
    }
    $out[] = newRowsMarkup($plan, $next, len($plan), $context);
    $out[] = "</sheetData>";
    $out[] = byteText($src, $sheetData.end, len($src));
    return PatchedSheet{part: strings.join($out, ""), formulaRemoved: $removed};
}

/**
 * The part up to `<sheetData>`, with `<dimension>` grown to cover the changes.
 *
 * @param src {bytes} the worksheet part
 * @param root {Node} the `<worksheet>` element
 * @param sheetData {Node} the `<sheetData>` element
 * @param plan {list of CellChange} the changes
 * @return {string} the head of the part
 */
func headWithDimension(src as bytes, root as Node, sheetData as Node, plan as list of CellChange) {
    def dimension as Node init childNamed($src, $root, "dimension");
    if (not isNode($dimension) or $dimension.start > $sheetData.start or len($plan) == 0) {
        return byteText($src, 0, $sheetData.start);
    }
    def box as Area init Area{from: $plan[0].at, to2: $plan[0].at};
    def written as string init nodeAttr($src, $dimension, "ref");
    try {
        $box = parseArea($written);
    } catch (e) {
        # A dimension that does not read is rebuilt from the changes alone;
        # it is a hint an application recomputes.
        $written = "";
    }
    for (def change in $plan) {
        $box = Area{
            from: Ref{
                row: math.min($box.from.row, $change.at.row),
                col: math.min($box.from.col, $change.at.col)
            },
            to2: Ref{
                row: math.max($box.to2.row, $change.at.row),
                col: math.max($box.to2.col, $change.at.col)
            }
        };
    }
    def grown as string init areaRef($box);
    if ($grown == $written) {
        return byteText($src, 0, $sheetData.start);
    }
    return byteText($src, 0, $dimension.start) + tagEmpty("dimension", {"ref": $grown}) +
        byteText($src, $dimension.end, $sheetData.start);
}

/**
 * New `<row>` elements for changes in rows the sheet does not have.
 *
 * @param plan {list of CellChange} the changes
 * @param from {int} the first change to write
 * @param to2 {int} one past the last
 * @param context {PatchContext} the workbook's date styles and system
 * @return {string} the rows, `""` when there are none
 */
func newRowsMarkup(plan as list of CellChange, from as int, to2 as int, context as PatchContext) {
    def out as list of string init [];
    def i as int init $from;
    while ($i < $to2) {
        def row as int init $plan[$i].at.row;
        def cells as list of string init [];
        while ($i < $to2 and $plan[$i].at.row == $row) {
            $cells[] = patchCellMarkup($plan[$i], OldCell{style: "", hadFormula: false}, $context);
            $i = $i + 1;
        }
        def body as string init strings.join($cells, "");
        if ($body != "") {
            $out[] = tagOpenWith("row", {"r": convert.toString($row + 1)}) + $body + tagClose("row");
        }
    }
    return strings.join($out, "");
}

/**
 * One existing row with its changed cells replaced and new ones inserted.
 *
 * @param src {bytes} the worksheet part
 * @param rowNode {Node} the row element
 * @param rowIndex {int} the row's zero-based index
 * @param changes {list of CellChange} this row's changes, by column
 * @param context {PatchContext} the workbook's date styles and system
 * @return {PatchedSheet} the row's markup and whether a formula was overwritten
 * @throws {Error} kind "sheets" when a change is refused
 */
func patchedRow(
    src as bytes,
    rowNode as Node,
    rowIndex as int,
    changes as list of CellChange,
    context as PatchContext) {
    def out as list of string init [];
    def removed as bool init false;
    def inserted as bool init false;
    def next as int init 0;
    def colIndex as int init 0;
    def at as int init $rowNode.openEnd;
    def cellNode as Node init missingNode();
    if ($rowNode.innerEnd >= $rowNode.openEnd) {
        $cellNode = nextChild($src, $rowNode.openEnd, $rowNode.innerEnd);
    }
    while (isNode($cellNode)) {
        $out[] = byteText($src, $at, $cellNode.start);
        $at = $cellNode.end;
        def col as int init xlsxCellRef($src, $cellNode, $rowIndex, $colIndex).col;
        $colIndex = $col + 1;
        while ($next < len($changes) and $changes[$next].at.col < $col) {
            $out[] = patchCellMarkup(
                $changes[$next],
                OldCell{style: "", hadFormula: false},
                $context);
            $inserted = true;
            $next = $next + 1;
        }
        if ($next < len($changes) and $changes[$next].at.col == $col) {
            def old as OldCell init replacedCell($src, $cellNode, $changes[$next].ref);
            if ($old.hadFormula and not isFormula($changes[$next].value)) {
                $removed = true;
            }
            $out[] = patchCellMarkup($changes[$next], $old, $context);
            $next = $next + 1;
        } else {
            $out[] = byteText($src, $cellNode.start, $cellNode.end);
        }
        $cellNode = nextChild($src, $cellNode.end, $rowNode.innerEnd);
    }
    if ($rowNode.innerEnd > $at) {
        $out[] = byteText($src, $at, $rowNode.innerEnd);
    }
    while ($next < len($changes)) {
        $out[] = patchCellMarkup($changes[$next], OldCell{style: "", hadFormula: false}, $context);
        $inserted = true;
        $next = $next + 1;
    }
    def open as string init rowOpenTag($src, $rowNode, $inserted);
    return PatchedSheet{part: $open + strings.join($out, "") + "</row>", formulaRemoved: $removed};
}

/**
 * A row's open tag, made an open tag if it closed itself.
 *
 * `spans` is a hint of which columns the row uses; a row that gained a cell
 * may fall outside it, so it is dropped then rather than left wrong.
 *
 * @param src {bytes} the worksheet part
 * @param rowNode {Node} the row element
 * @param inserted {bool} whether a cell was added to the row
 * @return {string} the open tag
 */
func rowOpenTag(src as bytes, rowNode as Node, inserted as bool) {
    def tag as string init byteText($src, $rowNode.start, $rowNode.openEnd);
    if (strings.endsWith($tag, "/>")) {
        $tag = $tag[..len($tag) - 2] + ">";
    }
    if (not $inserted) {
        return $tag;
    }
    def spans as int init strings.indexOf($tag, " spans=");
    if ($spans < 0) {
        return $tag;
    }
    def quote as string init $tag[$spans + 7..$spans + 8];
    def close as int init strings.indexOf($tag[$spans + 8..len($tag)], $quote);
    if ($close < 0) {
        return $tag;
    }
    return $tag[..$spans] + $tag[$spans + 9 + $close..len($tag)];
}

/**
 * What a cell about to be replaced keeps, refusing a shared formula's anchor.
 *
 * @param src {bytes} the worksheet part
 * @param cellNode {Node} the cell element
 * @param ref {string} the cell's reference, for the message
 * @return {OldCell} its style and whether it held a formula
 * @throws {Error} kind "sheets" when the cell anchors a shared or array formula
 */
func replacedCell(src as bytes, cellNode as Node, ref as string) {
    def formula as Node init missingNode();
    if ($cellNode.innerEnd >= $cellNode.openEnd) {
        $formula = childNamed($src, $cellNode, "f");
    }
    if (isNode($formula)) {
        def kind as string init nodeAttr($src, $formula, "t");
        if (($kind == "shared" or $kind == "array") and nodeAttr($src, $formula, "ref") != "") {
            fail($ref + " holds the " + $kind + " formula of " + nodeAttr($src, $formula, "ref") +
                "; overwriting it would break the other cells that use it");
        }
    }
    return OldCell{style: nodeAttr($src, $cellNode, "s"), hadFormula: isNode($formula)};
}

/**
 * The array formula ranges a row's cells anchor.
 *
 * @param src {bytes} the worksheet part
 * @param rowNode {Node} the row element
 * @param rowIndex {int} the row's zero-based index
 * @return {list of Area} the ranges
 */
func arrayRangesIn(src as bytes, rowNode as Node, rowIndex as int) {
    def out as list of Area init [];
    if ($rowNode.innerEnd < $rowNode.openEnd) {
        return $out;
    }
    for (def cellNode in childNodes($src, $rowNode.openEnd, $rowNode.innerEnd)) {
        if ($cellNode.innerEnd < $cellNode.openEnd) {
            continue;
        }
        def formula as Node init childNamed($src, $cellNode, "f");
        if (not isNode($formula) or nodeAttr($src, $formula, "t") != "array") {
            continue;
        }
        try {
            $out[] = parseArea(nodeAttr($src, $formula, "ref"));
        } catch (e) {
            continue;
        }
    }
    return $out;
}

/**
 * Refuse a change inside an array formula's range.
 *
 * @param change {CellChange} the change
 * @param arrays {list of Area} the array ranges seen so far
 * @throws {Error} kind "sheets" when the cell is inside one
 */
func refuseInsideArray(change as CellChange, arrays as list of Area) {
    for (def box in $arrays) {
        if ($change.at.row >= $box.from.row and $change.at.row <= $box.to2.row and
            $change.at.col >= $box.from.col and $change.at.col <= $box.to2.col) {
            fail($change.ref + " is inside the array formula of " + areaRef($box) +
                ", which can only be changed as a whole");
        }
    }
}

/**
 * Whether a value is a formula.
 *
 * @param v {Value} the value
 * @return {bool} whether it is a `Formula`
 */
func isFormula(v as Value) {
    match ($v) {
        when Formula(f) { return true; }
        else { return false; }
    }
}

/**
 * The `<c>` element for a change, keeping the old cell's style.
 *
 * @param change {CellChange} the change
 * @param old {OldCell} what the cell held, or an empty one for a new cell
 * @param context {PatchContext} the workbook's date styles and system
 * @return {string} the cell, `""` for an unstyled cell cleared
 * @throws {Error} kind "sheets" when a date goes into a cell without a date format
 */
func patchCellMarkup(change as CellChange, old as OldCell, context as PatchContext) {
    def attrs as map of string to string init {"r": $change.ref};
    if ($old.style != "") {
        $attrs["s"] = $old.style;
    }
    def v as Value init $change.value;
    match ($v) {
        when Text(t) {
            $attrs["t"] = "inlineStr";
            return xlsxWrapCell(
                $attrs,
                "<is>" + tagTextWith("t", {"xml:space": "preserve"}, $t.body) + "</is>");
        }
        when Number(n) { return xlsxWrapCell($attrs, tagText("v", numberAttr($n.amount))); }
        when Bool(b) {
            $attrs["t"] = "b";
            return xlsxWrapCell($attrs, tagText("v", boolDigit($b.flag)));
        }
        when Stamp(st) {
            def key as string init strings.trim($old.style);
            if (not maps.has($context.dateStyles, $key) or not $context.dateStyles[$key]) {
                fail("a date in " + $change.ref + " needs a cell with a date format; " +
                    "write toSerial's number or format the cell first");
            }
            return xlsxWrapCell(
                $attrs,
                tagText("v", numberAttr(toSerial($st.at, $context.date1904))));
        }
        when Formula(f) { return xlsxFormulaCell($attrs, $f.source, $f.cached); }
        when Err(err) {
            $attrs["t"] = "e";
            return xlsxWrapCell($attrs, tagText("v", $err.code));
        }
        when Empty { if ($old.style == "") {
            return "";
        }
        return tagEmpty("c", $attrs); }
    }
}

/**
 * A part with its mention of a dropped `calcChain.xml` removed.
 *
 * The content types list it as an override and the workbook's relationships
 * point at it; both would name a part that is no longer there.
 *
 * @param entry {archive.Entry} the member
 * @param calcChain {string} the dropped part's path
 * @return {bytes} the member's data, without the mention
 */
func withoutCalcChainMention(entry as archive.Entry, calcChain as string) {
    if ($entry.name == "[Content_Types].xml") {
        return withoutChild($entry.data, "Override", "PartName", "/" + $calcChain);
    }
    if ($entry.name == XLSX_WORKBOOK_RELS) {
        return withoutChild($entry.data, "Relationship", "Target", "calcChain.xml");
    }
    return $entry.data;
}

/**
 * A document with the root's children of one kind that match removed.
 *
 * @param src {bytes} the document
 * @param name {string} the children's local name
 * @param attribute {string} the attribute to test
 * @param suffix {string} what its value ends with to be removed
 * @return {bytes} the document, the rest of it byte for byte
 */
func withoutChild(src as bytes, name as string, attribute as string, suffix as string) {
    def root as Node init rootNode($src);
    def kept as list of string init [];
    def at as int init 0;
    for (def child in childNodes($src, $root.openEnd, $root.innerEnd)) {
        if (localName($child.name) == $name and
            strings.endsWith(nodeAttr($src, $child, $attribute), $suffix)) {
            $kept[] = byteText($src, $at, $child.start);
            $at = $child.end;
        }
    }
    if ($at == 0) {
        return $src;
    }
    $kept[] = byteText($src, $at, len($src));
    return encoding.encode("utf-8", strings.join($kept, ""));
}
