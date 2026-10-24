# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the Gnumeric reader and writer.
# Spliced into sheets.j via include - not a standalone module.

/** The Gnumeric namespace, as the files declare it. */
def const GNM_NS as string init "http://www.gnumeric.org/v10.dtd";

/**
 * The format version the written documents declare.
 *
 * Gnumeric refuses a document with no `<gnm:Version>`, and the value is the
 * application version that wrote it rather than a format revision. This is
 * the oldest one that carries everything this deck writes.
 */
def const GNM_VERSION as string init "<gnm:Version Epoch=\"1\" Major=\"12\" Minor=\"0\" Full=\"1.12.0\"/>";

/** The grid a declared sheet covers, which Gnumeric wants stated up front. */
def const GNM_COLS as string init "256";

/** The rows a declared sheet covers. */
def const GNM_ROWS as string init "65536";

/**
 * Gnumeric's value type codes.
 *
 * The format stores the type as a number on each cell. These five are the
 * ones a stored cell carries; the rest of the enumeration (ranges, arrays) is
 * internal to Gnumeric.
 */
def const GNM_EMPTY as string init "10";

/** A boolean value. */
def const GNM_BOOLEAN as string init "20";

/** A number. */
def const GNM_FLOAT as string init "40";

/** An error code. */
def const GNM_ERROR as string init "50";

/** A string. */
def const GNM_STRING as string init "60";

/**
 * Read a Gnumeric file.
 *
 * Gnumeric is a single gzipped XML document rather than a container, so there
 * is no archive to walk: unpack the gzip and the whole format is one tree.
 * An uncompressed file is accepted too, since `gnumeric --export` can write
 * one and a user may have gunzipped it by hand.
 *
 * @param raw {bytes} the `.gnumeric` file, gzipped or not
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the document is unreadable or holds no sheets
 * @example
 *   def wb as Workbook init readGnumeric(fs.readBytes("book.gnumeric"));
 */
export func readGnumeric(raw as bytes) {
    def src as bytes init gunzipIfNeeded($raw);
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        fail("the document has no root element, so it is not a Gnumeric workbook");
    }
    def sheetsNode as Node init childNamed($src, $root, "Sheets");
    if (not isNode($sheetsNode)) {
        fail("the document has no <gnm:Sheets>, so it is not a Gnumeric workbook");
    }
    def sheets as list of Sheet init [];
    def child as Node init nextChild($src, $sheetsNode.openEnd, $sheetsNode.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "Sheet") {
            $sheets[] = readGnumericSheet($src, $child, len($sheets));
        }
        $child = nextChild($src, $child.end, $sheetsNode.innerEnd);
    }
    if (len($sheets) == 0) {
        fail("the workbook has no sheets");
    }
    def wb as Workbook init newWorkbook();
    $wb.sheets = $sheets;
    return $wb;
}

/**
 * Unpack a gzip member, or pass plain bytes through.
 *
 * The two-byte gzip magic is the test, so an already-unpacked document costs
 * nothing and a packed one is not guessed at.
 *
 * @param raw {bytes} the file
 * @return {bytes} the XML document
 * @throws {Error} kind "sheets" when the gzip member is damaged
 */
func gunzipIfNeeded(raw as bytes) {
    if (len($raw) < 2 or $raw[0] != 0x1f or $raw[1] != 0x8b) {
        return $raw;
    }
    def out as bytes init $raw;
    try {
        $out = compress.unpack($raw, "gzip");
    } catch (e) {
        fail("the file is gzipped but the member is damaged: " + $e.message);
    }
    return $out;
}

/**
 * Read one `<gnm:Sheet>` into a sheet.
 *
 * @param src {bytes} the document
 * @param sheetNode {Node} the sheet element
 * @param index {int} the sheet's position, for a fallback name
 * @return {Sheet} the sheet
 */
func readGnumericSheet(src as bytes, sheetNode as Node, index as int) {
    def nameNode as Node init childNamed($src, $sheetNode, "Name");
    def name as string init "";
    if (isNode($nameNode)) {
        $name = nodeText($src, $nameNode);
    }
    if ($name == "") {
        $name = "Sheet" + convert.toString($index + 1);
    }
    def placed as list of Placed init [];
    def cellsNode as Node init childNamed($src, $sheetNode, "Cells");
    if (not isNode($cellsNode)) {
        return sheetFrom($name, $placed);
    }

    def child as Node init nextChild($src, $cellsNode.openEnd, $cellsNode.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "Cell") {
            def one as list of Placed init readGnumericCell($src, $child);
            for (def p in $one) {
                $placed[] = $p;
            }
        }
        $child = nextChild($src, $child.end, $cellsNode.innerEnd);
    }
    return styledSheetFrom($name, $placed, readGnumericStyles($src, $sheetNode, $placed));
}

/**
 * Where one `<gnm:Cell>` goes and what it holds.
 *
 * Gnumeric addresses a cell by zero-based row and column attributes rather
 * than an A1 reference, which makes it the one format here that needs no
 * reference parsing at all.
 *
 * Returns a list so that a cell the reader cannot place comes back as nothing
 * rather than needing a sentinel, and so the sheet is never threaded through
 * this call. See {@link Placed}.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @return {list of Placed} the cell, or an empty list when it cannot be placed
 */
func readGnumericCell(src as bytes, cellNode as Node) {
    def out as list of Placed init [];
    def row as int init gnumericIndex($src, $cellNode, "Row", MAX_ROW);
    def col as int init gnumericIndex($src, $cellNode, "Col", MAX_COLUMN);
    if ($row < 0 or $col < 0) {
        return $out;
    }
    def v as Value init gnumericCellValue($src, $cellNode);
    if (isEmpty($v)) {
        return $out;
    }
    $out[] = Placed{at: Ref{row: $row, col: $col}, value: $v};
    return $out;
}

/**
 * A zero-based index attribute.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @param name {string} the attribute's name, `"Row"` or `"Col"`
 * @param limit {int} the largest index that axis addresses
 * @return {int} the index, or `-1` when it is missing, unreadable or off the
 *   grid
 */
func gnumericIndex(src as bytes, cellNode as Node, name as string, limit as int) {
    def raw as string init nodeAttr($src, $cellNode, $name);
    if ($raw == "") {
        return -1;
    }
    def out as int init -1;
    try {
        $out = convert.toInt(strings.trim($raw));
    } catch (e) {
        return -1;
    }
    if ($out < 0 or $out > $limit) {
        return -1;
    }
    return $out;
}

/**
 * The value one `<gnm:Cell>` holds.
 *
 * The text is normally the element's own, but a cell with a formula wraps it
 * in a `<gnm:Content>` child, which is the one shape that would otherwise
 * read as empty.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @return {Value} the value
 */
func gnumericCellValue(src as bytes, cellNode as Node) {
    def valueType as string init nodeAttr($src, $cellNode, "ValueType");
    def body as string init gnumericCellText($src, $cellNode);
    if (strings.startsWith($body, "=")) {
        return Value.Formula{source: strings.substring($body, 1, len($body)), cached: ""};
    }
    match ($valueType) {
        when GNM_FLOAT { return gnumericNumber($body); }
        when GNM_BOOLEAN { return Value.Bool{flag: strings.lower(strings.trim($body)) == "true"}; }
        when GNM_ERROR { return Value.Err{code: $body}; }
        when GNM_STRING { return Value.Text{body: $body}; }
        when GNM_EMPTY { return Value.Empty; }
        else { return gnumericUntyped($body); }
    }
}

/**
 * The text of a cell, from wherever the format put it.
 *
 * @param src {bytes} the document
 * @param cellNode {Node} the cell element
 * @return {string} the text
 */
func gnumericCellText(src as bytes, cellNode as Node) {
    def contentNode as Node init childNamed($src, $cellNode, "Content");
    if (isNode($contentNode)) {
        return nodeText($src, $contentNode);
    }
    return nodeText($src, $cellNode);
}

/**
 * A numeric Gnumeric cell.
 *
 * @param body {string} the cell's text
 * @return {Value} the value
 */
func gnumericNumber(body as string) {
    def trimmed as string init strings.trim($body);
    if ($trimmed == "") {
        return Value.Empty;
    }
    def amount as float init 0.0;
    try {
        $amount = convert.toFloat($trimmed);
    } catch (e) {
        return Value.Text{body: $body};
    }
    return Value.Number{amount: $amount};
}

/**
 * A cell whose type code is missing or unrecognised.
 *
 * @param body {string} the cell's text
 * @return {Value} the value
 */
func gnumericUntyped(body as string) {
    if ($body == "") {
        return Value.Empty;
    }
    if (looksLikeErrorCode($body)) {
        return Value.Err{code: $body};
    }
    return Value.Text{body: $body};
}

/**
 * Write a workbook as a Gnumeric file.
 *
 * The document is gzipped, which is what Gnumeric writes and what every
 * reader expects.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the `.gnumeric` file
 * @throws {Error} kind "sheets" when the workbook has no sheets
 * @example
 *   fs.writeBytes("out.gnumeric", writeGnumeric($wb));
 */
export func writeGnumeric(wb as Workbook) {
    return compress.pack(writeGnumericXml($wb), "gzip");
}

/**
 * Write a workbook as an uncompressed Gnumeric document.
 *
 * Exposed because it is the readable half, and because the gzip wrapper is
 * incidental to the format rather than part of it.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the XML document
 * @throws {Error} kind "sheets" when the workbook has no sheets
 * @example
 *   def doc as bytes init writeGnumericXml($wb);
 */
export func writeGnumericXml(wb as Workbook) {
    if (len($wb.sheets) == 0) {
        fail("cannot write a workbook with no sheets");
    }
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<gnm:Workbook xmlns:gnm=\"" + GNM_NS + "\">";
    $parts[] = GNM_VERSION;
    # Gnumeric cross-checks this index against the sheets that follow and
    # refuses the file when they disagree ("inconsistent SheetNameIndex
    # element"). LibreOffice's importer does not mind, which is exactly why
    # this was missed until the reference implementation was asked.
    $parts[] = tagOpen("gnm:SheetNameIndex");
    for (def s in $wb.sheets) {
        $parts[] = tagTextWith(
            "gnm:SheetName",
            {"gnm:Cols": GNM_COLS, "gnm:Rows": GNM_ROWS},
            $s.name);
    }
    $parts[] = tagClose("gnm:SheetNameIndex");
    $parts[] = tagOpen("gnm:Sheets");
    for (def s in $wb.sheets) {
        $parts[] = gnumericSheetMarkup($s);
    }
    $parts[] = tagClose("gnm:Sheets");
    $parts[] = tagClose("gnm:Workbook");
    return partsBytes($parts);
}

/**
 * One sheet as a `<gnm:Sheet>`.
 *
 * @param s {Sheet} the sheet
 * @return {string} the sheet element
 */
func gnumericSheetMarkup(s as Sheet) {
    def parts as list of string init [];
    $parts[] = tagOpen("gnm:Sheet");
    $parts[] = tagText("gnm:Name", $s.name);
    $parts[] = tagText("gnm:MaxCol", convert.toString($s.colCount - 1));
    $parts[] = tagText("gnm:MaxRow", convert.toString($s.rowCount - 1));
    # Styles come before the cells, which is where `ssconvert` puts them.
    $parts[] = gnumericStylesMarkup($s);
    $parts[] = tagOpen("gnm:Cells");
    def lines as list of list of Value init rows($s);
    for (def r in 0..len($lines)) {
        def line as list of Value init $lines[$r];
        for (def c in 0..len($line)) {
            if (not isEmpty($line[$c])) {
                $parts[] = gnumericCellMarkup($r, $c, $line[$c]);
            }
        }
    }
    $parts[] = tagClose("gnm:Cells");
    $parts[] = tagClose("gnm:Sheet");
    return strings.join($parts, "");
}

/**
 * One cell as a `<gnm:Cell>`.
 *
 * @param row {int} the zero-based row index
 * @param col {int} the zero-based column index
 * @param v {Value} the value
 * @return {string} the cell element
 */
func gnumericCellMarkup(row as int, col as int, v as Value) {
    def attrs as map of string to string init {
        "Row": convert.toString($row),
        "Col": convert.toString($col)
    };
    # A formula cell carries no ValueType at all, and the distinction between
    # an absent attribute and an empty one matters: with `ValueType=""`
    # Gnumeric still parses the `=` content but LibreOffice reads the cell as
    # blank, and with `ValueType="40"` LibreOffice reads NaN. Omitted is what
    # Gnumeric itself writes, checked against `ssconvert` output.
    def typeCode as string init gnumericTypeCode($v);
    if ($typeCode != "") {
        $attrs["ValueType"] = $typeCode;
    }
    return tagTextWith("gnm:Cell", $attrs, gnumericCellBody($v));
}

/**
 * The type code a value is written with.
 *
 * A formula gets no code at all - `""` - because the attribute describes a
 * stored value and a formula has none until something evaluates it. See
 * {@link gnumericCellMarkup} for what the alternatives do.
 *
 * @param v {Value} the value
 * @return {string} the type code, or `""` when the cell should carry none
 */
func gnumericTypeCode(v as Value) {
    match ($v) {
        when Number(n) { return GNM_FLOAT; }
        when Bool(b) { return GNM_BOOLEAN; }
        when Err(err) { return GNM_ERROR; }
        when Stamp(st) { return GNM_FLOAT; }
        when Formula(f) { return ""; }
        when Text(t) { return GNM_STRING; }
        when Empty { return GNM_EMPTY; }
    }
}

/**
 * The text a cell is written with.
 *
 * A formula is written as its expression with a leading `=`, which is how
 * Gnumeric stores one and how this reader recognises it. Gnumeric's syntax is
 * A1 with comma separators, so the model's dialect needs no translation.
 *
 * @param v {Value} the value
 * @return {string} the cell's text
 */
func gnumericCellBody(v as Value) {
    match ($v) {
        when Formula(f) { return "=" + $f.source; }
        when Stamp(st) { return numberAttr(toSerial($st.at, false)); }
        else { return asString($v); }
    }
}

# --- styles -----------------------------------------------------------------
#
# Gnumeric keeps styles in a `<gnm:Styles>` block of rectangular regions,
# before `<gnm:Cells>` and not inside it: a region names a span of rows and
# columns and the style every cell in it carries. That is the opposite of the
# other two formats, where a cell points at a style, and it is why this codec
# carried no styles for so long.
#
# The encodings were read off files `ssconvert` itself wrote, not from a
# specification:
#
#   Fore="CCCC:0:0"        a colour is three 16-bit channels in hex, separated
#                          by colons and not zero-padded. An 8-bit channel is
#                          the value repeated, so `CC` becomes `CCCC` - which
#                          makes the conversion textual in both directions and
#                          needs no arithmetic at all.
#   Shade="1"              set when the cell has a background. `Back` is
#                          `FFFF:FFFF:FFFF` on every cell either way, so the
#                          shade is what says whether it means anything.
#   Format="0.0%"          the number format code, exactly as this deck holds
#                          it. Gnumeric is the only format here besides XLSX
#                          that stores a code rather than a component tree.
#   HAlign="GNM_HALIGN_CENTER"   and `GNM_VALIGN_*`, both fully spelled out.
#   <gnm:Font Unit="11" Bold="1" ...>Calibri</gnm:Font>
#                          the size is an attribute and the family is the
#                          element's text.
#   <gnm:Top Style="1"/>   a border weight: 1 thin, 2 medium, 5 thick,
#                          checked by writing each one through `ssconvert`.

/**
 * The border weight Gnumeric writes for a thin edge.
 */
def const GNM_BORDER_THIN as int init 1;

/**
 * The border weight Gnumeric writes for a medium edge.
 */
def const GNM_BORDER_MEDIUM as int init 2;

/**
 * The border weight Gnumeric writes for a thick edge.
 *
 * Not 3: the weights are an enumeration with dashed and dotted in between,
 * and 5 is what `ssconvert` writes for a thick edge.
 */
def const GNM_BORDER_THICK as int init 5;

/**
 * The style regions a sheet element declares.
 *
 * A region may cover the whole grid - `ssconvert` fills the unused part of a
 * sheet with one - so a region is only expanded when its style is worth
 * carrying, and then only over the cells the sheet actually has. Without
 * both of those a default region would ask for 17 billion entries.
 *
 * @param src {bytes} the document
 * @param sheetNode {Node} the sheet element
 * @param placed {list of Placed} the cells already read, for the extent
 * @return {list of Styled} one entry per styled cell
 */
func readGnumericStyles(src as bytes, sheetNode as Node, placed as list of Placed) {
    def out as list of Styled init [];
    def stylesNode as Node init childNamed($src, $sheetNode, "Styles");
    if (not isNode($stylesNode)) {
        return $out;
    }
    def bounds as Ref init placedExtent($placed);
    def child as Node init nextChild($src, $stylesNode.openEnd, $stylesNode.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "StyleRegion") {
            for (def one in readGnumericRegion($src, $child, $bounds, len($out))) {
                $out[] = $one;
            }
        }
        $child = nextChild($src, $child.end, $stylesNode.innerEnd);
    }
    return $out;
}

/**
 * The last row and column any cell occupies.
 *
 * @param placed {list of Placed} the cells
 * @return {Ref} the furthest corner, `{-1, -1}` when there are no cells
 */
func placedExtent(placed as list of Placed) {
    def row as int init -1;
    def col as int init -1;
    for (def i in 0..len($placed)) {
        if ($placed[$i].at.row > $row) {
            $row = $placed[$i].at.row;
        }
        if ($placed[$i].at.col > $col) {
            $col = $placed[$i].at.col;
        }
    }
    return Ref{row: $row, col: $col};
}

/**
 * One `<gnm:StyleRegion>` as the cells it styles.
 *
 * @param src {bytes} the document
 * @param regionNode {Node} the region element
 * @param bounds {Ref} the furthest cell the sheet has
 * @param sofar {int} how many styled cells the sheet has already taken
 * @return {list of Styled} the cells, empty when the region says nothing
 */
func readGnumericRegion(src as bytes, regionNode as Node, bounds as Ref, sofar as int) {
    def out as list of Styled init [];
    if ($bounds.row < 0 or $bounds.col < 0) {
        return $out;
    }
    def styleNode as Node init childNamed($src, $regionNode, "Style");
    if (not isNode($styleNode)) {
        return $out;
    }
    def style as Style init readGnumericStyle($src, $styleNode);
    if (isPlain($style)) {
        # The filler regions are always the default style, and they are the
        # ones that span the grid. Skipping them here is what keeps this
        # bounded in the ordinary case rather than only in the guarded one.
        return $out;
    }
    def box as Area init regionArea($src, $regionNode, $bounds);
    if ($box.to2.row < $box.from.row or $box.to2.col < $box.from.col) {
        return $out;
    }
    for (def r in $box.from.row..($box.to2.row + 1)) {
        for (def c in $box.from.col..($box.to2.col + 1)) {
            if ($sofar + len($out) >= MAX_SHEET_CELLS) {
                fail("the sheet styles more than " +
                    convert.toString(MAX_SHEET_CELLS) + " cells");
            }
            $out[] = Styled{at: Ref{row: $r, col: $c}, style: $style};
        }
    }
    return $out;
}

/**
 * A region's span, clipped to the cells the sheet has.
 *
 * @param src {bytes} the document
 * @param regionNode {Node} the region element
 * @param bounds {Ref} the furthest cell the sheet has
 * @return {Area} the span to walk
 */
func regionArea(src as bytes, regionNode as Node, bounds as Ref) {
    def fromRow as int init regionEdge($src, $regionNode, "startRow", 0);
    def fromCol as int init regionEdge($src, $regionNode, "startCol", 0);
    def toRow as int init regionEdge($src, $regionNode, "endRow", $bounds.row);
    def toCol as int init regionEdge($src, $regionNode, "endCol", $bounds.col);
    if ($toRow > $bounds.row) {
        $toRow = $bounds.row;
    }
    if ($toCol > $bounds.col) {
        $toCol = $bounds.col;
    }
    return Area{from: Ref{row: $fromRow, col: $fromCol}, to2: Ref{row: $toRow, col: $toCol}};
}

/**
 * One edge of a style region.
 *
 * @param src {bytes} the document
 * @param regionNode {Node} the region element
 * @param name {string} the attribute
 * @param fallback {int} what an absent or unreadable attribute means
 * @return {int} the index
 */
func regionEdge(src as bytes, regionNode as Node, name as string, fallback as int) {
    def raw as string init nodeAttr($src, $regionNode, $name);
    if (strings.trim($raw) == "") {
        return $fallback;
    }
    def out as int init 0;
    try {
        $out = convert.toInt(strings.trim($raw));
    } catch (e) {
        return $fallback;
    }
    if ($out < 0) {
        return $fallback;
    }
    return $out;
}

/**
 * One `<gnm:Style>` as this deck's style.
 *
 * @param src {bytes} the document
 * @param styleNode {Node} the style element
 * @return {Style} the style
 */
func readGnumericStyle(src as bytes, styleNode as Node) {
    def out as Style init style();
    def format as string init nodeAttr($src, $styleNode, "Format");
    if ($format != "" and $format != "General") {
        $out.format = normalisedFormat($format);
    }
    $out.colour = gnumericColour(nodeAttr($src, $styleNode, "Fore"), "000000");
    if (nodeAttr($src, $styleNode, "Shade") != "0") {
        # `Back` is white on every cell, so without the shade a plain cell
        # would come back with a white background it never had.
        $out.background = gnumericColour(nodeAttr($src, $styleNode, "Back"), "FFFFFF");
    }
    $out.align = gnumericAlign(nodeAttr($src, $styleNode, "HAlign"));
    $out.valign = gnumericVerticalAlign(nodeAttr($src, $styleNode, "VAlign"));
    $out.wrap = nodeAttr($src, $styleNode, "WrapText") == "1";
    $out.border = gnumericBorder($src, $styleNode);
    return readGnumericFont($src, $styleNode, $out);
}

/**
 * A style's font, from its `<gnm:Font>` child.
 *
 * @param src {bytes} the document
 * @param styleNode {Node} the style element
 * @param into {Style} the style to fill in
 * @return {Style} the style with the font applied
 */
func readGnumericFont(src as bytes, styleNode as Node, into as Style) {
    def out as Style init $into;
    def fontNode as Node init childNamed($src, $styleNode, "Font");
    if (not isNode($fontNode)) {
        return $out;
    }
    $out.bold = nodeAttr($src, $fontNode, "Bold") == "1";
    $out.italic = nodeAttr($src, $fontNode, "Italic") == "1";
    # Underline is a style rather than a flag - 1 single, 2 double - so
    # anything but 0 is underlined.
    def underline as string init nodeAttr($src, $fontNode, "Underline");
    $out.underline = $underline != "" and $underline != "0";
    def name as string init strings.trim(nodeText($src, $fontNode));
    if ($name != "" and $name != GNM_DEFAULT_FONT) {
        $out.fontName = $name;
    }
    def size as string init nodeAttr($src, $fontNode, "Unit");
    if ($size != "") {
        def points as float init 0.0;
        def ok as bool init true;
        try {
            $points = convert.toFloat($size);
        } catch (e) {
            $ok = false;
        }
        if ($ok and $points > 0.0 and $points != GNM_DEFAULT_SIZE) {
            $out.fontSize = $points;
        }
    }
    return $out;
}

/**
 * The font family Gnumeric writes when a cell has none of its own.
 *
 * Read back as "no font" rather than as a choice, or every cell in a file
 * that went through Gnumeric would arrive carrying it.
 */
def const GNM_DEFAULT_FONT as string init "Calibri";

/**
 * The font size Gnumeric writes when a cell has none of its own.
 */
def const GNM_DEFAULT_SIZE as float init 11.0;

/**
 * A `RRRR:GGGG:BBBB` colour as this deck's `RRGGBB`.
 *
 * Each channel is 16 bits in hex and is not zero-padded, so `CCCC:0:0` is
 * what `#CC0000` comes back as. An 8-bit channel is its value repeated, so
 * the high half of a padded channel is the byte and no arithmetic is needed.
 *
 * @param raw {string} the attribute
 * @param ignored {string} the value that means "no colour here"
 * @return {string} the colour as `RRGGBB`, or `""`
 */
func gnumericColour(raw as string, ignored as string) {
    def trimmed as string init strings.trim($raw);
    if ($trimmed == "") {
        return "";
    }
    def channels as list of string init strings.split($trimmed, ":");
    if (len($channels) != 3) {
        return "";
    }
    def out as list of string init [];
    for (def i in 0..3) {
        $out[] = highByteOf($channels[$i]);
    }
    def rgb as string init strings.join($out, "");
    if ($rgb == $ignored) {
        return "";
    }
    return $rgb;
}

/**
 * The high byte of a 16-bit hex channel, as two hex digits.
 *
 * @param channel {string} the channel, in hex and possibly short
 * @return {string} the byte, uppercase
 */
func highByteOf(channel as string) {
    def padded as string init strings.trim($channel);
    while (len($padded) < 4) {
        $padded = "0" + $padded;
    }
    return strings.upper(strings.substring($padded, 0, 2));
}

/**
 * This deck's colour as Gnumeric's three channels.
 *
 * @param rgb {string} the colour as `RRGGBB`
 * @return {string} the colour as `RRRR:GGGG:BBBB`
 */
func gnumericColourText(rgb as string) {
    if (len($rgb) != 6) {
        return "0:0:0";
    }
    def out as list of string init [];
    for (def i in 0..3) {
        def pair as string init strings.substring($rgb, $i * 2, $i * 2 + 2);
        $out[] = $pair + $pair;
    }
    return strings.join($out, ":");
}

/**
 * The alignment a `GNM_HALIGN_` name means.
 *
 * @param name {string} the attribute
 * @return {Align} the alignment
 */
func gnumericAlign(name as string) {
    match (strings.upper(strings.trim($name))) {
        when "GNM_HALIGN_LEFT" { return Align.Left; }
        when "GNM_HALIGN_CENTER" { return Align.Centre; }
        when "GNM_HALIGN_RIGHT" { return Align.Right; }
        else { return Align.General; }
    }
}

/**
 * The vertical alignment a `GNM_VALIGN_` name means.
 *
 * @param name {string} the attribute
 * @return {VAlign} the alignment
 */
func gnumericVerticalAlign(name as string) {
    match (strings.upper(strings.trim($name))) {
        when "GNM_VALIGN_TOP" { return VAlign.Top; }
        when "GNM_VALIGN_CENTER" { return VAlign.Middle; }
        else { return VAlign.Bottom; }
    }
}

/**
 * The border weight a style's `<gnm:StyleBorder>` describes.
 *
 * This deck carries one weight for the whole cell where Gnumeric carries one
 * per edge, so the first edge that has a weight is the answer.
 *
 * @param src {bytes} the document
 * @param styleNode {Node} the style element
 * @return {BorderStyle} the weight
 */
func gnumericBorder(src as bytes, styleNode as Node) {
    def borderNode as Node init childNamed($src, $styleNode, "StyleBorder");
    if (not isNode($borderNode)) {
        return BorderStyle.NoBorder;
    }
    def child as Node init nextChild($src, $borderNode.openEnd, $borderNode.innerEnd);
    while (isNode($child)) {
        def weight as BorderStyle init gnumericBorderWeight(nodeAttr($src, $child, "Style"));
        match ($weight) {
            when NoBorder {
            }
            else { return $weight; }
        }
        $child = nextChild($src, $child.end, $borderNode.innerEnd);
    }
    return BorderStyle.NoBorder;
}

/**
 * The weight one border edge declares.
 *
 * Gnumeric's weights are an enumeration with dashed and dotted styles among
 * them; this deck has three weights, so a dashed edge reads as the nearest.
 *
 * @param raw {string} the `Style` attribute
 * @return {BorderStyle} the weight
 */
func gnumericBorderWeight(raw as string) {
    def code as int init 0;
    try {
        $code = convert.toInt(strings.trim($raw));
    } catch (e) {
        return BorderStyle.NoBorder;
    }
    if ($code <= 0) {
        return BorderStyle.NoBorder;
    }
    if ($code >= GNM_BORDER_THICK) {
        return BorderStyle.Thick;
    }
    if ($code >= GNM_BORDER_MEDIUM) {
        return BorderStyle.Medium;
    }
    return BorderStyle.Thin;
}

/**
 * The weight Gnumeric writes for one of this deck's.
 *
 * @param weight {BorderStyle} the weight
 * @return {int} the code, 0 for no border
 */
func gnumericBorderCode(weight as BorderStyle) {
    match ($weight) {
        when Thin { return GNM_BORDER_THIN; }
        when Medium { return GNM_BORDER_MEDIUM; }
        when Thick { return GNM_BORDER_THICK; }
        else { return 0; }
    }
}

/**
 * A sheet's styles as a `<gnm:Styles>` block.
 *
 * A region is rectangular, so a run of cells is merged along both axes: the
 * columns of a row first, then a row into the region above it when the span
 * and the style both match. That is the shape `ssconvert` writes, and it is
 * what keeps the block proportional to the *styling* rather than to the
 * sheet - a format applied to a whole column is one region and not one per
 * row. Writing a region per row made the file eleven times the size of the
 * equivalent ODS and took twice as long to read back.
 *
 * Cells with the default style are left out: a region is an override, and
 * Gnumeric fills the rest itself.
 *
 * @param s {Sheet} the sheet
 * @return {string} the block, or `""` when nothing is styled
 */
func gnumericStylesMarkup(s as Sheet) {
    def parts as list of string init [];
    def open as list of StyleRun init [];
    for (def r in 0..$s.rowCount) {
        def here as list of StyleRun init gnumericRowRuns($s, $r);
        for (def one in closedRuns($open, $here, $r)) {
            $parts[] = $one;
        }
        $open = extendedRuns($open, $here, $r);
    }
    for (def one in $open) {
        $parts[] = gnumericRegionMarkup($one, $s.rowCount - 1);
    }
    if (len($parts) == 0) {
        return "";
    }
    return tagOpen("gnm:Styles") + strings.join($parts, "") +
        tagClose("gnm:Styles");
}

/**
 * A run of adjacent cells in one or more rows that share a style.
 *
 * @field fromRow {int} the first row it covers
 * @field fromCol {int} the first column
 * @field toCol {int} the last column
 * @field style {Style} what they all carry
 */
def struct StyleRun {
    fromRow as int,
    fromCol as int,
    toCol as int,
    style as Style
};

/**
 * One row's runs of adjacent cells sharing a style.
 *
 * @param s {Sheet} the sheet
 * @param row {int} the zero-based row
 * @return {list of StyleRun} the runs, left to right
 */
func gnumericRowRuns(s as Sheet, row as int) {
    def out as list of StyleRun init [];
    def runStart as int init -1;
    def runStyle as Style init style();
    for (def c in 0..($s.colCount + 1)) {
        def here as Style init style();
        def styled as bool init false;
        if ($c < $s.colCount) {
            $here = styleAtRef($s, Ref{row: $row, col: $c});
            $styled = not isPlain($here);
        }
        if ($runStart >= 0 and (not $styled or not sameStyle($here, $runStyle))) {
            $out[] = StyleRun{fromRow: $row, fromCol: $runStart, toCol: $c - 1, style: $runStyle};
            $runStart = -1;
        }
        if ($styled and $runStart < 0) {
            $runStart = $c;
            $runStyle = $here;
        }
    }
    return $out;
}

/**
 * The open runs this row does not continue, as finished regions.
 *
 * @param open {list of StyleRun} the runs carried down from the row above
 * @param here {list of StyleRun} this row's runs
 * @param row {int} the zero-based row
 * @return {list of string} the region elements for the runs that ended
 */
func closedRuns(open as list of StyleRun, here as list of StyleRun, row as int) {
    def out as list of string init [];
    for (def i in 0..len($open)) {
        if (not continuesRun($here, $open[$i])) {
            $out[] = gnumericRegionMarkup($open[$i], $row - 1);
        }
    }
    return $out;
}

/**
 * The runs still open after this row, the continued ones kept as they were.
 *
 * A continued run keeps its `fromRow`, which is what makes the region span
 * several rows when it is finally written.
 *
 * @param open {list of StyleRun} the runs carried down from the row above
 * @param here {list of StyleRun} this row's runs
 * @param row {int} the zero-based row
 * @return {list of StyleRun} the runs to carry into the next row
 */
func extendedRuns(open as list of StyleRun, here as list of StyleRun, row as int) {
    def out as list of StyleRun init [];
    for (def i in 0..len($here)) {
        def carried as int init openRunAt($open, $here[$i]);
        if ($carried >= 0) {
            $out[] = $open[$carried];
        } else {
            $out[] = $here[$i];
        }
    }
    return $out;
}

/**
 * Whether a row's runs continue an open one exactly.
 *
 * @param here {list of StyleRun} the row's runs
 * @param one {StyleRun} the open run
 * @return {bool} whether the row carries the same span and style
 */
func continuesRun(here as list of StyleRun, one as StyleRun) {
    return openRunAt($here, $one) >= 0;
}

/**
 * Where a matching run sits in a list, by span and style.
 *
 * @param runs {list of StyleRun} the runs to look in
 * @param one {StyleRun} the run to match
 * @return {int} the index, or `-1`
 */
func openRunAt(runs as list of StyleRun, one as StyleRun) {
    for (def i in 0..len($runs)) {
        if ($runs[$i].fromCol == $one.fromCol and
            $runs[$i].toCol == $one.toCol and
            sameStyle($runs[$i].style, $one.style)) {
            return $i;
        }
    }
    return -1;
}

/**
 * Whether two styles are the same in every field this codec writes.
 *
 * @param a {Style} one style
 * @param b {Style} the other
 * @return {bool} whether a run may continue across them
 */
func sameStyle(a as Style, b as Style) {
    if ($a.bold != $b.bold or $a.italic != $b.italic or
        $a.underline != $b.underline or $a.wrap != $b.wrap) {
        return false;
    }
    if ($a.fontName != $b.fontName or $a.fontSize != $b.fontSize) {
        return false;
    }
    if ($a.colour != $b.colour or $a.background != $b.background or
        $a.format != $b.format) {
        return false;
    }
    return alignToOoxml($a.align) == alignToOoxml($b.align) and
        valignToOoxml($a.valign) == valignToOoxml($b.valign) and
        gnumericBorderCode($a.border) == gnumericBorderCode($b.border);
}

/**
 * One `<gnm:StyleRegion>` over a run of cells.
 *
 * @param one {StyleRun} the run
 * @param toRow {int} the last row it covers
 * @return {string} the region element
 */
func gnumericRegionMarkup(one as StyleRun, toRow as int) {
    def attrs as map of string to string init {
        "startCol": convert.toString($one.fromCol),
        "startRow": convert.toString($one.fromRow),
        "endCol": convert.toString($one.toCol),
        "endRow": convert.toString($toRow)
    };
    return tagOpenWith("gnm:StyleRegion", $attrs) +
        gnumericStyleMarkup($one.style) + tagClose("gnm:StyleRegion");
}

/**
 * One `<gnm:Style>` element.
 *
 * Every attribute is written, including the ones carrying a default: this is
 * what `ssconvert` does, and a style element that states its defaults cannot
 * be misread by an application that assumes different ones.
 *
 * @param st {Style} the style
 * @return {string} the style element and its children
 */
func gnumericStyleMarkup(st as Style) {
    def shade as string init "0";
    def back as string init "FFFF:FFFF:FFFF";
    if ($st.background != "") {
        $shade = "1";
        $back = gnumericColourText($st.background);
    }
    def attrs as map of string to string init {
        "HAlign": gnumericAlignName($st.align),
        "VAlign": gnumericVerticalAlignName($st.valign),
        "WrapText": boolDigit($st.wrap),
        "ShrinkToFit": "0",
        "Rotation": "0",
        "Shade": $shade,
        "Indent": "0",
        "Locked": "1",
        "Hidden": "0",
        "Fore": gnumericColourText(defaultedColour($st.colour, "000000")),
        "Back": $back,
        "PatternColor": "0:0:0",
        "Format": defaultedFormat($st.format)
    };
    return tagOpenWith("gnm:Style", $attrs) + gnumericFontMarkup($st) +
        gnumericBorderMarkup($st.border) + tagClose("gnm:Style");
}

/**
 * A colour, or the default when the style names none.
 *
 * @param rgb {string} the style's colour
 * @param fallback {string} what to write instead of nothing
 * @return {string} the colour to write
 */
func defaultedColour(rgb as string, fallback as string) {
    if ($rgb == "") {
        return $fallback;
    }
    return $rgb;
}

/**
 * A format code, or `General` when the style names none.
 *
 * @param code {string} the style's format code
 * @return {string} the code to write
 */
func defaultedFormat(code as string) {
    if (strings.trim($code) == "") {
        return "General";
    }
    return $code;
}

/**
 * A style's `<gnm:Font>` element.
 *
 * @param st {Style} the style
 * @return {string} the font element
 */
func gnumericFontMarkup(st as Style) {
    def size as float init $st.fontSize;
    if ($size <= 0.0) {
        $size = GNM_DEFAULT_SIZE;
    }
    def name as string init $st.fontName;
    if ($name == "") {
        $name = GNM_DEFAULT_FONT;
    }
    def attrs as map of string to string init {
        "Unit": numberAttr($size),
        "Bold": boolDigit($st.bold),
        "Italic": boolDigit($st.italic),
        "Underline": boolDigit($st.underline),
        "StrikeThrough": "0",
        "Script": "0"
    };
    return tagTextWith("gnm:Font", $attrs, $name);
}

/**
 * A style's `<gnm:StyleBorder>` element, if it has a border.
 *
 * This deck carries one weight for the cell, so all four edges get it.
 *
 * @param weight {BorderStyle} the border weight
 * @return {string} the border element, or `""` for no border
 */
func gnumericBorderMarkup(weight as BorderStyle) {
    def code as int init gnumericBorderCode($weight);
    if ($code == 0) {
        return "";
    }
    def attrs as map of string to string init {"Style": convert.toString($code), "Color": "0:0:0"};
    def parts as list of string init [];
    $parts[] = tagOpen("gnm:StyleBorder");
    for (def edge in ["gnm:Top", "gnm:Bottom", "gnm:Left", "gnm:Right"]) {
        $parts[] = tagEmpty($edge, $attrs);
    }
    $parts[] = tagClose("gnm:StyleBorder");
    return strings.join($parts, "");
}

/**
 * The `GNM_HALIGN_` name for an alignment.
 *
 * @param how {Align} the alignment
 * @return {string} the name
 */
func gnumericAlignName(how as Align) {
    match ($how) {
        when Left { return "GNM_HALIGN_LEFT"; }
        when Centre { return "GNM_HALIGN_CENTER"; }
        when Right { return "GNM_HALIGN_RIGHT"; }
        else { return "GNM_HALIGN_GENERAL"; }
    }
}

/**
 * The `GNM_VALIGN_` name for a vertical alignment.
 *
 * @param how {VAlign} the alignment
 * @return {string} the name
 */
func gnumericVerticalAlignName(how as VAlign) {
    match ($how) {
        when Top { return "GNM_VALIGN_TOP"; }
        when Middle { return "GNM_VALIGN_CENTER"; }
        else { return "GNM_VALIGN_BOTTOM"; }
    }
}
