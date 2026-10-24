# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the OpenDocument spreadsheet reader.
# Spliced into sheets.j via include - not a standalone module.

/** The media type an ODS container declares. */
export def const ODS_MIMETYPE as string init "application/vnd.oasis.opendocument.spreadsheet";

/**
 * How many repeated columns or rows the reader will expand.
 *
 * ODS run-length encodes empty space, and a file routinely says
 * `table:number-columns-repeated="16384"` to pad a row out to the end of the
 * grid. Expanding those literally would turn a small file into millions of
 * cells, so a run of empty cells is skipped rather than materialised and only
 * a run carrying a value is expanded, up to this many.
 */
def const MAX_REPEAT as int init 4096;

/**
 * The most cells one cell element may expand to.
 *
 * `MAX_REPEAT` alone is not enough, because the two axes multiply: a single
 * element carrying both `number-rows-repeated="1048576"` and
 * `number-columns-repeated="16384"` expands to 16.7 million cells, and a
 * 474-byte file built that way reached 7.1 GB before the kernel killed it.
 * Capping each axis caps the shape; capping the product caps the damage.
 *
 * A run past this is clamped rather than refused, because the file is still
 * readable and padding a row to the end of the grid is a normal thing for an
 * application to write.
 */
def const MAX_BLOCK_CELLS as int init 65536;

/**
 * Read an ODS container.
 *
 * The cells come out of `content.xml`, which is walked with the scanner
 * rather than decoded into a tree: a sheet's rows are handed to `xml.decode`
 * one at a time, so peak memory follows the largest row rather than the file.
 *
 * @param raw {bytes} the `.ods` file
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the container or its content is unreadable
 * @example
 *   def wb as Workbook init readOds(fs.readBytes("sales.ods"));
 */
export func readOds(raw as bytes) {
    def parts as map of string to bytes init unzip($raw);
    checkOdsMimetype($parts);
    if (not maps.has($parts, "content.xml")) {
        fail("the container has no content.xml, so it is not an ODS workbook");
    }
    # `styles.xml` matters for the formats. LibreOffice splits its number
    # styles between the two parts - a file it wrote had two of them in the
    # content and forty-nine in `styles.xml` - so reading only the content
    # loses most of a real document's formats.
    def extra as map of string to string init {};
    if (maps.has($parts, "styles.xml")) {
        $extra = odsNumberStylesIn($parts["styles.xml"]);
    }
    return readOdsDocument($parts["content.xml"], $extra);
}

/**
 * Every number style a part declares, from either of its style containers.
 *
 * `styles.xml` puts them under `<office:styles>` and
 * `<office:automatic-styles>` both, and a document uses whichever.
 *
 * @param part {bytes} the part to read
 * @return {map of string to string} style name to format code
 */
func odsNumberStylesIn(part as bytes) {
    def out as map of string to string init {};
    def root as Node init rootNode($part);
    if (not isNode($root)) {
        return $out;
    }
    for (def container in ["styles", "automatic-styles"]) {
        def node as Node init childNamed($part, $root, $container);
        if (isNode($node)) {
            # Bound once: calling it inside the loop re-parsed all forty-nine
            # styles per name.
            def found as map of string to string init readOdsNumberStyles($part, $node);
            for (def name in maps.keys($found)) {
                $out[$name] = $found[$name];
            }
        }
    }
    return $out;
}

/**
 * Refuse a container that declares itself as something other than a spreadsheet.
 *
 * A missing `mimetype` is tolerated: the member is required by ODF but some
 * writers omit it, and `content.xml` is the authority on what is actually
 * inside. A *present* member naming a different document type is refused,
 * because opening a text document as a workbook helps nobody.
 *
 * @param parts {map of string to bytes} the container's members
 * @throws {Error} kind "sheets" when the declared media type is not a spreadsheet
 */
func checkOdsMimetype(parts as map of string to bytes) {
    if (not maps.has($parts, "mimetype")) {
        return;
    }
    def declared as string init strings.trim(convert.stringFromBytes($parts["mimetype"], "utf-8"));
    if ($declared != "" and $declared != ODS_MIMETYPE) {
        fail("the container declares the media type " + quoted($declared) +
            ", which is not an OpenDocument spreadsheet");
    }
}

/**
 * Read an ODS `content.xml`.
 *
 * For a caller holding an unpacked container. Number styles kept only in
 * `styles.xml` are not seen, so a cell whose format lives there reads without
 * it; {@link readOds} reads both parts.
 *
 * @param content {bytes} the `content.xml` member
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the document has no spreadsheet in it
 * @example
 *   def wb as Workbook init readOdsContent($bytes);
 */
export func readOdsContent(content as bytes) {
    return readOdsDocument($content, {});
}

/**
 * A content part as a workbook, with formats from elsewhere in the container.
 *
 * @param content {bytes} the content part
 * @param extra {map of string to string} number styles from `styles.xml`
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the part is not a readable spreadsheet
 */
func readOdsDocument(content as bytes, extra as map of string to string) {
    def root as Node init rootNode($content);
    if (not isNode($root)) {
        fail("content.xml has no root element");
    }
    def spreadsheet as Node init findSpreadsheet($content, $root);
    if (not isNode($spreadsheet)) {
        fail("content.xml has no <office:spreadsheet>, so it is not a workbook");
    }
    def wb as Workbook init newWorkbook();
    def styles as map of string to Style init readOdsStyles($content, $root, $extra);
    def sheets as list of Sheet init [];
    def child as Node init nextChild($content, $spreadsheet.openEnd, $spreadsheet.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "table") {
            $sheets[] = readOdsTable($content, $child, len($sheets), $styles);
        }
        $child = nextChild($content, $child.end, $spreadsheet.innerEnd);
    }
    if (len($sheets) == 0) {
        fail("the workbook has no sheets");
    }
    $wb.sheets = $sheets;
    return $wb;
}

/**
 * The document's cell styles, by the name a cell points at.
 *
 * ODF puts a cell's look in a named `<style:style>` under
 * `<office:automatic-styles>`, split across three property groups - the cell's
 * own, its paragraph's and its text's - because the alignment belongs to the
 * paragraph in ODF's model and to the cell in OOXML's.
 *
 * A style that inherits from another through `style:parent-style-name` is
 * read as what it says itself: resolving the chain needs `styles.xml` as well
 * as the content, and a cell's own properties are what a writer puts there.
 *
 * @param src {bytes} the content part
 * @param root {Node} the document root
 * @param extra {map of string to string} number styles from `styles.xml`
 * @return {map of string to Style} the styles, keyed by name
 */
func readOdsStyles(src as bytes, root as Node, extra as map of string to string) {
    def out as map of string to Style init {};
    def automatic as Node init childNamed($src, $root, "automatic-styles");
    if (not isNode($automatic)) {
        return $out;
    }
    def formats as map of string to string init $extra;
    def own as map of string to string init readOdsNumberStyles($src, $automatic);
    for (def name in maps.keys($own)) {
        $formats[$name] = $own[$name];
    }
    def child as Node init nextChild($src, $automatic.openEnd, $automatic.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "style" and
            nodeAttr($src, $child, "family") == "table-cell") {
            def name as string init nodeAttr($src, $child, "name");
            if ($name != "") {
                $out[$name] = readOdsCellStyle($src, $child, $formats);
            }
        }
        $child = nextChild($src, $child.end, $automatic.innerEnd);
    }
    return $out;
}

/**
 * The format code each number style describes.
 *
 * ODF builds a format out of components rather than a code string, so the
 * code is put back together from them - see `odfFormatCode` in odsfmt.j. Two
 * passes, because a style with several sections names its sub-styles by
 * `style:map` and a map may point forwards.
 *
 * @param src {bytes} the content part
 * @param automatic {Node} the automatic styles element
 * @return {map of string to string} style name to format code
 */
func readOdsNumberStyles(src as bytes, automatic as Node) {
    def byName as map of string to Node init {};
    def order as list of string init [];
    def child as Node init nextChild($src, $automatic.openEnd, $automatic.innerEnd);
    while (isNode($child)) {
        def name as string init nodeAttr($src, $child, "name");
        if ($name != "" and isOdfNumberStyle(localName($child.name))) {
            $byName[$name] = $child;
            $order[] = $name;
        }
        $child = nextChild($src, $child.end, $automatic.innerEnd);
    }
    def out as map of string to string init {};
    for (def i in 0..len($order)) {
        def name as string init $order[$i];
        def code as string init odfFormatCode($src, $byName[$name], $byName);
        if ($code != "") {
            $out[$name] = $code;
        }
    }
    return $out;
}

/**
 * Whether an element name is one of ODF's number style kinds.
 *
 * @param tag {string} the element's local name
 * @return {bool} whether it describes a format
 */
func isOdfNumberStyle(tag as string) {
    match ($tag) {
        when "number-style", "percentage-style", "currency-style",
             "date-style", "time-style", "text-style", "boolean-style" { return true; }
        else { return false; }
    }
}

/**
 * One `<style:style>` as a style.
 *
 * @param src {bytes} the content part
 * @param styleNode {Node} the style element
 * @param formats {map of string to string} number style name to format code
 * @return {Style} the style
 */
func readOdsCellStyle(src as bytes, styleNode as Node, formats as map of string to string) {
    def out as Style init style();
    def dataStyle as string init nodeAttr($src, $styleNode, "data-style-name");
    if (maps.has($formats, $dataStyle)) {
        $out.format = normalisedFormat($formats[$dataStyle]);
    }
    def child as Node init nextChild($src, $styleNode.openEnd, $styleNode.innerEnd);
    while (isNode($child)) {
        match (localName($child.name)) {
            when "table-cell-properties" { $out = readOdsCellProperties($out, $src, $child); }
            when "paragraph-properties" {
                $out.align = alignFromName(nodeAttr($src, $child, "text-align"));
            }
            when "text-properties" { $out = readOdsTextProperties($out, $src, $child); }
            else {
            }
        }
        $child = nextChild($src, $child.end, $styleNode.innerEnd);
    }
    return $out;
}

/**
 * The cell-level properties onto a style.
 *
 * @param st {Style} the style so far
 * @param src {bytes} the content part
 * @param props {Node} the properties element
 * @return {Style} a fresh style
 */
func readOdsCellProperties(st as Style, src as bytes, props as Node) {
    def out as Style init $st;
    $out.background = odsColour(nodeAttr($src, $props, "background-color"));
    $out.border = borderFromName(odsBorderWeight(nodeAttr($src, $props, "border")));
    $out.wrap = nodeAttr($src, $props, "wrap-option") == "wrap";
    def valign as string init nodeAttr($src, $props, "vertical-align");
    if ($valign != "") {
        $out.valign = valignFromName($valign);
    }
    return $out;
}

/**
 * The text-level properties onto a style.
 *
 * @param st {Style} the style so far
 * @param src {bytes} the content part
 * @param props {Node} the properties element
 * @return {Style} a fresh style
 */
func readOdsTextProperties(st as Style, src as bytes, props as Node) {
    def out as Style init $st;
    $out.bold = nodeAttr($src, $props, "font-weight") == "bold";
    $out.italic = nodeAttr($src, $props, "font-style") == "italic";
    def underline as string init nodeAttr($src, $props, "text-underline-style");
    $out.underline = $underline != "" and $underline != "none";
    def family as string init nodeAttr($src, $props, "font-name");
    if ($family == "") {
        $family = nodeAttr($src, $props, "font-family");
    }
    $out.fontName = $family;
    $out.fontSize = odsPoints(nodeAttr($src, $props, "font-size"));
    $out.colour = odsColour(nodeAttr($src, $props, "color"));
    return $out;
}

/**
 * An ODF colour as six hexadecimal digits.
 *
 * @param raw {string} the attribute, such as `"#FFF2CC"`
 * @return {string} the colour, or `""` when unreadable
 */
func odsColour(raw as string) {
    def body as string init strings.trim($raw);
    if (strings.startsWith($body, "#")) {
        $body = strings.substring($body, 1, len($body));
    }
    if (len($body) != 6) {
        return "";
    }
    def upper as string init strings.upper($body);
    for (def ch in strings.chars($upper)) {
        if (strings.indexOf("0123456789ABCDEF", $ch) < 0) {
            return "";
        }
    }
    return $upper;
}

/**
 * A point measurement as a number.
 *
 * @param raw {string} the attribute, such as `"11pt"`
 * @return {float} the size, or `0.0` when unreadable
 */
func odsPoints(raw as string) {
    def body as string init strings.trim($raw);
    if (strings.endsWith($body, "pt")) {
        $body = strings.substring($body, 0, len($body) - 2);
    }
    if ($body == "") {
        return 0.0;
    }
    def out as float init 0.0;
    try {
        $out = convert.toFloat($body);
    } catch (e) {
        return 0.0;
    }
    if ($out < 0.0 or $out > 4000.0) {
        return 0.0;
    }
    return $out;
}

/**
 * The weight word in an ODF border value.
 *
 * ODF writes a border as a width, a style and a colour in one attribute
 * (`0.5pt solid #000000`), so the weight has to come from the width.
 *
 * @param raw {string} the `fo:border` value
 * @return {string} a weight word the shared mapper understands
 */
func odsBorderWeight(raw as string) {
    def body as string init strings.trim($raw);
    if ($body == "" or $body == "none") {
        return "none";
    }
    def width as float init odsPoints(strings.split($body, " ")[0]);
    if ($width >= 1.5) {
        return "thick";
    }
    if ($width >= 0.9) {
        return "medium";
    }
    return "thin";
}

/**
 * The styles one `<table:table-row>` puts on the sheet.
 *
 * @param src {bytes} the content part
 * @param row {Node} the row element
 * @param rowIndex {int} the row's zero-based index
 * @param runLength {int} how many identical rows this element stands for
 * @param styles {map of string to Style} the document's cell styles by name
 * @param columnStyles {list of string} each column's default style name
 * @return {list of Styled} the styles the row places
 */
func readOdsRowStyles(
    src as bytes,
    row as Node,
    rowIndex as int,
    runLength as int,
    styles as map of string to Style,
    columnStyles as list of string) {
    def out as list of Styled init [];
    def colIndex as int init 0;
    def cellNode as Node init nextChild($src, $row.openEnd, $row.innerEnd);
    while (isNode($cellNode)) {
        def span as int init odsCellSpan($src, $cellNode);
        if ($span > 0) {
            def named as string init nodeAttr($src, $cellNode, "style-name");
            if ($named == "") {
                $named = columnDefaultStyle($columnStyles, $colIndex);
            }
            def st as Style init namedStyle($styles, $named);
            for (def one in styledBlock($st, $rowIndex, $colIndex, $runLength, $span)) {
                $out[] = $one;
            }
            $colIndex = $colIndex + $span;
        }
        $cellNode = nextChild($src, $cellNode.end, $row.innerEnd);
    }
    return $out;
}

/**
 * Each column's default cell style name, in column order.
 *
 * `<table:table-column table:default-cell-style-name="ce1"/>` says what a
 * cell in that column looks like when it names no style of its own, and
 * `table:number-columns-repeated` lets one element stand for many columns.
 * The list is bounded by the grid, because a file is free to repeat a column
 * sixteen thousand times and usually does.
 *
 * @param src {bytes} the content part
 * @param table {Node} the table element
 * @return {list of string} the names, `""` where a column declares none
 */
func readOdsColumnStyles(src as bytes, table as Node) {
    def out as list of string init [];
    def child as Node init nextChild($src, $table.openEnd, $table.innerEnd);
    while (isNode($child)) {
        def tag as string init localName($child.name);
        if ($tag == "table-row" or isRowContainer($tag)) {
            # The columns are declared before the rows, so there is nothing
            # more to find once the rows start.
            return $out;
        }
        if ($tag == "table-column" and len($out) <= MAX_COLUMN) {
            # Appended into this local rather than threaded through a helper
            # that takes and returns it: passing a growing list copies it
            # every time, and a document of 20 000 column elements took
            # 44.9 s that way against 4.5 s this way.
            def span as int init columnSpanOf($src, $child, len($out));
            def name as string init nodeAttr($src, $child, "default-cell-style-name");
            for (def i in 0..$span) {
                $out[] = $name;
            }
        }
        $child = nextChild($src, $child.end, $table.innerEnd);
    }
    return $out;
}

/**
 * How many columns one column element covers, clipped to the grid.
 *
 * `table:number-columns-repeated` lets one element stand for many, and every
 * file LibreOffice writes repeats the last column sixteen thousand times -
 * so the span is clipped rather than believed.
 *
 * @param src {bytes} the content part
 * @param column {Node} the column element
 * @param sofar {int} how many columns have been recorded already
 * @return {int} the span to record
 */
func columnSpanOf(src as bytes, column as Node, sofar as int) {
    def span as int init repeatCount($src, $column, "number-columns-repeated");
    def room as int init MAX_COLUMN + 1 - $sofar;
    if ($span > $room) {
        return $room;
    }
    return $span;
}

/**
 * The default cell style a column declares.
 *
 * @param columnStyles {list of string} each column's default style name
 * @param col {int} the zero-based column
 * @return {string} the name, `""` when the column declares none
 */
func columnDefaultStyle(columnStyles as list of string, col as int) {
    if ($col < 0 or $col >= len($columnStyles)) {
        return "";
    }
    return $columnStyles[$col];
}

/**
 * The style a name points at.
 *
 * @param styles {map of string to Style} the document's cell styles by name
 * @param name {string} the style name, `""` when the cell has none
 * @return {Style} the style, the default when the name is unknown
 */
func namedStyle(styles as map of string to Style, name as string) {
    if ($name == "" or not maps.has($styles, $name)) {
        return style();
    }
    return $styles[$name];
}

/**
 * One style spread across a block of cells.
 *
 * Capped the same way values are, and for the same reason: a repeated run
 * carrying a style is as cheap to write and as expensive to expand.
 *
 * @param st {Style} the style
 * @param rowIndex {int} the block's first row
 * @param colIndex {int} the block's first column
 * @param rowSpan {int} how many rows the block covers
 * @param colSpan {int} how many columns the block covers
 * @return {list of Styled} the placements
 */
func styledBlock(st as Style, rowIndex as int, colIndex as int, rowSpan as int, colSpan as int) {
    def out as list of Styled init [];
    if (isPlain($st)) {
        return $out;
    }
    def tall as int init $rowSpan;
    def wide as int init $colSpan;
    if ($tall * $wide > MAX_BLOCK_CELLS) {
        if ($wide > $tall) {
            $wide = MAX_BLOCK_CELLS // $tall;
        } else {
            $tall = MAX_BLOCK_CELLS // $wide;
        }
        if ($tall < 1) {
            $tall = 1;
        }
        if ($wide < 1) {
            $wide = 1;
        }
    }
    for (def r in 0..$tall) {
        for (def c in 0..$wide) {
            $out[] = Styled{at: Ref{row: $rowIndex + $r, col: $colIndex + $c}, style: $st};
        }
    }
    return $out;
}

/**
 * Find `<office:spreadsheet>` inside `<office:document-content>`.
 *
 * It sits under `<office:body>`, but a writer may nest it differently, so the
 * search is a bounded descent rather than a fixed path.
 *
 * @param src {bytes} the document
 * @param root {Node} the root element
 * @return {Node} the spreadsheet element, or a node pointing at nothing
 */
func findSpreadsheet(src as bytes, root as Node) {
    def child as Node init nextChild($src, $root.openEnd, $root.innerEnd);
    while (isNode($child)) {
        def name as string init localName($child.name);
        if ($name == "spreadsheet") {
            return $child;
        }
        if ($name == "body") {
            def inner as Node init childNamed($src, $child, "spreadsheet");
            if (isNode($inner)) {
                return $inner;
            }
        }
        $child = nextChild($src, $child.end, $root.innerEnd);
    }
    return missingNode();
}

/**
 * The first direct child of an element with a given local name.
 *
 * Streams rather than listing: the caller wants one element, and the parent
 * may have very many children.
 *
 * @param src {bytes} the document
 * @param parent {Node} the element to look inside
 * @param name {string} the local name to match
 * @return {Node} the child, or a node pointing at nothing
 */
func childNamed(src as bytes, parent as Node, name as string) {
    def child as Node init nextChild($src, $parent.openEnd, $parent.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == $name) {
            return $child;
        }
        $child = nextChild($src, $child.end, $parent.innerEnd);
    }
    return missingNode();
}

/**
 * Read one `<table:table>` into a sheet.
 *
 * @param src {bytes} the document
 * @param table {Node} the table element
 * @param index {int} the table's position, for a fallback name
 * @param styles {map of string to Style} the document's cell styles by name
 * @return {Sheet} the sheet
 */
func readOdsTable(src as bytes, table as Node, index as int, styles as map of string to Style) {
    def name as string init nodeAttr($src, $table, "name");
    if ($name == "") {
        $name = "Sheet" + convert.toString($index + 1);
    }
    def placed as list of Placed init [];
    def styled as list of Styled init [];
    def rowIndex as int init 0;
    # A column may declare the style its cells take when they name none of
    # their own, and that is how an application stores "format this whole
    # column" - the most ordinary way a person applies a format. Without
    # this, a format LibreOffice put on a column was lost.
    def columnStyles as list of string init readOdsColumnStyles($src, $table);
    def child as Node init nextChild($src, $table.openEnd, $table.innerEnd);
    while (isNode($child)) {
        def tag as string init localName($child.name);
        if ($tag == "table-row") {
            def runLength as int init repeatCount($src, $child, "number-rows-repeated");
            for (def p in readOdsRowCells($src, $child, $rowIndex, $runLength)) {
                $placed[] = $p;
            }
            for (def st in readOdsRowStyles(
                $src,
                $child,
                $rowIndex,
                $runLength,
                $styles,
                $columnStyles)) {
                $styled[] = $st;
            }
            $rowIndex = $rowIndex + $runLength;
            # Checked here as well as in sheetFrom so that a file built to
            # amplify stops being read at the cap rather than after it.
            checkSheetCells($name, len($placed));
        } elseif (isRowContainer($tag)) {
            # A grouped or repeated header block wraps its rows in another
            # element; its rows are the table's rows all the same.
            def group as GroupCells init readOdsGroupCells(
                $src,
                $child,
                $rowIndex,
                $styles,
                $columnStyles);
            for (def p in $group.cells) {
                $placed[] = $p;
            }
            for (def st in $group.styles) {
                $styled[] = $st;
            }
            $rowIndex = $group.nextRow;
        }
        $child = nextChild($src, $child.end, $table.innerEnd);
    }
    return styledSheetFrom($name, $placed, $styled);
}

/**
 * A row group's cells and the row index after it.
 *
 * @field cells {list of Placed} the cells the group's rows put on the sheet
 * @field styles {list of Styled} the styles its rows put on the sheet
 * @field nextRow {int} the index the next row would take
 */
def struct GroupCells {
    cells as list of Placed,
    styles as list of Styled,
    nextRow as int
};

/**
 * The cells inside a group or header block.
 *
 * @param src {bytes} the document
 * @param group {Node} the wrapping element
 * @param rowIndex {int} where its first row goes
 * @param styles {map of string to Style} the document's cell styles by name
 * @param columnStyles {list of string} each column's default style name
 * @return {GroupCells} the cells, the styles and the index after its last row
 */
func readOdsGroupCells(
    src as bytes,
    group as Node,
    rowIndex as int,
    styles as map of string to Style,
    columnStyles as list of string) {
    def out as list of Placed init [];
    def styled as list of Styled init [];
    def at as int init $rowIndex;
    def inner as Node init nextChild($src, $group.openEnd, $group.innerEnd);
    while (isNode($inner)) {
        if (localName($inner.name) == "table-row") {
            def runLength as int init repeatCount($src, $inner, "number-rows-repeated");
            for (def p in readOdsRowCells($src, $inner, $at, $runLength)) {
                $out[] = $p;
            }
            for (def st in readOdsRowStyles($src, $inner, $at, $runLength, $styles, $columnStyles)) {
                $styled[] = $st;
            }
            $at = $at + $runLength;
        }
        $inner = nextChild($src, $inner.end, $group.innerEnd);
    }
    return GroupCells{cells: $out, styles: $styled, nextRow: $at};
}

/**
 * Whether a tag wraps rows rather than being one.
 *
 * @param tag {string} the element's local name
 * @return {bool} whether its children are rows
 */
func isRowContainer(tag as string) {
    return $tag == "table-row-group" or $tag == "table-header-rows" or
        $tag == "table-rows";
}

/**
 * How many times a row or column repeats.
 *
 * @param src {bytes} the document
 * @param node {Node} the row or cell element
 * @param attribute {string} the repeat attribute's local name
 * @return {int} the count, at least 1 and at most `MAX_REPEAT`
 */
func repeatCount(src as bytes, node as Node, attribute as string) {
    def raw as string init nodeAttr($src, $node, $attribute);
    if ($raw == "") {
        return 1;
    }
    def count as int init 1;
    try {
        $count = convert.toInt(strings.trim($raw));
    } catch (e) {
        return 1;
    }
    if ($count < 1) {
        return 1;
    }
    if ($count > MAX_REPEAT) {
        return MAX_REPEAT;
    }
    return $count;
}

/**
 * The cells one `<table:table-row>` holds.
 *
 * Returns the row's own cells rather than taking the sheet, so that a sheet's
 * cell map is never deep-copied per row. See {@link Placed}.
 *
 * The cells are walked with the scanner over the row's own bytes rather than
 * decoded into a tree. Two reasons, and the second is the one that decided it:
 *
 * - attributes are read natively by `nodeAttr`, so peak memory follows the row
 *   rather than the sheet;
 * - `xml.children` returns only elements and `xml.text` concatenates all of
 *   an element's text at once, so a decoded `<text:p>a<text:span>B</text:span>b`
 *   cannot be put back in order - it reads as `abB`. Mixed content is the
 *   normal shape of a styled cell, so the tree is the wrong model here.
 *
 * @param src {bytes} the document
 * @param row {Node} the row element
 * @param rowIndex {int} the row's zero-based index
 * @param runLength {int} how many identical rows this element stands for
 * @return {list of Placed} the cells the row puts on the sheet
 */
func readOdsRowCells(src as bytes, row as Node, rowIndex as int, runLength as int) {
    def out as list of Placed init [];
    def colIndex as int init 0;
    def cellNode as Node init nextChild($src, $row.openEnd, $row.innerEnd);
    while (isNode($cellNode)) {
        def span as int init odsCellSpan($src, $cellNode);
        if ($span > 0) {
            def v as Value init odsCellValue($src, $cellNode);
            for (def p in placedBlock($v, $rowIndex, $colIndex, $runLength, $span)) {
                $out[] = $p;
            }
            $colIndex = $colIndex + $span;
        }
        $cellNode = nextChild($src, $cellNode.end, $row.innerEnd);
    }
    return $out;
}

/**
 * How many columns an element in a row occupies.
 *
 * Zero for anything that is not a cell, which is how the caller skips the
 * annotations and shapes a row may also carry.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the element
 * @return {int} the column span, or 0 when this is not a cell
 */
func odsCellSpan(src as bytes, cellNode as Node) {
    def tag as string init localName($cellNode.name);
    if ($tag != "table-cell" and $tag != "covered-table-cell") {
        return 0;
    }
    return repeatCount($src, $cellNode, "number-columns-repeated");
}

/**
 * One value spread across a block of cells.
 *
 * ODS run-length encodes both axes, so a single cell element can stand for a
 * rectangle: `number-columns-repeated` wide by `number-rows-repeated` tall.
 * Only a run carrying a value reaches here; an empty run is skipped by the
 * caller rather than materialised, which is what stops a file that pads to
 * column XFD from becoming millions of cells.
 *
 * @param v {Value} the value to spread
 * @param rowIndex {int} the block's first row
 * @param colIndex {int} the block's first column
 * @param rowSpan {int} how many rows the block covers
 * @param colSpan {int} how many columns the block covers
 * @return {list of Placed} the cells
 */
func placedBlock(v as Value, rowIndex as int, colIndex as int, rowSpan as int, colSpan as int) {
    def out as list of Placed init [];
    if (isEmpty($v)) {
        return $out;
    }
    def tall as int init $rowSpan;
    def wide as int init $colSpan;
    if ($tall * $wide > MAX_BLOCK_CELLS) {
        # Clamp the product, trimming the larger axis so that a short-and-wide
        # or tall-and-narrow run keeps its shape.
        if ($wide > $tall) {
            $wide = MAX_BLOCK_CELLS // $tall;
        } else {
            $tall = MAX_BLOCK_CELLS // $wide;
        }
        if ($tall < 1) {
            $tall = 1;
        }
        if ($wide < 1) {
            $wide = 1;
        }
    }
    for (def r in 0..$tall) {
        for (def c in 0..$wide) {
            $out[] = Placed{at: Ref{row: $rowIndex + $r, col: $colIndex + $c}, value: $v};
        }
    }
    return $out;
}

/**
 * The value one `<table:table-cell>` holds.
 *
 * ODS carries the type in `office:value-type` and the machine-readable value
 * in a type-specific attribute, with the displayed text in `<text:p>`
 * children. The attribute is authoritative: the text is a rendering, so
 * reading it instead would lose precision and depend on the writer's locale.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @return {Value} the value, `Empty` when the cell carries nothing
 */
func odsCellValue(src as bytes, cellNode as Node) {
    def formulaSource as string init nodeAttr($src, $cellNode, "formula");
    def valueType as string init nodeAttr($src, $cellNode, "value-type");
    def displayed as string init odsCellText($src, $cellNode);

    if ($formulaSource != "") {
        return Value.Formula{source: odsFormulaSource($formulaSource), cached: $displayed};
    }
    match ($valueType) {
        when "float", "percentage", "currency" { return odsNumber($src, $cellNode, $displayed); }
        when "boolean" { return odsBoolean($src, $cellNode, $displayed); }
        when "date" { return odsDate($src, $cellNode, $displayed); }
        when "time" { return odsTime($src, $cellNode, $displayed); }
        when "string" { return odsString($src, $cellNode, $displayed); }
        else { return odsUntyped($displayed); }
    }
}

/**
 * A numeric ODS cell.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @param displayed {string} the cell's rendered text, as a fallback
 * @return {Value} the value
 */
func odsNumber(src as bytes, cellNode as Node, displayed as string) {
    def raw as string init nodeAttr($src, $cellNode, "value");
    if ($raw == "") {
        return odsUntyped($displayed);
    }
    def amount as float init 0.0;
    try {
        $amount = convert.toFloat(strings.trim($raw));
    } catch (e) {
        return Value.Text{body: $displayed};
    }
    return Value.Number{amount: $amount};
}

/**
 * A boolean ODS cell.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @param displayed {string} the cell's rendered text, as a fallback
 * @return {Value} the value
 */
func odsBoolean(src as bytes, cellNode as Node, displayed as string) {
    def raw as string init nodeAttr($src, $cellNode, "boolean-value");
    if ($raw == "") {
        return odsUntyped($displayed);
    }
    return Value.Bool{flag: strings.lower(strings.trim($raw)) == "true"};
}

/**
 * A date ODS cell.
 *
 * A value carrying a time of day keeps it; a bare date does not, which is the
 * distinction `Stamp.dateOnly` exists for.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @param displayed {string} the cell's rendered text, as a fallback
 * @return {Value} the value
 */
func odsDate(src as bytes, cellNode as Node, displayed as string) {
    def raw as string init nodeAttr($src, $cellNode, "date-value");
    if ($raw == "") {
        return odsUntyped($displayed);
    }
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    try {
        $at = parseIsoDate($raw);
    } catch (e) {
        return Value.Text{body: $displayed};
    }
    return Value.Stamp{at: $at, dateOnly: not strings.contains($raw, "T")};
}

/**
 * A time-of-day ODS cell.
 *
 * ODS writes a duration (`PT14H30M00S`), not an instant. It is read as a
 * fraction of a day, which is how both formats treat a bare time: the
 * fractional part of a date serial.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @param displayed {string} the cell's rendered text, as a fallback
 * @return {Value} the value
 */
func odsTime(src as bytes, cellNode as Node, displayed as string) {
    def raw as string init nodeAttr($src, $cellNode, "time-value");
    if ($raw == "") {
        return odsUntyped($displayed);
    }
    def seconds as int init parseOdsDuration($raw);
    if ($seconds < 0) {
        return Value.Text{body: $displayed};
    }
    return Value.Number{amount: convert.toFloat($seconds) / 86400.0};
}

/**
 * Read an ODS duration such as `PT14H30M00S` into seconds.
 *
 * Only the time components are read: a duration carrying years, months or
 * days is not a time of day and is refused.
 *
 * @param raw {string} the duration
 * @return {int} the seconds, or `-1` when the text is not a time duration
 */
func parseOdsDuration(raw as string) {
    def body as string init strings.trim($raw);
    if (not strings.startsWith($body, "PT")) {
        return -1;
    }
    $body = strings.substring($body, 2, len($body));
    def seconds as int init 0;
    def digits as string init "";
    for (def ch in strings.chars($body)) {
        if (strings.indexOf("0123456789.", $ch) >= 0) {
            $digits = $digits + $ch;
            continue;
        }
        def amount as float init 0.0;
        try {
            $amount = convert.toFloat($digits);
        } catch (e) {
            return -1;
        }
        $digits = "";
        def step as int init durationStep($amount, $ch);
        if ($step < 0) {
            return -1;
        }
        $seconds = $seconds + $step;
    }
    return $seconds;
}

/**
 * How many seconds one component of a duration contributes.
 *
 * @param amount {float} the component's value
 * @param unit {string} the component's unit letter
 * @return {int} the seconds, or `-1` when the unit is not a time unit
 */
func durationStep(amount as float, unit as string) {
    match (strings.upper($unit)) {
        when "H" { return math.round($amount * 3600.0); }
        when "M" { return math.round($amount * 60.0); }
        when "S" { return math.round($amount); }
        else { return -1; }
    }
}

/**
 * A string ODS cell.
 *
 * The text usually sits in `<text:p>` children, but a writer may also put it
 * in `office:string-value`, which wins when it is there.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @param displayed {string} the cell's rendered text
 * @return {Value} the value
 */
func odsString(src as bytes, cellNode as Node, displayed as string) {
    def raw as string init nodeAttr($src, $cellNode, "string-value");
    if ($raw != "") {
        return Value.Text{body: $raw};
    }
    return Value.Text{body: $displayed};
}

/**
 * A cell with no usable type: text if it says anything, empty otherwise.
 *
 * An error cell arrives this way too. ODS has no error type; an application
 * writes the code as the displayed text and leaves the value type off, so a
 * leading `#` is the only signal there is. The cost is that a text cell whose
 * content genuinely looks like a code reads back as an error, which the
 * format gives no way to tell apart.
 *
 * @param displayed {string} the cell's rendered text
 * @return {Value} the value
 */
func odsUntyped(displayed as string) {
    if ($displayed == "") {
        return Value.Empty;
    }
    if (looksLikeErrorCode($displayed)) {
        return Value.Err{code: $displayed};
    }
    return Value.Text{body: $displayed};
}

/**
 * Whether a piece of text is a spreadsheet error code.
 *
 * @param body {string} the text
 * @return {bool} whether it reads as an error code
 */
func looksLikeErrorCode(body as string) {
    if (not strings.startsWith($body, "#")) {
        return false;
    }
    return strings.endsWith($body, "!") or strings.endsWith($body, "?") or
        $body == "#N/A";
}

/**
 * The displayed text of a cell: its `<text:p>` children, joined by newlines.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @return {string} the text
 */
func odsCellText(src as bytes, cellNode as Node) {
    def lines as list of string init [];
    def child as Node init nextChild($src, $cellNode.openEnd, $cellNode.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "p") {
            $lines[] = odsParagraphText($src, $child);
        }
        $child = nextChild($src, $child.end, $cellNode.innerEnd);
    }
    return strings.join($lines, "\n");
}

/**
 * The text of one `<text:p>`, in document order.
 *
 * A paragraph is mixed content: a styled fragment becomes a `<text:span>`
 * child, a run of spaces becomes `<text:s/>`, and a tab or a break has its own
 * element. The text between the children has to be interleaved with them, so
 * this walks the byte range and takes each piece as it comes.
 *
 * @param src {bytes} the document
 * @param paragraph {Node} the paragraph element
 * @return {string} the text
 */
func odsParagraphText(src as bytes, paragraph as Node) {
    def parts as list of string init [];
    def at as int init $paragraph.openEnd;
    def child as Node init nextChild($src, $at, $paragraph.innerEnd);
    while (isNode($child)) {
        $parts[] = xmlUnescape(byteText($src, $at, $child.start));
        $parts[] = odsInlineText($src, $child);
        $at = $child.end;
        $child = nextChild($src, $child.end, $paragraph.innerEnd);
    }
    $parts[] = xmlUnescape(byteText($src, $at, $paragraph.innerEnd));
    return strings.join($parts, "");
}

/**
 * The text one inline element inside a paragraph contributes.
 *
 * @param src {bytes} the document
 * @param element {Node} the inline element
 * @return {string} the text
 */
func odsInlineText(src as bytes, element as Node) {
    match (localName($element.name)) {
        when "s" { return repeatedSpaces($src, $element); }
        when "tab" { return "\t"; }
        when "line-break" { return "\n"; }
        else { return odsParagraphText($src, $element); }
    }
}

/**
 * The spaces a `<text:s/>` stands for.
 *
 * ODS collapses runs of spaces into one element carrying a count, because XML
 * character data would otherwise lose them.
 *
 * @param src {bytes} the document
 * @param element {Node} the `<text:s/>` element
 * @return {string} the spaces
 */
func repeatedSpaces(src as bytes, element as Node) {
    def raw as string init nodeAttr($src, $element, "c");
    if ($raw == "") {
        return " ";
    }
    def count as int init 1;
    try {
        $count = convert.toInt(strings.trim($raw));
    } catch (e) {
        return " ";
    }
    if ($count < 1) {
        return "";
    }
    if ($count > MAX_REPEAT) {
        $count = MAX_REPEAT;
    }
    return strings.repeat(" ", $count);
}

/**
 * Read an ODS formula attribute into the model's A1 dialect.
 *
 * ODS writes `of:=[.B3]*[.C2]`: a namespace prefix, an `=`, then the
 * expression in OpenFormula. The prefix and the `=` come off here and the
 * expression goes through `toA1Formula`, because the model stores every
 * formula in A1 regardless of the format it came from. Without that, an
 * ODS-to-XLSX conversion would hand Excel an expression it cannot read.
 *
 * @param raw {string} the formula attribute as written
 * @return {string} the expression in A1, with no prefix and no leading `=`
 * @example
 *   odsFormulaSource("of:=[.B3]*[.C2]");   # "B3*C2"
 */
export func odsFormulaSource(raw as string) {
    def body as string init strings.trim($raw);
    def colon as int init strings.indexOf($body, ":");
    def equals as int init strings.indexOf($body, "=");
    if ($colon >= 0 and ($equals < 0 or $colon < $equals)) {
        $body = strings.substring($body, $colon + 1, len($body));
    }
    if (strings.startsWith($body, "=")) {
        $body = strings.substring($body, 1, len($body));
    }
    return toA1Formula($body);
}
