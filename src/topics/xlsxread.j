# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# sheets - the Office Open XML (xlsx) reader.
# Spliced into sheets.j via include - not a standalone module.

/** Where the workbook part lives in every file Excel and LibreOffice write. */
def const XLSX_WORKBOOK as string init "xl/workbook.xml";

/** The relationship part naming the workbook's sheets and shared strings. */
def const XLSX_WORKBOOK_RELS as string init "xl/_rels/workbook.xml.rels";

/**
 * Read an XLSX container.
 *
 * Each worksheet is walked with the scanner rather than decoded into a tree,
 * so peak memory follows the row being read rather than the size of the
 * sheet. See `docs/internal/memory.md`.
 *
 * @param raw {bytes} the `.xlsx` file
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the container or the workbook part is unreadable
 * @example
 *   def wb as Workbook init readXlsx(fs.readBytes("sales.xlsx"));
 */
export func readXlsx(raw as bytes) {
    def parts as map of string to bytes init unzip($raw);
    if (not maps.has($parts, XLSX_WORKBOOK)) {
        fail("the container has no " + quoted(XLSX_WORKBOOK) +
            ", so it is not an XLSX workbook");
    }
    def workbookPart as bytes init $parts[XLSX_WORKBOOK];
    def targets as map of string to string init readRelationships($parts);
    def shared as SharedTable init packShared(readSharedStrings($parts, $targets));
    def cellStyles as list of Style init readXlsxStyles($parts, $targets);
    def dateStyles as map of string to bool init dateStyleFlags($cellStyles);

    def wb as Workbook init newWorkbook();
    $wb.date1904 = readDate1904($workbookPart);
    def sheets as list of Sheet init [];
    for (def entry in readSheetEntries($workbookPart)) {
        $sheets[] = readXlsxSheet(
            $parts,
            $targets,
            $entry,
            $shared,
            $cellStyles,
            $dateStyles,
            $wb.date1904);
    }
    if (len($sheets) == 0) {
        fail("the workbook lists no sheets");
    }
    $wb.sheets = $sheets;
    return $wb;
}

/**
 * One entry of the workbook's sheet list.
 *
 * @field name {string} the sheet name
 * @field relationId {string} the `r:id` naming the part that holds it
 */
def struct SheetEntry {
    name as string,
    relationId as string
};

/**
 * The sheets a workbook part lists, in order.
 *
 * Order matters and is the workbook's, not the archive's: the parts are named
 * `sheet1.xml`, `sheet2.xml` and so on, but nothing says those names run in
 * the order the tabs appear.
 *
 * @param workbookPart {bytes} the `xl/workbook.xml` member
 * @return {list of SheetEntry} the entries, in workbook order
 */
func readSheetEntries(workbookPart as bytes) {
    def out as list of SheetEntry init [];
    def root as Node init rootNode($workbookPart);
    if (not isNode($root)) {
        return $out;
    }
    def sheetsNode as Node init childNamed($workbookPart, $root, "sheets");
    if (not isNode($sheetsNode)) {
        return $out;
    }
    def child as Node init nextChild($workbookPart, $sheetsNode.openEnd, $sheetsNode.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "sheet") {
            $out[] = SheetEntry{
                name: nodeAttr($workbookPart, $child, "name"),
                relationId: nodeAttr($workbookPart, $child, "id")
            };
        }
        $child = nextChild($workbookPart, $child.end, $sheetsNode.innerEnd);
    }
    return $out;
}

/**
 * Whether the workbook counts dates from 1904.
 *
 * @param workbookPart {bytes} the `xl/workbook.xml` member
 * @return {bool} whether the 1904 date system is in use
 */
func readDate1904(workbookPart as bytes) {
    def root as Node init rootNode($workbookPart);
    if (not isNode($root)) {
        return false;
    }
    def pr as Node init childNamed($workbookPart, $root, "workbookPr");
    if (not isNode($pr)) {
        return false;
    }
    def raw as string init nodeAttr($workbookPart, $pr, "date1904");
    if ($raw == "") {
        $raw = nodeAttr($workbookPart, $pr, "dateCompatibility");
    }
    def word as string init strings.lower(strings.trim($raw));
    return $word == "1" or $word == "true";
}

/**
 * The relationship id to part path map, resolved against `xl/`.
 *
 * A worksheet is reached by its `r:id`, not by a fixed filename, so the
 * relationship part is what turns `rId2` into `xl/worksheets/sheet2.xml`.
 *
 * @param parts {map of string to bytes} the container's members
 * @return {map of string to string} relationship id to member path
 */
func readRelationships(parts as map of string to bytes) {
    def out as map of string to string init {};
    if (not maps.has($parts, XLSX_WORKBOOK_RELS)) {
        return $out;
    }
    def src as bytes init $parts[XLSX_WORKBOOK_RELS];
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        return $out;
    }
    def child as Node init nextChild($src, $root.openEnd, $root.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "Relationship") {
            def id as string init nodeAttr($src, $child, "Id");
            def target as string init nodeAttr($src, $child, "Target");
            if ($id != "" and $target != "") {
                $out[$id] = resolveXlPath($target);
            }
        }
        $child = nextChild($src, $child.end, $root.innerEnd);
    }
    return $out;
}

/**
 * Resolve a relationship target to a member path.
 *
 * Targets in the workbook's relationship part are relative to `xl/`, except
 * an absolute one, which is relative to the package root.
 *
 * @param target {string} the relationship target as written
 * @return {string} the member path
 */
func resolveXlPath(target as string) {
    if (strings.startsWith($target, "/")) {
        return $target[1..len($target)];
    }
    if (strings.startsWith($target, "xl/")) {
        return $target;
    }
    return "xl/" + $target;
}

/**
 * The shared string table, in index order.
 *
 * A string cell holds an index into this table rather than its own text,
 * which is how the format keeps a column of repeated labels small.
 *
 * @param parts {map of string to bytes} the container's members
 * @param targets {map of string to string} the relationship map
 * @return {list of string} the strings, in index order
 */
func readSharedStrings(parts as map of string to bytes, targets as map of string to string) {
    def out as list of string init [];
    def path as string init findPartBySuffix($parts, $targets, "sharedStrings.xml");
    if ($path == "") {
        return $out;
    }
    def src as bytes init $parts[$path];
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        return $out;
    }
    def namespaces as map of string to string init sheetPrefixes($src, $root, $root);
    if ($root.name == "sst" and $root.closed) {
        try {
            return sharedStringsInBatches($src, $root, $namespaces);
        } catch (e) {
            if ($e.kind != ERROR_KIND) {
                throw $e;
            }
            # A batch that does not decode: a `</si>` inside a comment or a
            # CDATA section split it, or the part is damaged. The scanner
            # reads the whole table instead.
        }
    }
    def child as Node init nextChild($src, $root.openEnd, $root.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "si") {
            $out[] = sharedEntryText($src, $child, $namespaces);
        }
        $child = nextChild($src, $child.end, $root.innerEnd);
    }
    return $out;
}

/** How many shared strings one native decode takes. */
def const SHARED_BATCH as int init 256;

/** The end of a shared string entry, for the batch boundaries. */
def const SI_CLOSE_PROBE as bytes init encoding.encode("utf-8", "</si>");

/**
 * The shared string table, decoded natively a batch of entries at a time.
 *
 * Finding each `<si>` with the scanner cost about 0.1 ms an entry, most of
 * the time it takes to open a large workbook. Here a native search finds
 * every 256th `</si>`, and each run of entries between two such ends is
 * decoded in one call, inside a bare `<sst>` that carries the part's
 * namespace bindings. Every byte between the root's tags is decoded once,
 * so an entry that closes itself (`<si/>`) or an `extLst` after the last one
 * lands in a batch like anything else.
 *
 * @param src {bytes} the shared strings part
 * @param root {Node} the unprefixed `<sst>` element
 * @param namespaces {map of string to string} the prefixes the part declares
 * @return {list of string} the strings, in index order
 * @throws {Error} kind "sheets" when a batch is not well-formed XML; kind
 *   "limit" past the decoder's caps
 */
func sharedStringsInBatches(src as bytes, root as Node, namespaces as map of string to string) {
    def out as list of string init [];
    def at as int init $root.openEnd;
    while ($at < $root.innerEnd) {
        def end as int init $at;
        def count as int init 0;
        while ($count < SHARED_BATCH) {
            def close as int init indexOfByte($src, SI_CLOSE_PROBE, $end, $root.innerEnd);
            if ($close < 0) {
                break;
            }
            $end = $close + len(SI_CLOSE_PROBE);
            $count = $count + 1;
        }
        if ($count == 0) {
            $end = $root.innerEnd;
        }
        def batch as xml.Value init xml.element("sst");
        try {
            $batch = xml.decodeWith(
                "<sst>" + byteText($src, $at, $end) + "</sst>",
                xml.DecodeOptions{namespaces: $namespaces});
        } catch (e) {
            if (isGeneric($e.kind)) {
                throw $e;
            }
            fail("the shared string table is not well-formed: " + $e.message);
        }
        for (def entry in xml.children($batch)) {
            if (localName(xml.tag($entry)) == "si") {
                $out[] = treeRunText($entry);
            }
        }
        $at = $end;
    }
    return $out;
}

/**
 * The text of one shared string entry, decoded natively.
 *
 * One native parse per entry instead of a scanner walk of its runs; an entry
 * that does not decode is read by the scanner, which takes what it can.
 *
 * @param src {bytes} the shared strings part
 * @param entry {Node} the `<si>` element
 * @param namespaces {map of string to string} the prefixes the part declares
 * @return {string} the text
 */
func sharedEntryText(src as bytes, entry as Node, namespaces as map of string to string) {
    def tree as xml.Value init xml.element("si");
    try {
        $tree = decodeLeaf($src, $entry, $namespaces);
    } catch (e) {
        if ($e.kind != ERROR_KIND) {
            throw $e;
        }
        return sharedStringText($src, $entry);
    }
    return treeRunText($tree);
}

/**
 * The text of one shared string entry.
 *
 * A plain entry is a single `<t>`. A styled one is split into `<r>` runs, each
 * with its own `<t>`, and the cell's text is all of them joined - so taking
 * only the first would truncate every partially-formatted label.
 *
 * @param src {bytes} the shared strings part
 * @param entry {Node} the `<si>` element
 * @return {string} the text
 */
func sharedStringText(src as bytes, entry as Node) {
    def parts as list of string init [];
    def child as Node init nextChild($src, $entry.openEnd, $entry.innerEnd);
    while (isNode($child)) {
        def tag as string init localName($child.name);
        if ($tag == "t") {
            $parts[] = xmlUnescape(byteText($src, $child.openEnd, $child.innerEnd));
        } elseif ($tag == "r") {
            def runText as Node init childNamed($src, $child, "t");
            if (isNode($runText)) {
                $parts[] = xmlUnescape(byteText($src, $runText.openEnd, $runText.innerEnd));
            }
        }
        $child = nextChild($src, $child.end, $entry.innerEnd);
    }
    return strings.join($parts, "");
}

/**
 * The style every `cellXfs` entry describes, in index order.
 *
 * The inverse of what the writer does: the four indexed tables are read, then
 * each `xf` is resolved through them into one `Style`. An entry the deck
 * cannot represent - a per-edge border, a gradient fill - comes back as the
 * nearest thing it can, which is the point of `borderFromName` and friends.
 *
 * @param parts {map of string to bytes} the container's members
 * @param targets {map of string to string} the relationship map
 * @return {list of Style} one style per `cellXfs` entry
 */
func readXlsxStyles(parts as map of string to bytes, targets as map of string to string) {
    def out as list of Style init [];
    def path as string init findPartBySuffix($parts, $targets, "styles.xml");
    if ($path == "") {
        return $out;
    }
    def src as bytes init $parts[$path];
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        return $out;
    }
    def codes as map of string to string init readNumberFormatCodes($src, $root);
    def fonts as list of Style init readXlsxFonts($src, $root);
    def fills as list of string init readXlsxFills($src, $root);
    def borders as list of BorderStyle init readXlsxBorders($src, $root);
    def cellXfs as Node init childNamed($src, $root, "cellXfs");
    if (not isNode($cellXfs)) {
        return $out;
    }
    def child as Node init nextChild($src, $cellXfs.openEnd, $cellXfs.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "xf") {
            $out[] = readXlsxXf($src, $child, $codes, $fonts, $fills, $borders);
        }
        $child = nextChild($src, $child.end, $cellXfs.innerEnd);
    }
    return $out;
}

/**
 * One `<xf>` resolved into a style.
 *
 * @param src {bytes} the styles part
 * @param xf {Node} the `xf` element
 * @param codes {map of string to string} format id to format code
 * @param fonts {list of Style} the font table
 * @param fills {list of string} the fill table
 * @param borders {list of BorderStyle} the border table
 * @return {Style} the style
 */
func readXlsxXf(
    src as bytes,
    xf as Node,
    codes as map of string to string,
    fonts as list of Style,
    fills as list of string,
    borders as list of BorderStyle) {
    def out as Style init style();
    def fontAt as int init indexAttr($src, $xf, "fontId");
    if ($fontAt >= 0 and $fontAt < len($fonts)) {
        $out = mergeFont($out, $fonts[$fontAt]);
    }
    def fillAt as int init indexAttr($src, $xf, "fillId");
    if ($fillAt > 1 and $fillAt < len($fills)) {
        $out.background = $fills[$fillAt];
    }
    def borderAt as int init indexAttr($src, $xf, "borderId");
    if ($borderAt > 0 and $borderAt < len($borders)) {
        $out.border = $borders[$borderAt];
    }
    def numFmtId as string init nodeAttr($src, $xf, "numFmtId");
    if (maps.has($codes, $numFmtId)) {
        $out.format = normalisedFormat($codes[$numFmtId]);
    } else {
        # The first fifty ids are implicit: the file says `numFmtId="14"` and
        # nothing else, so the code has to come from the built-in table. This
        # used to recognise only the date ids, and wrote `yyyy-mm-dd` for all
        # of them - so `h:mm AM/PM` arrived as a date, and every non-date
        # built-in such as `0%` arrived with no format at all.
        $out.format = normalisedFormat(builtinFormat(builtinIdOf($numFmtId)));
    }
    def alignment as Node init childNamed($src, $xf, "alignment");
    if (isNode($alignment)) {
        $out.align = alignFromName(nodeAttr($src, $alignment, "horizontal"));
        $out.valign = valignFromName(nodeAttr($src, $alignment, "vertical"));
        def wrap as string init nodeAttr($src, $alignment, "wrapText");
        $out.wrap = $wrap == "1" or strings.lower($wrap) == "true";
    }
    return $out;
}

/**
 * A style with another's font properties copied onto it.
 *
 * @param st {Style} the style to fill in
 * @param font {Style} the style holding the font half
 * @return {Style} a fresh style
 */
func mergeFont(st as Style, font as Style) {
    def out as Style init $st;
    $out.bold = $font.bold;
    $out.italic = $font.italic;
    $out.underline = $font.underline;
    $out.fontName = $font.fontName;
    $out.fontSize = $font.fontSize;
    $out.colour = $font.colour;
    return $out;
}

/**
 * An integer attribute, or `-1` when it is absent or unreadable.
 *
 * @param src {bytes} the styles part
 * @param node {Node} the element
 * @param name {string} the attribute
 * @return {int} the value, or `-1`
 */
func indexAttr(src as bytes, node as Node, name as string) {
    def raw as string init nodeAttr($src, $node, $name);
    if ($raw == "") {
        return -1;
    }
    def out as int init -1;
    try {
        $out = convert.toInt(strings.trim($raw));
    } catch (e) {
        return -1;
    }
    return $out;
}

/**
 * The `<fonts>` table, each entry as the font half of a style.
 *
 * @param src {bytes} the styles part
 * @param root {Node} the styles root
 * @return {list of Style} the fonts, in index order
 */
func readXlsxFonts(src as bytes, root as Node) {
    def out as list of Style init [];
    def fonts as Node init childNamed($src, $root, "fonts");
    if (not isNode($fonts)) {
        return $out;
    }
    def child as Node init nextChild($src, $fonts.openEnd, $fonts.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "font") {
            $out[] = readXlsxFont($src, $child);
        }
        $child = nextChild($src, $child.end, $fonts.innerEnd);
    }
    return $out;
}

/**
 * One `<font>` as the font half of a style.
 *
 * A `<b/>` with no attribute means bold; `<b val="0"/>` means not. Both
 * spellings occur, and LibreOffice writes the second for every font it emits.
 *
 * @param src {bytes} the styles part
 * @param font {Node} the `font` element
 * @return {Style} the style
 */
func readXlsxFont(src as bytes, font as Node) {
    def out as Style init style();
    def child as Node init nextChild($src, $font.openEnd, $font.innerEnd);
    while (isNode($child)) {
        def tag as string init localName($child.name);
        def val as string init nodeAttr($src, $child, "val");
        match ($tag) {
            when "b" { $out.bold = flagAttr($val, true); }
            when "i" { $out.italic = flagAttr($val, true); }
            when "u" {
                # `<u/>` and `<u val="single"/>` both mean underlined; only
                # `val="none"` means not. The value names the *kind* of
                # underline, so it is not a boolean flag like `b` and `i`.
                $out.underline = $val != "none";
            }
            when "sz" { $out.fontSize = sizeAttr($val); }
            when "name" { $out.fontName = $val; }
            when "color" { $out.colour = rgbAttr(nodeAttr($src, $child, "rgb")); }
            else {
            }
        }
        $child = nextChild($src, $child.end, $font.innerEnd);
    }
    return $out;
}

/**
 * Whether a `val` attribute means on.
 *
 * @param val {string} the attribute, `""` when absent
 * @param whenAbsent {bool} what an absent attribute means
 * @return {bool} whether the property is on
 */
func flagAttr(val as string, whenAbsent as bool) {
    if ($val == "") {
        return $whenAbsent;
    }
    def word as string init strings.lower(strings.trim($val));
    return $word == "1" or $word == "true";
}

/**
 * A font size attribute.
 *
 * @param val {string} the attribute
 * @return {float} the size, or `0.0` when unreadable
 */
func sizeAttr(val as string) {
    if ($val == "") {
        return 0.0;
    }
    def out as float init 0.0;
    try {
        $out = convert.toFloat(strings.trim($val));
    } catch (e) {
        return 0.0;
    }
    if ($out < 0.0 or $out > 4000.0) {
        return 0.0;
    }
    return $out;
}

/**
 * A colour attribute as six hexadecimal digits.
 *
 * OOXML writes `FFRRGGBB` with the alpha first, which this deck does not
 * carry, so the leading pair comes off.
 *
 * @param rgb {string} the attribute
 * @return {string} the colour, or `""` when unreadable
 */
func rgbAttr(rgb as string) {
    def body as string init strings.trim($rgb);
    if (len($body) == 8) {
        $body = $body[2..8];
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
 * The `<fills>` table, each entry as a colour.
 *
 * @param src {bytes} the styles part
 * @param root {Node} the styles root
 * @return {list of string} the fill colours, `""` where there is no solid fill
 */
func readXlsxFills(src as bytes, root as Node) {
    def out as list of string init [];
    def fills as Node init childNamed($src, $root, "fills");
    if (not isNode($fills)) {
        return $out;
    }
    def child as Node init nextChild($src, $fills.openEnd, $fills.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "fill") {
            $out[] = readXlsxFill($src, $child);
        }
        $child = nextChild($src, $child.end, $fills.innerEnd);
    }
    return $out;
}

/**
 * One `<fill>` as a colour.
 *
 * @param src {bytes} the styles part
 * @param fill {Node} the `fill` element
 * @return {string} the colour, or `""` when it is not a solid fill
 */
func readXlsxFill(src as bytes, fill as Node) {
    def pattern as Node init childNamed($src, $fill, "patternFill");
    if (not isNode($pattern)) {
        return "";
    }
    if (nodeAttr($src, $pattern, "patternType") != "solid") {
        return "";
    }
    def fg as Node init childNamed($src, $pattern, "fgColor");
    if (isNode($fg)) {
        return rgbAttr(nodeAttr($src, $fg, "rgb"));
    }
    return "";
}

/**
 * The `<borders>` table, each entry as a weight.
 *
 * The weight is taken from whichever edge says something, since this deck
 * carries one weight for all four.
 *
 * @param src {bytes} the styles part
 * @param root {Node} the styles root
 * @return {list of BorderStyle} the weights, in index order
 */
func readXlsxBorders(src as bytes, root as Node) {
    def out as list of BorderStyle init [];
    def borders as Node init childNamed($src, $root, "borders");
    if (not isNode($borders)) {
        return $out;
    }
    def child as Node init nextChild($src, $borders.openEnd, $borders.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "border") {
            $out[] = readXlsxBorder($src, $child);
        }
        $child = nextChild($src, $child.end, $borders.innerEnd);
    }
    return $out;
}

/**
 * One `<border>` as a weight.
 *
 * @param src {bytes} the styles part
 * @param border {Node} the `border` element
 * @return {BorderStyle} the weight
 */
func readXlsxBorder(src as bytes, border as Node) {
    def child as Node init nextChild($src, $border.openEnd, $border.innerEnd);
    while (isNode($child)) {
        def weight as BorderStyle init borderFromName(nodeAttr($src, $child, "style"));
        match ($weight) {
            when NoBorder {
            }
            else { return $weight; }
        }
        $child = nextChild($src, $child.end, $border.innerEnd);
    }
    return BorderStyle.NoBorder;
}

/**
 * The format code each number format id names.
 *
 * @param src {bytes} the styles part
 * @param root {Node} the styles root
 * @return {map of string to string} format id to format code
 */
func readNumberFormatCodes(src as bytes, root as Node) {
    def out as map of string to string init {};
    def numFmts as Node init childNamed($src, $root, "numFmts");
    if (not isNode($numFmts)) {
        return $out;
    }
    def child as Node init nextChild($src, $numFmts.openEnd, $numFmts.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "numFmt") {
            def id as string init nodeAttr($src, $child, "numFmtId");
            if ($id != "") {
                $out[$id] = nodeAttr($src, $child, "formatCode");
            }
        }
        $child = nextChild($src, $child.end, $numFmts.innerEnd);
    }
    return $out;
}

/**
 * A `numFmtId` attribute as a number.
 *
 * @param numFmtId {string} the id, as the attribute spells it
 * @return {int} the id, or `-1` when it is missing or unreadable
 */
func builtinIdOf(numFmtId as string) {
    def trimmed as string init strings.trim($numFmtId);
    if ($trimmed == "") {
        return -1;
    }
    def out as int init -1;
    try {
        $out = convert.toInt($trimmed);
    } catch (e) {
        return -1;
    }
    return $out;
}

/**
 * Which style indices mean "this number is a date".
 *
 * Derived from the styles rather than read separately, so there is one answer
 * to the question and the writer and reader cannot disagree about it.
 *
 * @param styles {list of Style} one style per `cellXfs` entry
 * @return {map of string to bool} style index (as text) to whether it is a date
 */
func dateStyleFlags(styles as list of Style) {
    def out as map of string to bool init {};
    for (def i in 0..len($styles)) {
        $out[convert.toString($i)] = isDateFormat($styles[$i]);
    }
    return $out;
}

/**
 * Which cell-format indices mean "this number is a date".
 *
 * XLSX stores a date as a plain number; the only thing that makes it a date is
 * the number format its style points at. So reading dates correctly means
 * resolving `c/@s` to a `cellXfs` entry, then its `numFmtId` to either a
 * built-in date format or a custom one whose code carries date tokens.
 *
 * @param parts {map of string to bytes} the container's members
 * @param targets {map of string to string} the relationship map
 * @return {map of string to bool} style index (as text) to whether it is a date
 */
func readDateStyles(parts as map of string to bytes, targets as map of string to string) {
    def out as map of string to bool init {};
    def path as string init findPartBySuffix($parts, $targets, "styles.xml");
    if ($path == "") {
        return $out;
    }
    def src as bytes init $parts[$path];
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        return $out;
    }
    def custom as map of string to bool init readCustomNumberFormats($src, $root);
    def cellXfs as Node init childNamed($src, $root, "cellXfs");
    if (not isNode($cellXfs)) {
        return $out;
    }
    def index as int init 0;
    def child as Node init nextChild($src, $cellXfs.openEnd, $cellXfs.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "xf") {
            def numFmtId as string init nodeAttr($src, $child, "numFmtId");
            $out[convert.toString($index)] = isDateFormatId($numFmtId, $custom);
            $index = $index + 1;
        }
        $child = nextChild($src, $child.end, $cellXfs.innerEnd);
    }
    return $out;
}

/**
 * Which custom number formats are date formats.
 *
 * A format id of 164 or more is the file's own, and only its code says what it
 * is, so the code is inspected for date tokens.
 *
 * @param src {bytes} the styles part
 * @param root {Node} the styles root element
 * @return {map of string to bool} format id (as text) to whether it is a date
 */
func readCustomNumberFormats(src as bytes, root as Node) {
    def out as map of string to bool init {};
    def numFmts as Node init childNamed($src, $root, "numFmts");
    if (not isNode($numFmts)) {
        return $out;
    }
    def child as Node init nextChild($src, $numFmts.openEnd, $numFmts.innerEnd);
    while (isNode($child)) {
        if (localName($child.name) == "numFmt") {
            def id as string init nodeAttr($src, $child, "numFmtId");
            def code as string init nodeAttr($src, $child, "formatCode");
            if ($id != "") {
                $out[$id] = looksLikeDateFormat($code);
            }
        }
        $child = nextChild($src, $child.end, $numFmts.innerEnd);
    }
    return $out;
}

/**
 * Whether a number format id denotes a date.
 *
 * @param numFmtId {string} the format id, as text
 * @param custom {map of string to bool} the file's own formats
 * @return {bool} whether a number in this format is a date
 */
func isDateFormatId(numFmtId as string, custom as map of string to bool) {
    if ($numFmtId == "") {
        return false;
    }
    if (maps.has($custom, $numFmtId)) {
        return $custom[$numFmtId];
    }
    def id as int init -1;
    try {
        $id = convert.toInt(strings.trim($numFmtId));
    } catch (e) {
        return false;
    }
    # The built-in date and time formats, fixed by the specification.
    if ($id >= 14 and $id <= 22) {
        return true;
    }
    return $id >= 45 and $id <= 47;
}

/**
 * Whether a number format code describes a date or a time.
 *
 * The date tokens are `y`, `d` and `h` plus the `m` that means month rather
 * than minute. A code is scanned outside its quoted literals, so a currency
 * format whose symbol happens to be a letter is not mistaken for a date.
 *
 * @param code {string} the format code
 * @return {bool} whether it is a date or time format
 */
func looksLikeDateFormat(code as string) {
    def inQuote as bool init false;
    def inBracket as bool init false;
    for (def ch in strings.chars($code)) {
        if ($ch == "\"") {
            $inQuote = not $inQuote;
        } elseif ($ch == "[") {
            $inBracket = true;
        } elseif ($ch == "]") {
            $inBracket = false;
        } elseif (not $inQuote and not $inBracket) {
            def lower as string init strings.lower($ch);
            if ($lower == "y" or $lower == "d" or $lower == "h" or $lower == "s" or
                $lower == "m") {
                return true;
            }
        }
    }
    return false;
}

/**
 * A member path whose name ends with a suffix, preferring the relationship map.
 *
 * The relationship part is the authority, but a file written by hand may omit
 * it, so a direct search of the member names is the fallback.
 *
 * @param parts {map of string to bytes} the container's members
 * @param targets {map of string to string} the relationship map
 * @param suffix {string} the part name to find, such as `"styles.xml"`
 * @return {string} the member path, or `""` when it is not there
 */
func findPartBySuffix(
    parts as map of string to bytes,
    targets as map of string to string,
    suffix as string) {
    for (def id in $targets) {
        def path as string init $targets[$id];
        if (strings.endsWith($path, $suffix) and maps.has($parts, $path)) {
            return $path;
        }
    }
    for (def path in $parts) {
        if (strings.endsWith($path, $suffix)) {
            return $path;
        }
    }
    return "";
}

/**
 * Read one worksheet into a sheet.
 *
 * @param parts {map of string to bytes} the container's members
 * @param targets {map of string to string} the relationship map
 * @param entry {SheetEntry} the workbook's entry for this sheet
 * @param shared {SharedTable} the shared string table
 * @param cellStyles {list of Style} one style per `cellXfs` entry
 * @param dateStyles {map of string to bool} which style indices mean a date
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {Sheet} the sheet
 * @throws {Error} kind "sheets" when the sheet's part is missing
 */
func readXlsxSheet(
    parts as map of string to bytes,
    targets as map of string to string,
    entry as SheetEntry,
    shared as SharedTable,
    cellStyles as list of Style,
    dateStyles as map of string to bool,
    date1904 as bool) {
    def name as string init $entry.name;
    if ($name == "") {
        $name = "Sheet";
    }
    def placed as list of Placed init [];
    def styled as list of StyledXf init [];
    def path as string init sheetPartPath($parts, $targets, $entry);
    if ($path == "") {
        # Damage, not bad data: a workbook naming a part that is not in the
        # container still has its other sheets, so this one comes back empty
        # rather than taking the file down with it.
        return sheetFrom($name, $placed);
    }
    def src as bytes init $parts[$path];
    def root as Node init rootNode($src);
    if (not isNode($root)) {
        return sheetFrom($name, $placed);
    }
    def sheetData as Node init childNamed($src, $root, "sheetData");
    if (not isNode($sheetData)) {
        return sheetFrom($name, $placed);
    }
    def namespaces as map of string to string init sheetPrefixes($src, $root, $sheetData);
    def look as XlsxLookups init XlsxLookups{
        shared: $shared,
        cellStyles: $cellStyles,
        dateStyles: $dateStyles,
        date1904: $date1904
    };
    def rowIndex as int init 0;
    def rowNode as Node init nextChild($src, $sheetData.openEnd, $sheetData.innerEnd);
    while (isNode($rowNode)) {
        if (localName($rowNode.name) == "row") {
            $rowIndex = xlsxRowIndex($src, $rowNode, $rowIndex);
            def cells as RowCells init readXlsxRow($src, $rowNode, $rowIndex, $namespaces, $look);
            for (def p in $cells.placed) {
                $placed[] = $p;
            }
            for (def one in $cells.styled) {
                $styled[] = $one;
            }
            $rowIndex = $rowIndex + 1;
        }
        $rowNode = nextChild($src, $rowNode.end, $sheetData.innerEnd);
    }
    def out as Sheet init xfSheetFrom($name, $placed, $styled, $cellStyles);
    $out.layout = readXlsxLayout($src, $root, $out.colCount);
    return $out;
}

/**
 * A worksheet's column widths and frozen panes.
 *
 * Widths are kept for the columns inside the sheet's extent: Excel often
 * gives one `<col>` to every column up to the grid's edge, and a width on a
 * column that holds nothing is not worth sixteen thousand entries. A width
 * or a split that does not read as a number is left out, like any other
 * layout hint a file gets wrong.
 *
 * @param src {bytes} the worksheet part
 * @param root {Node} the `<worksheet>` element
 * @param colCount {int} the sheet's width, in columns
 * @return {SheetLayout} the layout
 */
func readXlsxLayout(src as bytes, root as Node, colCount as int) {
    def out as SheetLayout init plainLayout();
    def cols as Node init childNamed($src, $root, "cols");
    if (isNode($cols)) {
        for (def col in childNodes($src, $cols.openEnd, $cols.innerEnd)) {
            if (localName($col.name) != "col") {
                continue;
            }
            def width as float init floatAttr($src, $col, "width");
            def first as int init indexAttr($src, $col, "min");
            def last as int init math.min(indexAttr($src, $col, "max"), $colCount);
            if ($width <= 0.0 or $width > MAX_COLUMN_WIDTH or $first < 1) {
                continue;
            }
            for (def c in ($first - 1)..math.max($last, $first - 1)) {
                $out.columnWidths[columnName($c)] = $width;
            }
        }
    }
    def views as Node init childNamed($src, $root, "sheetViews");
    if (not isNode($views)) {
        return $out;
    }
    def view as Node init childNamed($src, $views, "sheetView");
    if (not isNode($view)) {
        return $out;
    }
    def pane as Node init childNamed($src, $view, "pane");
    if (not isNode($pane)) {
        return $out;
    }
    def state as string init nodeAttr($src, $pane, "state");
    if ($state != "frozen" and $state != "frozenSplit") {
        # A plain split scrolls both halves; it is not a freeze.
        return $out;
    }
    $out.frozenColumns = clampedSplit(indexAttr($src, $pane, "xSplit"), MAX_COLUMN);
    $out.frozenRows = clampedSplit(indexAttr($src, $pane, "ySplit"), MAX_ROW);
    return $out;
}

/**
 * A frozen split as a count, or 0 when it is absent or off the grid.
 *
 * @param split {int} the split as read, `-1` when absent
 * @param most {int} the grid's last index on that axis
 * @return {int} the count
 */
func clampedSplit(split as int, most as int) {
    if ($split < 0 or $split > $most) {
        return 0;
    }
    return $split;
}

/**
 * A float attribute, or `-1.0` when it is absent or unreadable.
 *
 * @param src {bytes} the part
 * @param node {Node} the element
 * @param name {string} the attribute
 * @return {float} the value, or `-1.0`
 */
func floatAttr(src as bytes, node as Node, name as string) {
    def raw as string init strings.trim(nodeAttr($src, $node, $name));
    if ($raw == "") {
        return -1.0;
    }
    def out as float init -1.0;
    try {
        $out = convert.toFloat($raw);
    } catch (e) {
        return -1.0;
    }
    return $out;
}

/**
 * A styled cell, by the `cellXfs` entry it points at.
 *
 * The index rather than the style: a `Style` is a dozen fields, and carrying
 * one per styled cell until the sheet is built cost more memory than the
 * cells themselves.
 *
 * @field at {Ref} the cell
 * @field xf {int} its `cellXfs` index
 */
def struct StyledXf {
    at as Ref,
    xf as int
};

/**
 * Whether a `cellXfs` index styles a cell.
 *
 * @param cellStyles {list of Style} one style per `cellXfs` entry
 * @param xf {int} the index, `-1` when the cell had none
 * @return {bool} whether it names an entry other than the general format
 */
func isStyledXf(cellStyles as list of Style, xf as int) {
    return $xf > 0 and $xf < len($cellStyles) and not isPlain($cellStyles[$xf]);
}

/**
 * Build a sheet from placed cells and the `cellXfs` entries they point at.
 *
 * As {@link styledSheetFrom}, but each distinct entry is interned once and
 * the cells take its index.
 *
 * @param name {string} the sheet name
 * @param placed {list of Placed} the cells
 * @param styled {list of StyledXf} the styled cells
 * @param cellStyles {list of Style} one style per `cellXfs` entry
 * @return {Sheet} the sheet
 * @throws {Error} kind "sheets" when the name is unusable; kind "limit" when there are too many cells
 */
func xfSheetFrom(
    name as string,
    placed as list of Placed,
    styled as list of StyledXf,
    cellStyles as list of Style) {
    def out as Sheet init sheetFrom($name, $placed);
    if (len($styled) == 0) {
        return $out;
    }
    def table as list of Style init $out.styles;
    def indices as map of string to int init $out.cellStyles;
    def local as map of string to int init {};
    def rowCount as int init $out.rowCount;
    def colCount as int init $out.colCount;
    for (def one in $styled) {
        if (not onGrid($one.at)) {
            continue;
        }
        def key as string init convert.toString($one.xf);
        if (not maps.has($local, $key)) {
            def index as int init styleIndexIn($table, $cellStyles[$one.xf]);
            if ($index < 0) {
                $table[] = $cellStyles[$one.xf];
                $index = len($table) - 1;
            }
            $local[$key] = $index;
        }
        $indices[cellRef($one.at)] = $local[$key];
        $rowCount = math.max($rowCount, $one.at.row + 1);
        $colCount = math.max($colCount, $one.at.col + 1);
    }
    $out.styles = $table;
    $out.cellStyles = $indices;
    $out.rowCount = $rowCount;
    $out.colCount = $colCount;
    return $out;
}

/**
 * The namespace prefixes a worksheet declares around its rows.
 *
 * A damaged open tag gives no bindings rather than failing the sheet: a row
 * that then uses a prefix does not decode, and is read by the scanner.
 *
 * @param src {bytes} the worksheet part
 * @param root {Node} the `<worksheet>` element
 * @param sheetData {Node} the `<sheetData>` element
 * @return {map of string to string} prefix to namespace URI
 */
func sheetPrefixes(src as bytes, root as Node, sheetData as Node) {
    def out as map of string to string init {};
    try {
        $out = declaredPrefixes($src, [$root, $sheetData]);
    } catch (e) {
        if ($e.kind != ERROR_KIND) {
            throw $e;
        }
    }
    return $out;
}

/**
 * What a cell needs from outside its sheet to be read.
 *
 * @field shared {SharedTable} the shared string table
 * @field cellStyles {list of Style} one style per `cellXfs` entry
 * @field dateStyles {map of string to bool} which style indices mean a date
 * @field date1904 {bool} whether the workbook uses the 1904 date system
 */
def struct XlsxLookups {
    shared as SharedTable,
    cellStyles as list of Style,
    dateStyles as map of string to bool,
    date1904 as bool
};

/**
 * The cells and the styles one row puts on the sheet.
 *
 * @field placed {list of Placed} the cells that hold something
 * @field styled {list of StyledXf} the cells whose style is not the default
 */
def struct RowCells {
    placed as list of Placed,
    styled as list of StyledXf
};

/**
 * One `<row>`'s cells and styles.
 *
 * The row is decoded natively, once, and read off the tree, as the streaming
 * reader does: walking it with the scanner cost about 0.3 ms per cell, twice
 * over. A row that does not decode - a file cut short mid-row, a broken tag -
 * is walked with the scanner instead, which reads what it can.
 *
 * @param src {bytes} the worksheet part
 * @param rowNode {Node} the row element
 * @param rowIndex {int} the row's zero-based index
 * @param namespaces {map of string to string} the prefixes declared around the rows
 * @param look {XlsxLookups} the tables the cells refer to
 * @return {RowCells} the row's cells and styles
 */
func readXlsxRow(
    src as bytes,
    rowNode as Node,
    rowIndex as int,
    namespaces as map of string to string,
    look as XlsxLookups) {
    def tree as xml.Value init xml.element("row");
    try {
        $tree = decodeLeaf($src, $rowNode, $namespaces);
    } catch (e) {
        if ($e.kind != ERROR_KIND) {
            throw $e;
        }
        return RowCells{
            placed: readXlsxRowCells(
                $src,
                $rowNode,
                $rowIndex,
                $look.shared,
                $look.dateStyles,
                $look.date1904),
            styled: readXlsxRowStyles($src, $rowNode, $rowIndex, $look.cellStyles)
        };
    }
    def placed as list of Placed init [];
    def styled as list of StyledXf init [];
    def colIndex as int init 0;
    for (def cellNode in xml.children($tree)) {
        if (localName(xml.tag($cellNode)) != "c") {
            continue;
        }
        def at as Ref init Ref{row: $rowIndex, col: xlsxTreeColumn($cellNode, $colIndex)};
        $colIndex = $at.col + 1;
        def v as Value init xlsxTreeCellValue(
            $cellNode,
            $look.shared,
            $look.dateStyles,
            $look.date1904);
        if (not isEmpty($v)) {
            $placed[] = Placed{at: $at, value: $v};
        }
        def xf as int init treeIndexAttr($cellNode, "s");
        if (isStyledXf($look.cellStyles, $xf)) {
            $styled[] = StyledXf{at: $at, xf: $xf};
        }
    }
    return RowCells{placed: $placed, styled: $styled};
}

/**
 * The styles one `<row>` puts on the sheet.
 *
 * A cell's `s` attribute indexes `cellXfs`, and index 0 is the general format
 * which needs no entry.
 *
 * @param src {bytes} the worksheet part
 * @param rowNode {Node} the row element
 * @param rowIndex {int} the row's zero-based index
 * @param cellStyles {list of Style} one style per `cellXfs` entry
 * @return {list of StyledXf} the styled cells of the row
 */
func readXlsxRowStyles(
    src as bytes,
    rowNode as Node,
    rowIndex as int,
    cellStyles as list of Style) {
    def out as list of StyledXf init [];
    def colIndex as int init 0;
    def cellNode as Node init nextChild($src, $rowNode.openEnd, $rowNode.innerEnd);
    while (isNode($cellNode)) {
        if (localName($cellNode.name) == "c") {
            def at as Ref init xlsxCellRef($src, $cellNode, $rowIndex, $colIndex);
            $colIndex = $at.col + 1;
            def xf as int init indexAttr($src, $cellNode, "s");
            if (isStyledXf($cellStyles, $xf)) {
                $out[] = StyledXf{at: $at, xf: $xf};
            }
        }
        $cellNode = nextChild($src, $cellNode.end, $rowNode.innerEnd);
    }
    return $out;
}

/**
 * Which member holds a sheet's worksheet part.
 *
 * @param parts {map of string to bytes} the container's members
 * @param targets {map of string to string} the relationship map
 * @param entry {SheetEntry} the workbook's entry for this sheet
 * @return {string} the member path, or `""` when it cannot be found
 */
func sheetPartPath(
    parts as map of string to bytes,
    targets as map of string to string,
    entry as SheetEntry) {
    if (maps.has($targets, $entry.relationId)) {
        def path as string init $targets[$entry.relationId];
        if (maps.has($parts, $path)) {
            return $path;
        }
    }
    return "";
}

/**
 * Which row a `<row>` element describes.
 *
 * The `r` attribute is one-based and authoritative, because a sheet may skip
 * empty rows entirely. Without it, position is the best guess available.
 *
 * @param src {bytes} the worksheet part
 * @param rowNode {Node} the row element
 * @param fallback {int} the index position would give
 * @return {int} the zero-based row index
 */
func xlsxRowIndex(src as bytes, rowNode as Node, fallback as int) {
    def raw as string init nodeAttr($src, $rowNode, "r");
    if ($raw == "") {
        return $fallback;
    }
    def oneBased as int init 0;
    try {
        $oneBased = convert.toInt(strings.trim($raw));
    } catch (e) {
        return $fallback;
    }
    if ($oneBased < 1 or $oneBased - 1 > MAX_ROW) {
        # A file may claim any row number it likes. Past the grid it is not
        # describing a real cell, so position is the better guess than a row
        # index that would become the sheet's extent.
        return $fallback;
    }
    return $oneBased - 1;
}

/**
 * The cells one `<row>` holds.
 *
 * Returns the row's own cells rather than taking the sheet, so that a sheet's
 * cell map is never deep-copied per row. See {@link Placed}.
 *
 * @param src {bytes} the worksheet part
 * @param rowNode {Node} the row element
 * @param rowIndex {int} the row's zero-based index
 * @param shared {SharedTable} the shared string table
 * @param dateStyles {map of string to bool} which style indices mean a date
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {list of Placed} the cells the row puts on the sheet
 */
func readXlsxRowCells(
    src as bytes,
    rowNode as Node,
    rowIndex as int,
    shared as SharedTable,
    dateStyles as map of string to bool,
    date1904 as bool) {
    def out as list of Placed init [];
    def colIndex as int init 0;
    def cellNode as Node init nextChild($src, $rowNode.openEnd, $rowNode.innerEnd);
    while (isNode($cellNode)) {
        if (localName($cellNode.name) == "c") {
            def at as Ref init xlsxCellRef($src, $cellNode, $rowIndex, $colIndex);
            $colIndex = $at.col + 1;
            def v as Value init xlsxCellValue($src, $cellNode, $shared, $dateStyles, $date1904);
            if (not isEmpty($v)) {
                $out[] = Placed{at: $at, value: $v};
            }
        }
        $cellNode = nextChild($src, $cellNode.end, $rowNode.innerEnd);
    }
    return $out;
}

/**
 * Where a `<c>` element sits.
 *
 * The `r` attribute carries the full A1 reference and is authoritative,
 * because a row writes only its non-empty cells and so position alone would
 * close up every gap.
 *
 * @param src {bytes} the worksheet part
 * @param cellNode {Node} the cell element
 * @param rowIndex {int} the row the cell is in
 * @param fallbackCol {int} the column position would give
 * @return {Ref} the reference
 */
func xlsxCellRef(src as bytes, cellNode as Node, rowIndex as int, fallbackCol as int) {
    def raw as string init nodeAttr($src, $cellNode, "r");
    if ($raw != "") {
        def parsed as Ref init Ref{row: $rowIndex, col: $fallbackCol};
        def ok as bool init true;
        try {
            $parsed = parseRef($raw);
        } catch (e) {
            $ok = false;
        }
        if ($ok) {
            # The row is taken from the element, not the reference: a file with
            # a wrong r on the cell but a right one on the row still reads.
            return Ref{row: $rowIndex, col: $parsed.col};
        }
    }
    return Ref{row: $rowIndex, col: $fallbackCol};
}

/**
 * The value one `<c>` element holds.
 *
 * The `t` attribute names the kind, defaulting to a number. A number is a date
 * only if its style says so, which is why `dateStyles` has to be read first.
 *
 * @param src {bytes} the worksheet part
 * @param cellNode {Node} the cell element
 * @param shared {SharedTable} the shared string table
 * @param dateStyles {map of string to bool} which style indices mean a date
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {Value} the value, `Empty` when the cell carries nothing
 */
func xlsxCellValue(
    src as bytes,
    cellNode as Node,
    shared as SharedTable,
    dateStyles as map of string to bool,
    date1904 as bool) {
    def kind as string init nodeAttr($src, $cellNode, "t");
    if ($kind == "") {
        $kind = "n";
    }
    def rawValue as string init childNodeText($src, $cellNode, "v");
    def formulaNode as Node init childNamed($src, $cellNode, "f");

    if (isNode($formulaNode)) {
        def source as string init xmlUnescape(byteText(
            $src,
            $formulaNode.openEnd,
            $formulaNode.innerEnd));
        def cached as string init $rawValue;
        if ($kind == "s") {
            $cached = sharedString($shared, $rawValue);
        } elseif ($kind == "inlineStr") {
            $cached = inlineString($src, $cellNode);
        }
        return Value.Formula{source: $source, cached: $cached};
    }

    match ($kind) {
        when "s" { return xlsxSharedValue($shared, $rawValue); }
        when "inlineStr" { return xlsxInlineValue($src, $cellNode); }
        when "str" { return xlsxTextValue($rawValue); }
        when "b" { return xlsxBoolValue($rawValue); }
        when "e" { return xlsxErrorValue($rawValue); }
        when "d" { return xlsxIsoDateValue($rawValue); }
        else { return xlsxNumberValue($src, $cellNode, $rawValue, $dateStyles, $date1904); }
    }
}

/**
 * The text of a named child element, unescaped.
 *
 * @param src {bytes} the worksheet part
 * @param parent {Node} the element to look inside
 * @param name {string} the child's local name
 * @return {string} the text, or `""` when the child is absent
 */
func childNodeText(src as bytes, parent as Node, name as string) {
    def child as Node init childNamed($src, $parent, $name);
    if (not isNode($child)) {
        return "";
    }
    return xmlUnescape(byteText($src, $child.openEnd, $child.innerEnd));
}

/**
 * A shared string by index.
 *
 * @param shared {SharedTable} the shared string table
 * @param rawIndex {string} the index as written
 * @return {string} the string, or `""` when the index is out of range
 */
func sharedString(shared as SharedTable, rawIndex as string) {
    def index as int init -1;
    try {
        $index = convert.toInt(strings.trim($rawIndex));
    } catch (e) {
        return "";
    }
    def count as int init len($shared.index) // SHARED_ENTRY;
    if ($index < 0 or $index >= $count) {
        return "";
    }
    def at as int init $index * SHARED_ENTRY;
    def chunk as int init convert.toInt($shared.index[$at..$at + SHARED_FIELD]);
    def first as int init convert.toInt($shared.index[$at + SHARED_FIELD..$at + 2 * SHARED_FIELD]);
    def last as int init convert.toInt($shared.index[$at + 2 * SHARED_FIELD..$at + SHARED_ENTRY]);
    return $shared.chunks[$chunk][$first..$last];
}

/**
 * The shared string table, packed into strings.
 *
 * A row cursor held in a top-level variable is copied for every row. A string
 * copies in constant time, where a `bytes` value copies every byte (the
 * table's whole size per row) and a `list of string` costs time per element
 * (1.2 ms a row for 17,500 strings). So the strings are run together into
 * chunks of about `SHARED_CHUNK` characters, a few list elements for even a
 * large table, and `index` is ASCII: for each string, its chunk, start and end
 * as `SHARED_FIELD`-digit decimals. A chunk stays short, so slicing one is
 * cheap even with non-ASCII text.
 *
 * @field chunks {list of string} the strings, back to back, a chunk at a time
 * @field index {string} each string's chunk, start and end, in index order
 */
export def struct SharedTable {
    chunks as list of string,
    index as string
};

/**
 * About how many characters of shared strings one chunk holds; a longer
 * string gets a chunk of its own.
 */
def const SHARED_CHUNK as int init 65536;

/** The digits of one number in a `SharedTable` index. */
def const SHARED_FIELD as int init 10;

/** The characters of one string's entry in a `SharedTable` index. */
def const SHARED_ENTRY as int init 30;

/**
 * Pack a list of strings into a table.
 *
 * @param entries {list of string} the strings, in index order
 * @return {SharedTable} the table
 */
func packShared(entries as list of string) {
    def chunks as list of string init [];
    def chunk as list of string init [];
    def size as int init 0;
    def index as list of string init [];
    for (def one in $entries) {
        def n as int init len($one);
        if ($size > 0 and $size + $n > SHARED_CHUNK) {
            $chunks[] = strings.join($chunk, "");
            $chunk = [];
            $size = 0;
        }
        $index[] = sharedField(len($chunks)) + sharedField($size) + sharedField($size + $n);
        $chunk[] = $one;
        $size = $size + $n;
    }
    if (len($chunk) > 0) {
        $chunks[] = strings.join($chunk, "");
    }
    return SharedTable{chunks: $chunks, index: strings.join($index, "")};
}

/**
 * A number as `SHARED_FIELD` decimal digits, zero-padded.
 *
 * @param n {int} the number, not negative and below 10^10
 * @return {string} the digits
 */
func sharedField(n as int) {
    def digits as string init convert.toString($n);
    return strings.replicate("0", SHARED_FIELD - len($digits)) + $digits;
}

/**
 * A cell holding a shared string.
 *
 * @param shared {SharedTable} the shared string table
 * @param rawIndex {string} the index as written
 * @return {Value} the value
 */
func xlsxSharedValue(shared as SharedTable, rawIndex as string) {
    def body as string init sharedString($shared, $rawIndex);
    if ($body == "") {
        return Value.Empty;
    }
    return Value.Text{body: $body};
}

/**
 * The text of an inline-string cell.
 *
 * @param src {bytes} the worksheet part
 * @param cellNode {Node} the cell element
 * @return {string} the text
 */
func inlineString(src as bytes, cellNode as Node) {
    def isNode2 as Node init childNamed($src, $cellNode, "is");
    if (not isNode($isNode2)) {
        return "";
    }
    return sharedStringText($src, $isNode2);
}

/**
 * A cell holding its string inline rather than in the shared table.
 *
 * @param src {bytes} the worksheet part
 * @param cellNode {Node} the cell element
 * @return {Value} the value
 */
func xlsxInlineValue(src as bytes, cellNode as Node) {
    def body as string init inlineString($src, $cellNode);
    if ($body == "") {
        return Value.Empty;
    }
    return Value.Text{body: $body};
}

/**
 * A cell holding a plain string value.
 *
 * @param rawValue {string} the value as written
 * @return {Value} the value
 */
func xlsxTextValue(rawValue as string) {
    if ($rawValue == "") {
        return Value.Empty;
    }
    return Value.Text{body: $rawValue};
}

/**
 * A cell holding a boolean.
 *
 * @param rawValue {string} the value as written, `"1"` or `"0"`
 * @return {Value} the value
 */
func xlsxBoolValue(rawValue as string) {
    if ($rawValue == "") {
        return Value.Empty;
    }
    return Value.Bool{flag: strings.trim($rawValue) == "1"};
}

/**
 * A cell holding an error code.
 *
 * @param rawValue {string} the code as written
 * @return {Value} the value
 */
func xlsxErrorValue(rawValue as string) {
    if ($rawValue == "") {
        return Value.Empty;
    }
    return Value.Err{code: $rawValue};
}

/**
 * A cell holding an ISO 8601 date.
 *
 * The `d` type is rare but legal, and carries a real date rather than a
 * serial, so the workbook's date system does not come into it.
 *
 * @param rawValue {string} the date as written
 * @return {Value} the value
 */
func xlsxIsoDateValue(rawValue as string) {
    if ($rawValue == "") {
        return Value.Empty;
    }
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    try {
        $at = parseIsoDate($rawValue);
    } catch (e) {
        return Value.Text{body: $rawValue};
    }
    return Value.Stamp{at: $at, dateOnly: not strings.contains($rawValue, "T")};
}

/**
 * A cell holding a number, which may be a date in disguise.
 *
 * @param src {bytes} the worksheet part
 * @param cellNode {Node} the cell element
 * @param rawValue {string} the value as written
 * @param dateStyles {map of string to bool} which style indices mean a date
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {Value} the value
 */
func xlsxNumberValue(
    src as bytes,
    cellNode as Node,
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
    if (not isDateStyled($src, $cellNode, $dateStyles)) {
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
 * Whether a cell's style marks its number as a date.
 *
 * @param src {bytes} the worksheet part
 * @param cellNode {Node} the cell element
 * @param dateStyles {map of string to bool} which style indices mean a date
 * @return {bool} whether the number should be read as a date
 */
func isDateStyled(src as bytes, cellNode as Node, dateStyles as map of string to bool) {
    def styleIndex as string init nodeAttr($src, $cellNode, "s");
    if ($styleIndex == "") {
        return false;
    }
    def key as string init strings.trim($styleIndex);
    if (not maps.has($dateStyles, $key)) {
        return false;
    }
    return $dateStyles[$key];
}
