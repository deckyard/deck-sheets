# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# sheets - reading a sheet one row at a time.
# Spliced into sheets.j via include - not a standalone module.

/**
 * A cursor over one sheet's rows.
 *
 * A `Workbook` holds every cell of every sheet. Through a cursor the only
 * things alive at once are the sheet's markup and the row being looked at.
 *
 * The sheet is read once and its rows walked in place, so there is nothing to
 * close. The markup waits in `rest` as strings, which copy in constant time,
 * and moves into the `src` window a slice at a time, so a cursor that is
 * copied for every row (one held in a top-level variable is) copies the window
 * and not the sheet. The calling shape is `$r = nextRow($r)`:
 *
 *     def r as RowReader init openRows("huge.xlsx", "Sheet1");
 *     while (hasRow($r)) {
 *         $r = nextRow($r);
 *         process(rowValues($r));
 *     }
 *
 * @field src {bytes} the window: the part of the sheet's rows being walked
 * @field at {int} where the scan has reached in the window
 * @field limit {int} where the window's markup ends
 * @field rowIndex {int} the zero-based index of the row just read
 * @field values {list of Value} the row just read, left to right
 * @field more {bool} whether another row is waiting
 * @field kind {Format} which format's markup is being walked
 * @field shared {SharedTable} the shared string table, for XLSX
 * @field dateStyles {map of string to bool} which styles mean a date, for XLSX
 * @field date1904 {bool} whether the workbook counts dates from 1904
 * @field namespaces {map of string to string} the prefixes declared around
 *   the rows, for XLSX, so a row decoded on its own can resolve them
 * @field rest {list of string} the sheet's rows not yet moved into the
 *   window, in slices of up to 256 KiB
 */
export def struct RowReader {
    src as bytes,
    at as int,
    limit as int,
    rowIndex as int,
    values as list of Value,
    more as bool,
    kind as Format,
    shared as SharedTable,
    dateStyles as map of string to bool,
    date1904 as bool,
    namespaces as map of string to string,
    rest as list of string
};

/**
 * How many bytes of markup a cursor moves into its window at a time.
 *
 * Large enough that refills are rare, small enough that copying the window
 * for each row costs little next to decoding the row.
 */
def const ROW_WINDOW as int init 262144;

/**
 * Open a cursor over a sheet of a file.
 *
 * The format comes from the extension, as with {@link open}. Only ODS and
 * XLSX stream; the others hold one sheet of text or one small document, so
 * reading them whole is no worse.
 *
 * @param filePath {string} the file to read
 * @param sheetName {string} the sheet to walk; `""` takes the first
 * @return {RowReader} a cursor positioned before the first row
 * @throws {Error} kind "sheets" when the file, the format or the sheet is unusable
 * @example
 *   def r as RowReader init openRows("huge.xlsx", "Sheet1");
 */
export func openRows(filePath as string, sheetName as string) {
    if (not fs.exists($filePath)) {
        fail("no such file: " + quoted($filePath));
    }
    return openRowsFromBytes(fs.readBytes($filePath), formatOf($filePath), $sheetName);
}

/**
 * Open a cursor over a sheet of a file already in memory.
 *
 * @param raw {bytes} the file
 * @param kind {Format} the format to read it as
 * @param sheetName {string} the sheet to walk; `""` takes the first
 * @return {RowReader} a cursor positioned before the first row
 * @throws {Error} kind "sheets" when the format or the sheet is unusable
 * @example
 *   def r as RowReader init openRowsFromBytes($bytes, Format.Ods, "");
 */
export func openRowsFromBytes(raw as bytes, kind as Format, sheetName as string) {
    match ($kind) {
        when Ods { return openOdsRows($raw, $sheetName); }
        when Xlsx { return openXlsxRows($raw, $sheetName); }
        else { return openWholeSheetRows($raw, $kind, $sheetName); }
    }
}

/**
 * A cursor that was filled from a whole-sheet read.
 *
 * Gnumeric and delimited text do not reward streaming: one is a small document
 * and the other is a single table of text. Rather than refuse them, the sheet
 * is read whole and handed out row by row, so a caller can use one loop for
 * every format.
 *
 * @param raw {bytes} the file
 * @param kind {Format} the format
 * @param sheetName {string} the sheet to walk; `""` takes the first
 * @return {RowReader} a cursor over the rows
 * @throws {Error} kind "sheets" when the sheet is not there
 */
func openWholeSheetRows(raw as bytes, kind as Format, sheetName as string) {
    def wb as Workbook init readFormat($raw, $kind);
    def s as Sheet init firstOrNamedSheet($wb, $sheetName);
    # The rows are re-serialised into the same markup the ODS walker reads, so
    # one cursor implementation serves every format.
    def parts as list of string init [];
    $parts[] = "<rows>";
    # No style names: the cursor hands back values, and a caller streaming a
    # sheet is reading data rather than formatting.
    def unstyled as list of string init [];
    for (def line in rows($s)) {
        $parts[] = odsRowMarkup($line, $unstyled);
    }
    $parts[] = "</rows>";
    def src as bytes init partsBytes($parts);
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        fail("the sheet has no rows to read");
    }
    return readerOver($src, $root.openEnd, $root.innerEnd, Format.Ods);
}

/**
 * A cursor over the rows in a byte range of a part.
 *
 * The range is cut into the cursor's `rest`, each cut moved back to the start
 * of a character; the window starts empty and is filled by the first
 * {@link hasRow} or {@link nextRow}.
 *
 * @param src {bytes} the part
 * @param from {int} where the rows start
 * @param limit {int} where they end
 * @param kind {Format} the format to report
 * @return {RowReader} the cursor
 * @throws {Error} kind "sheets" when the rows are not UTF-8
 */
func readerOver(src as bytes, from as int, limit as int, kind as Format) {
    def rest as list of string init [];
    def at as int init $from;
    while ($at < $limit) {
        def cut as int init $at + ROW_WINDOW;
        if ($cut >= $limit) {
            $cut = $limit;
        } else {
            # Back off to the start of a character, so each slice decodes alone.
            while ($cut > $at and $src[$cut] >= 0x80 and $src[$cut] < 0xc0) {
                $cut = $cut - 1;
            }
            if ($cut == $at) {
                $cut = $at + ROW_WINDOW;
            }
        }
        try {
            $rest[] = byteText($src, $at, $cut);
        } catch (e) {
            if (isGeneric($e.kind)) {
                throw $e;
            }
            fail("the sheet's rows are not UTF-8: " + $e.message);
        }
        $at = $cut;
    }
    return RowReader{
        src: binary.make(0),
        at: 0,
        limit: 0,
        rowIndex: -1,
        values: [],
        more: true,
        kind: $kind,
        shared: packShared([]),
        dateStyles: {},
        date1904: false,
        namespaces: {},
        rest: $rest
    };
}

/**
 * Open a cursor over a sheet of an ODS container.
 *
 * @param raw {bytes} the `.ods` file
 * @param sheetName {string} the sheet to walk; `""` takes the first
 * @return {RowReader} the cursor
 * @throws {Error} kind "sheets" when the container or the sheet is unusable
 */
func openOdsRows(raw as bytes, sheetName as string) {
    def parts as map of string to bytes init unzip($raw);
    if (not maps.has($parts, "content.xml")) {
        fail("the container has no content.xml, so it is not an ODS workbook");
    }
    def src as bytes init $parts["content.xml"];
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        fail("content.xml has no root element");
    }
    def spreadsheet as Node init findSpreadsheet($src, $root);
    if (not isNode($spreadsheet)) {
        fail("content.xml has no <office:spreadsheet>, so it is not a workbook");
    }
    def table as Node init findOdsTable($src, $spreadsheet, $sheetName);
    if (not isNode($table)) {
        fail("the workbook has no sheet named " + quoted($sheetName));
    }
    return readerOver($src, $table.openEnd, $table.innerEnd, Format.Ods);
}

/**
 * The table a sheet name picks out, or the first one.
 *
 * @param src {bytes} the content part
 * @param spreadsheet {Node} the spreadsheet element
 * @param sheetName {string} the sheet to find; `""` takes the first
 * @return {Node} the table element, or a node pointing at nothing
 */
func findOdsTable(src as bytes, spreadsheet as Node, sheetName as string) {
    def child as Node init nextChild($src, $spreadsheet.openEnd, $spreadsheet.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "table") {
            if ($sheetName == "" or nodeAttr($src, $child, "name") == $sheetName) {
                return $child;
            }
        }
        $child = nextChild($src, $child.end, $spreadsheet.innerEnd);
    }
    return missingNode();
}

/**
 * Open a cursor over a sheet of an XLSX container.
 *
 * The shared string table and the date styles are read up front, because a
 * cell cannot be understood without them and they are small next to a sheet.
 *
 * @param raw {bytes} the `.xlsx` file
 * @param sheetName {string} the sheet to walk; `""` takes the first
 * @return {RowReader} the cursor
 * @throws {Error} kind "sheets" when the container or the sheet is unusable
 */
func openXlsxRows(raw as bytes, sheetName as string) {
    def parts as map of string to bytes init unzip($raw);
    if (not maps.has($parts, XLSX_WORKBOOK)) {
        fail("the container has no " + quoted(XLSX_WORKBOOK) +
            ", so it is not an XLSX workbook");
    }
    def workbookPart as bytes init $parts[XLSX_WORKBOOK];
    def targets as map of string to string init readRelationships($parts);
    def entries as list of SheetEntry init readSheetEntries($workbookPart);
    def chosen as SheetEntry init pickSheetEntry($entries, $sheetName);
    def path as string init sheetPartPath($parts, $targets, $chosen);
    if ($path == "") {
        fail("the sheet " + quoted($chosen.name) +
            " names a part that is not in the container");
    }
    def src as bytes init $parts[$path];
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        fail("the worksheet part has no root element");
    }
    def sheetData as Node init childNamed($src, $root, "sheetData");
    if (not isNode($sheetData)) {
        fail("the worksheet has no <sheetData>");
    }
    def reader as RowReader init readerOver(
        $src,
        $sheetData.openEnd,
        $sheetData.innerEnd,
        Format.Xlsx);
    $reader.shared = packShared(readSharedStrings($parts, $targets));
    $reader.dateStyles = readDateStyles($parts, $targets);
    $reader.date1904 = readDate1904($workbookPart);
    $reader.namespaces = declaredPrefixes($src, [$root, $sheetData]);
    return $reader;
}

/**
 * The namespace prefixes the open tags of some elements declare.
 *
 * Excel declares its extension namespaces on `<worksheet>` and writes
 * attributes such as `x14ac:dyDescent` on nearly every `<row>`. A row cut out
 * of the sheet and decoded on its own would have those prefixes undeclared,
 * so their bindings are collected once here and handed to every decode.
 * Later elements win, as an inner declaration does in the document.
 *
 * @param src {bytes} the whole document
 * @param nodes {list of Node} the enclosing elements, outermost first
 * @return {map of string to string} prefix to namespace URI
 * @throws {Error} kind "sheets" when an open tag is not well-formed
 */
func declaredPrefixes(src as bytes, nodes as list of Node) {
    def out as map of string to string init {};
    for (def node in $nodes) {
        def tag as string init byteText($src, $node.start, $node.openEnd);
        if (not strings.endsWith($tag, "/>")) {
            $tag = $tag[..len($tag) - 1] + "/>";
        }
        def tree as xml.Value init xml.element("empty");
        try {
            $tree = xml.decode($tag, $out);
        } catch (e) {
            if (isGeneric($e.kind)) {
                throw $e;
            }
            fail("<" + $node.name + "> is not well-formed: " + $e.message);
        }
        for (def name in xml.attrs($tree)) {
            if (strings.startsWith($name, "xmlns:")) {
                $out[$name[6..]] = xml.attr($tree, $name);
            }
        }
    }
    return $out;
}

/**
 * The sheet entry a name picks out, or the first one.
 *
 * @param entries {list of SheetEntry} the workbook's sheet list
 * @param sheetName {string} the sheet to find; `""` takes the first
 * @return {SheetEntry} the entry
 * @throws {Error} kind "sheets" when there are no sheets, or none by that name
 */
func pickSheetEntry(entries as list of SheetEntry, sheetName as string) {
    if (len($entries) == 0) {
        fail("the workbook lists no sheets");
    }
    if ($sheetName == "") {
        return $entries[0];
    }
    for (def entry in $entries) {
        if ($entry.name == $sheetName) {
            return $entry;
        }
    }
    fail("the workbook has no sheet named " + quoted($sheetName));
    return $entries[0];
}

/**
 * Whether another row is waiting.
 *
 * @param r {RowReader} the cursor
 * @return {bool} whether {@link nextRow} would read a row
 * @example
 *   while (hasRow($r)) { $r = nextRow($r); }
 */
export func hasRow(r as RowReader) {
    if (not $r.more) {
        return false;
    }
    def rowNode as Node init peekRow($r);
    if (len($r.rest) == 0 or isWholeRow($rowNode)) {
        return isNode($rowNode);
    }
    # The window ends before the next row does: look on in a widened copy,
    # once per window, since this cursor cannot be handed back.
    def wider as RowReader init $r;
    while (len($wider.rest) > 0 and not isWholeRow($rowNode)) {
        $wider = widen($wider);
        $rowNode = peekRow($wider);
    }
    return isNode($rowNode);
}

/**
 * Whether a row element found in the window is all there.
 *
 * A row cut off by the window's end reads as unclosed, or as no element at
 * all when its open tag is cut. Either way the window needs more markup.
 *
 * @param rowNode {Node} what {@link peekRow} found
 * @return {bool} whether it is a complete element
 */
func isWholeRow(rowNode as Node) {
    return isNode($rowNode) and $rowNode.closed;
}

/**
 * Move the next slice of `rest` into the window.
 *
 * The rows already read are dropped from the window first, so it holds at
 * most one slice plus the unread tail of the last.
 *
 * @param r {RowReader} the cursor, with `rest` not empty
 * @return {RowReader} the cursor with a wider window
 */
func widen(r as RowReader) {
    $r.src = binary.concat($r.src[$r.at..$r.limit], encoding.encode("utf-8", $r.rest[0]));
    $r.rest = $r.rest[1..];
    $r.at = 0;
    $r.limit = len($r.src);
    return $r;
}

/**
 * The next row element waiting, if any.
 *
 * @param r {RowReader} the cursor
 * @return {Node} the row element, or a node pointing at nothing
 */
func peekRow(r as RowReader) {
    def child as Node init nextChild($r.src, $r.at, $r.limit);
    while (isNode($child)) {
        if (isRowElement($child)) {
            return $child;
        }
        $child = nextChild($r.src, $child.end, $r.limit);
    }
    return missingNode();
}

/**
 * Whether an element is a row in either format's markup.
 *
 * @param node {Node} the element
 * @return {bool} whether it is a row
 */
func isRowElement(node as Node) {
    def name as string init localName($node.name);
    return $name == "row" or $name == "table-row";
}

/**
 * Read the next row.
 *
 * @param r {RowReader} the cursor
 * @return {RowReader} a fresh cursor whose `values` are the row just read
 * @throws {Error} kind "sheets" when there is no row left; test with {@link hasRow} first
 * @example
 *   $r = nextRow($r);
 *   def values as list of Value init rowValues($r);
 */
export func nextRow(r as RowReader) {
    def rowNode as Node init peekRow($r);
    while (len($r.rest) > 0 and not isWholeRow($rowNode)) {
        $r = widen($r);
        $rowNode = peekRow($r);
    }
    if (not isNode($rowNode)) {
        fail("there is no row left to read; test with hasRow first");
    }
    def rowIndex as int init $r.rowIndex + 1;
    def values as list of Value init [];
    match ($r.kind) {
        when Xlsx {
            $rowIndex = xlsxRowIndex($r.src, $rowNode, $r.rowIndex + 1);
            $values = xlsxRowValues($r, $rowNode);
        }
        else { $values = odsRowValues($r, $rowNode); }
    }
    # Updated in place and handed back: called as `$r = nextRow($r)` from a
    # function, the cursor moves in and out without a copy. A new literal
    # would copy `src` and `shared` out of the parameter for every row.
    $r.at = $rowNode.end;
    $r.rowIndex = $rowIndex;
    $r.values = $values;
    return $r;
}

/**
 * One ODS row's values, left to right.
 *
 * @param r {RowReader} the cursor
 * @param rowNode {Node} the row element
 * @return {list of Value} the values
 */
func odsRowValues(r as RowReader, rowNode as Node) {
    def out as list of Value init [];
    def cellNode as Node init nextChild($r.src, $rowNode.openEnd, $rowNode.innerEnd);
    while (isNode($cellNode)) {
        def tag as string init localName($cellNode.name);
        if ($tag == "table-cell" or $tag == "covered-table-cell") {
            def span as int init repeatCount($r.src, $cellNode, "number-columns-repeated");
            def v as Value init odsCellValue($r.src, $cellNode);
            for (def i in 0..$span) {
                $out[] = $v;
            }
        }
        $cellNode = nextChild($r.src, $cellNode.end, $rowNode.innerEnd);
    }
    return trimTrailingEmpty($out);
}

/**
 * One XLSX row's values, left to right.
 *
 * The row is handed to `xml.decode` whole, once, rather than walked cell by
 * cell with the scanner. One native parse of a row amortises over all its
 * cells, where an interpreted walk pays per attribute: measured over a
 * 20-column sheet, the walk cost about 0.3 ms per cell against 0.01 ms here.
 *
 * ODS cannot do this (see {@link odsRowValues}), but XLSX can, because a
 * cell's value sits in a `<v>` or an `<is><t>` of pure text and never in
 * mixed content, so nothing depends on the order of a node's children.
 *
 * The cells carry their own references, so a gap has to be filled in: the
 * list a caller gets is positional, with `Empty` where the row said nothing.
 *
 * @param r {RowReader} the cursor
 * @param rowNode {Node} the row element
 * @return {list of Value} the values
 */
func xlsxRowValues(r as RowReader, rowNode as Node) {
    def out as list of Value init [];
    def tree as xml.Value init decodeLeaf($r.src, $rowNode, $r.namespaces);
    for (def cellNode in xml.children($tree)) {
        if (localName(xml.tag($cellNode)) != "c") {
            continue;
        }
        def col as int init xlsxTreeColumn($cellNode, len($out));
        while (len($out) < $col) {
            $out[] = Value.Empty;
        }
        $out[] = xlsxTreeCellValue($cellNode, $r.shared, $r.dateStyles, $r.date1904);
    }
    return trimTrailingEmpty($out);
}

/**
 * Which column a decoded `<c>` sits in.
 *
 * @param cellNode {xml.Value} the decoded cell element
 * @param fallback {int} the column position would give
 * @return {int} the zero-based column index
 */
func xlsxTreeColumn(cellNode as xml.Value, fallback as int) {
    if (not xml.hasAttr($cellNode, "r")) {
        return $fallback;
    }
    def out as int init $fallback;
    try {
        $out = parseRef(xml.attr($cellNode, "r")).col;
    } catch (e) {
        return $fallback;
    }
    return $out;
}

/**
 * The value a decoded `<c>` holds.
 *
 * The same rules as `xlsxCellValue`, read off a tree instead of bytes.
 * Children are matched on their local names, as the scanner matches them, so
 * a sheet written with a prefix (`<x:c><x:v>`) reads the same.
 *
 * @param cellNode {xml.Value} the decoded cell element
 * @param shared {SharedTable} the shared string table
 * @param dateStyles {map of string to bool} which style indices mean a date
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {Value} the value
 */
func xlsxTreeCellValue(
    cellNode as xml.Value,
    shared as SharedTable,
    dateStyles as map of string to bool,
    date1904 as bool) {
    def kind as string init "n";
    if (xml.hasAttr($cellNode, "t")) {
        $kind = xml.attr($cellNode, "t");
    }
    def rawValue as string init treeChildText($cellNode, "v");
    def inline as string init "";
    if (xml.has($cellNode, "*:is")) {
        $inline = treeRunText(xml.get($cellNode, "*:is"));
    }
    if (xml.has($cellNode, "*:f")) {
        def cached as string init $rawValue;
        if ($kind == "s") {
            $cached = sharedString($shared, $rawValue);
        } elseif ($kind == "inlineStr") {
            $cached = $inline;
        }
        return Value.Formula{source: treeChildText($cellNode, "f"), cached: $cached};
    }
    match ($kind) {
        when "s" { return xlsxSharedValue($shared, $rawValue); }
        when "inlineStr" { return xlsxTextValue($inline); }
        when "str" { return xlsxTextValue($rawValue); }
        when "b" { return xlsxBoolValue($rawValue); }
        when "e" { return xlsxErrorValue($rawValue); }
        when "d" { return xlsxIsoDateValue($rawValue); }
        else { return xlsxTreeNumberValue($cellNode, $rawValue, $dateStyles, $date1904); }
    }
}

/**
 * The text of a decoded element's child, matched on its local name.
 *
 * @param node {xml.Value} the element
 * @param name {string} the child's local name
 * @return {string} the child's text, or `""` when there is no such child
 */
func treeChildText(node as xml.Value, name as string) {
    def path as string init "*:" + $name;
    if (not xml.has($node, $path)) {
        return "";
    }
    return xml.text(xml.get($node, $path));
}

/**
 * The text of a decoded `<is>` or `<si>`: its `<t>`, or all its runs joined.
 *
 * A partly formatted string is split into `<r>` runs, each with its own
 * `<t>`, as `sharedStringText` reads them from bytes.
 *
 * @param entry {xml.Value} the element
 * @return {string} the text
 */
func treeRunText(entry as xml.Value) {
    def parts as list of string init [];
    for (def child in xml.children($entry)) {
        def tag as string init localName(xml.tag($child));
        if ($tag == "t") {
            $parts[] = xml.text($child);
        } elseif ($tag == "r") {
            $parts[] = treeChildText($child, "t");
        }
    }
    return strings.join($parts, "");
}

/**
 * An integer attribute of a decoded element, or `-1`.
 *
 * @param node {xml.Value} the element
 * @param name {string} the attribute
 * @return {int} the value, or `-1` when it is absent or unreadable
 */
func treeIndexAttr(node as xml.Value, name as string) {
    if (not xml.hasAttr($node, $name)) {
        return -1;
    }
    def out as int init -1;
    try {
        $out = convert.toInt(strings.trim(xml.attr($node, $name)));
    } catch (e) {
        return -1;
    }
    return $out;
}

/**
 * A decoded numeric cell, which may be a date in disguise.
 *
 * @param cellNode {xml.Value} the decoded cell element
 * @param rawValue {string} the value as written
 * @param dateStyles {map of string to bool} which style indices mean a date
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {Value} the value
 */
func xlsxTreeNumberValue(
    cellNode as xml.Value,
    rawValue as string,
    dateStyles as map of string to bool,
    date1904 as bool) {
    if (strings.trim($rawValue) == "") {
        return Value.Empty;
    }
    def amount as float init 0.0;
    try {
        $amount = convert.toFloat(strings.trim($rawValue));
    } catch (e) {
        return Value.Text{body: $rawValue};
    }
    def styled as bool init false;
    if (xml.hasAttr($cellNode, "s")) {
        def key as string init strings.trim(xml.attr($cellNode, "s"));
        if (maps.has($dateStyles, $key)) {
            $styled = $dateStyles[$key];
        }
    }
    if (not $styled) {
        return Value.Number{amount: $amount};
    }
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    try {
        $at = fromSerial($amount, $date1904);
    } catch (e) {
        return Value.Number{amount: $amount};
    }
    return Value.Stamp{at: $at, dateOnly: $amount == math.floor($amount)};
}

/**
 * Drop the empty cells at the end of a row.
 *
 * A row padded out to the end of the grid is common, and a caller asking for
 * a row wants its cells rather than its padding.
 *
 * @param values {list of Value} the row's values
 * @return {list of Value} the values with trailing empties removed
 */
func trimTrailingEmpty(values as list of Value) {
    def last as int init len($values);
    while ($last > 0 and isEmpty($values[$last - 1])) {
        $last = $last - 1;
    }
    if ($last == len($values)) {
        return $values;
    }
    return $values[0..$last];
}

/**
 * The row just read.
 *
 * @param r {RowReader} the cursor
 * @return {list of Value} the values, left to right, trailing empties removed
 * @example
 *   def values as list of Value init rowValues($r);
 */
export func rowValues(r as RowReader) {
    return $r.values;
}

/**
 * Which row was just read, one-based as a user counts them.
 *
 * For XLSX this is the row's own `r` number, so a sheet that skips empty rows
 * reports the real gaps. For ODS it counts `<table:table-row>` elements: a run
 * the file wrote as one element with `table:number-rows-repeated` counts once.
 *
 * @param r {RowReader} the cursor
 * @return {int} the one-based row number, or 0 before the first row
 * @example
 *   io.printf("row %d\n", rowNumber($r));
 */
export func rowNumber(r as RowReader) {
    return $r.rowIndex + 1;
}

/**
 * The row just read, as text.
 *
 * The common case for a streaming read: one row of strings to hand to a
 * parser, a database or a log line.
 *
 * @param r {RowReader} the cursor
 * @return {list of string} each value rendered by {@link asString}
 * @example
 *   def fields as list of string init rowStrings($r);
 */
export func rowStrings(r as RowReader) {
    def out as list of string init [];
    for (def v in $r.values) {
        $out[] = asString($v);
    }
    return $out;
}
