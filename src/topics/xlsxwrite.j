# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the Office Open XML (xlsx) writer.
# Spliced into sheets.j via include - not a standalone module.

/** The main namespace every spreadsheet part sits in. */
def const XLSX_NS as string init "http://schemas.openxmlformats.org/spreadsheetml/2006/main";

/** The relationships namespace, used for the `r:id` attributes. */
def const XLSX_REL_NS as string init "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

/** The namespace of a `.rels` part's own elements. */
def const XLSX_PKG_REL_NS as string init "http://schemas.openxmlformats.org/package/2006/relationships";

/**
 * The first number format id a file may define for itself.
 *
 * Everything below 164 is built in to the format, so a file's own codes start
 * here.
 */
def const XLSX_FIRST_NUMFMT as int init 164;

/** The style index a plain cell uses. */
def const XF_GENERAL as string init "0";

/** The style index a date cell uses: built-in number format 14. */
def const XF_DATE as string init "1";

/** The style index a date-and-time cell uses: built-in number format 22. */
def const XF_DATETIME as string init "2";

/**
 * Write a workbook as an XLSX container.
 *
 * Text goes into the shared string table rather than being repeated in the
 * sheet, which is what the format is built around: a column of repeated
 * labels costs one entry instead of one per row.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the `.xlsx` file
 * @throws {Error} kind "sheets" when the workbook has no sheets
 * @example
 *   fs.writeBytes("out.xlsx", writeXlsx($wb));
 */
export func writeXlsx(wb as Workbook) {
    if (len($wb.sheets) == 0) {
        fail("cannot write a workbook with no sheets");
    }
    def shared as SharedStrings init collectSharedStrings($wb);
    # One style table for the whole workbook, because OOXML has one: `c/@s`
    # indexes `cellXfs`, which is a package-level part. Each sheet's own table
    # is mapped into it here.
    def formats as XlsxFormats init collectXlsxFormats($wb);
    def members as list of Member init [];
    $members[] = member("[Content_Types].xml", xlsxContentTypes($wb));
    $members[] = member("_rels/.rels", xlsxRootRels());
    $members[] = member(XLSX_WORKBOOK, xlsxWorkbookPart($wb));
    $members[] = member(XLSX_WORKBOOK_RELS, xlsxWorkbookRels($wb));
    $members[] = member("xl/styles.xml", xlsxStyles($formats));
    $members[] = member("xl/sharedStrings.xml", xlsxSharedStringsPart($shared));
    for (def i in 0..len($wb.sheets)) {
        $members[] = member(
            sheetPartName($i),
            xlsxWorksheet($wb.sheets[$i], $i, $shared, $formats, $wb.date1904));
    }
    return zip($members);
}

/**
 * The shared string table being built, with the index of each string.
 *
 * @field texts {list of string} the strings, in index order
 * @field index {map of string to int} where each string sits
 */
def struct SharedStrings {
    texts as list of string,
    index as map of string to int
};

/**
 * Collect every text a workbook holds into one shared string table.
 *
 * Done in a pass before any sheet is written, because a cell has to name its
 * string by index and the index is only known once the table is complete.
 *
 * Built in one local loop rather than by threading the table through a
 * per-cell call: a `SharedStrings` is a value, so handing it down would copy
 * its list and its map on every cell.
 *
 * @param wb {Workbook} the workbook
 * @return {SharedStrings} the table
 */
func collectSharedStrings(wb as Workbook) {
    def texts as list of string init [];
    def index as map of string to int init {};
    for (def s in $wb.sheets) {
        for (def body in sharedStringsOf($s)) {
            if (not maps.has($index, $body)) {
                $texts[] = $body;
                $index[$body] = len($texts) - 1;
            }
        }
    }
    return SharedStrings{texts: $texts, index: $index};
}

/**
 * The texts one sheet contributes to the shared table.
 *
 * @param s {Sheet} the sheet
 * @return {list of string} the non-empty texts, in row-major order
 */
func sharedStringsOf(s as Sheet) {
    def out as list of string init [];
    for (def line in rows($s)) {
        for (def v in $line) {
            def body as string init sharedStringBody($v);
            if ($body != "") {
                $out[] = $body;
            }
        }
    }
    return $out;
}

/**
 * The text a value contributes to the shared table, if any.
 *
 * Only a plain text cell uses the shared table. A formula's cached string
 * result is written inline, because it belongs to the formula rather than
 * being data in its own right.
 *
 * @param v {Value} the value
 * @return {string} the text, or `""` when the value does not use the table
 */
func sharedStringBody(v as Value) {
    match ($v) {
        when Text(t) { return $t.body; }
        else { return ""; }
    }
}

/**
 * The workbook's cell formats, flattened into one table.
 *
 * OOXML has one style table for the package, so the sheets' separate tables
 * are merged. The first three entries are fixed and reserved:
 *
 *   0  the general format, which an unstyled cell points at
 *   1  a date, so a date cell displays as a date
 *   2  a date and time
 *
 * `indexOf` then maps a sheet and its local style index to the entry's place
 * in the merged table, which is what the worksheet writer needs per cell.
 *
 * @field styles {list of Style} the distinct styles, after the reserved three
 * @field indexOf {map of string to int} sheet and local index to `cellXfs` index
 */
def struct XlsxFormats {
    styles as list of Style,
    indexOf as map of string to int
};

/**
 * How many `cellXfs` entries come before the workbook's own styles.
 *
 * General, date, date-and-time. The date formats are written whether or not
 * any cell uses them, because a date cell with no style of its own still has
 * to point at one.
 */
def const XLSX_RESERVED_XFS as int init 3;

/**
 * Collect every style the workbook uses into one table.
 *
 * @param wb {Workbook} the workbook
 * @return {XlsxFormats} the merged table and the per-sheet mapping
 */
func collectXlsxFormats(wb as Workbook) {
    def styles as list of Style init [];
    def indexOf as map of string to int init {};
    for (def sheetIndex in 0..len($wb.sheets)) {
        def sheet as Sheet init $wb.sheets[$sheetIndex];
        for (def local in 1..len($sheet.styles)) {
            def st as Style init $sheet.styles[$local];
            def at as int init styleSlot($styles, $st);
            if ($at < 0) {
                $styles[] = $st;
                $at = len($styles) - 1;
            }
            $indexOf[formatKey($sheetIndex, $local)] = $at + XLSX_RESERVED_XFS;
        }
    }
    return XlsxFormats{styles: $styles, indexOf: $indexOf};
}

/**
 * Where a style already sits in the merged table, if it does.
 *
 * @param styles {list of Style} the table so far
 * @param st {Style} the style to find
 * @return {int} the index, or `-1` when it is not there yet
 */
func styleSlot(styles as list of Style, st as Style) {
    for (def i in 0..len($styles)) {
        if ($styles[$i] == $st) {
            return $i;
        }
    }
    return -1;
}

/**
 * The key a sheet's local style index is mapped under.
 *
 * @param sheetIndex {int} the sheet's position
 * @param local {int} the index in that sheet's own style table
 * @return {string} the key
 */
func formatKey(sheetIndex as int, local as int) {
    return convert.toString($sheetIndex) + ":" + convert.toString($local);
}

/**
 * Which `cellXfs` entry a cell points at.
 *
 * A styled cell points at its style. An unstyled one points at the general
 * format, unless it holds a date, in which case it points at one of the two
 * reserved date formats - otherwise the right number would display as a
 * number.
 *
 * @param formats {XlsxFormats} the merged table
 * @param s {Sheet} the sheet
 * @param sheetIndex {int} the sheet's position
 * @param at {Ref} the cell
 * @param v {Value} the cell's value
 * @return {string} the index, as the `s` attribute's text
 */
func xlsxStyleIndex(formats as XlsxFormats, s as Sheet, sheetIndex as int, at as Ref, v as Value) {
    def key as string init cellRef($at);
    if (not maps.has($s.cellStyles, $key)) {
        return defaultStyleIndex($v);
    }
    def local as int init $s.cellStyles[$key];
    def mapped as string init formatKey($sheetIndex, $local);
    if ($local <= 0 or not maps.has($formats.indexOf, $mapped)) {
        return defaultStyleIndex($v);
    }
    # A style with no number format of its own still needs a date one when the
    # cell holds a date, or the serial would show.
    if (isDateValue($v) and not isDateFormat($s.styles[$local])) {
        return defaultStyleIndex($v);
    }
    return convert.toString($formats.indexOf[$mapped]);
}

/**
 * The reserved format an unstyled cell points at.
 *
 * @param v {Value} the cell's value
 * @return {string} the index, as text
 */
func defaultStyleIndex(v as Value) {
    match ($v) {
        when Stamp(st) { return stampStyleIndex($st.dateOnly); }
        else { return XF_GENERAL; }
    }
}

/**
 * Whether a value is a date.
 *
 * @param v {Value} the value
 * @return {bool} whether it is a `Stamp`
 */
func isDateValue(v as Value) {
    match ($v) {
        when Stamp(st) { return true; }
        else { return false; }
    }
}

/**
 * Which member a sheet's worksheet part is written to.
 *
 * @param i {int} the sheet's zero-based position
 * @return {string} the member path
 */
func sheetPartName(i as int) {
    return "xl/worksheets/sheet" + convert.toString($i + 1) + ".xml";
}

/**
 * The relationship id a sheet is reached by.
 *
 * @param i {int} the sheet's zero-based position
 * @return {string} the relationship id
 */
func sheetRelationId(i as int) {
    return "rId" + convert.toString($i + 1);
}

/**
 * The `[Content_Types].xml` part, declaring what every member is.
 *
 * Every part needs either a default for its extension or an explicit
 * override; a reader that cannot find one treats the member as unknown and
 * the file as damaged.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the content types part
 */
func xlsxContentTypes(wb as Workbook) {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<Types xmlns=\"" +
        "http://schemas.openxmlformats.org/package/2006/content-types\">";
    $parts[] = tagEmpty(
        "Default",
        {
            "Extension": "rels",
            "ContentType": "application/vnd.openxmlformats-package.relationships+xml"
        });
    $parts[] = tagEmpty("Default", {"Extension": "xml", "ContentType": "application/xml"});
    $parts[] = contentOverride("/" + XLSX_WORKBOOK, "sheet.main");
    for (def i in 0..len($wb.sheets)) {
        $parts[] = contentOverride("/" + sheetPartName($i), "worksheet");
    }
    $parts[] = contentOverride("/xl/styles.xml", "styles");
    $parts[] = contentOverride("/xl/sharedStrings.xml", "sharedStrings");
    $parts[] = tagClose("Types");
    return partsBytes($parts);
}

/**
 * One `<Override>` naming a spreadsheet part's type.
 *
 * @param partName {string} the part's path, with a leading slash
 * @param kind {string} the type's last segment, such as `"worksheet"`
 * @return {string} the element
 */
func contentOverride(partName as string, kind as string) {
    return tagEmpty(
        "Override",
        {
            "PartName": $partName,
            "ContentType": "application/vnd.openxmlformats-officedocument." +
                "spreadsheetml." + $kind + "+xml"
        });
}

/**
 * The `_rels/.rels` part, pointing at the workbook.
 *
 * @return {bytes} the root relationships part
 */
func xlsxRootRels() {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<Relationships xmlns=\"" + XLSX_PKG_REL_NS + "\">";
    $parts[] = tagEmpty(
        "Relationship",
        {"Id": "rId1", "Type": XLSX_REL_NS + "/officeDocument", "Target": XLSX_WORKBOOK});
    $parts[] = tagClose("Relationships");
    return partsBytes($parts);
}

/**
 * The `xl/workbook.xml` part, listing the sheets in order.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the workbook part
 */
func xlsxWorkbookPart(wb as Workbook) {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<workbook xmlns=\"" + XLSX_NS + "\" xmlns:r=\"" +
        XLSX_REL_NS + "\">";
    if ($wb.date1904) {
        $parts[] = tagEmpty("workbookPr", {"date1904": "1"});
    }
    $parts[] = tagOpen("sheets");
    for (def i in 0..len($wb.sheets)) {
        $parts[] = tagEmpty(
            "sheet",
            {
                "name": $wb.sheets[$i].name,
                "sheetId": convert.toString($i + 1),
                "r:id": sheetRelationId($i)
            });
    }
    $parts[] = tagClose("sheets");
    $parts[] = tagClose("workbook");
    return partsBytes($parts);
}

/**
 * The `xl/_rels/workbook.xml.rels` part.
 *
 * The sheets take the first relationship ids so that `sheetRelationId`
 * matches, and styles and shared strings follow them.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the workbook relationships part
 */
func xlsxWorkbookRels(wb as Workbook) {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<Relationships xmlns=\"" + XLSX_PKG_REL_NS + "\">";
    for (def i in 0..len($wb.sheets)) {
        $parts[] = tagEmpty(
            "Relationship",
            {
                "Id": sheetRelationId($i),
                "Type": XLSX_REL_NS + "/worksheet",
                "Target": "worksheets/sheet" + convert.toString($i + 1) + ".xml"
            });
    }
    def next as int init len($wb.sheets);
    $parts[] = tagEmpty(
        "Relationship",
        {
            "Id": "rId" + convert.toString($next + 1),
            "Type": XLSX_REL_NS + "/styles",
            "Target": "styles.xml"
        });
    $parts[] = tagEmpty(
        "Relationship",
        {
            "Id": "rId" + convert.toString($next + 2),
            "Type": XLSX_REL_NS + "/sharedStrings",
            "Target": "sharedStrings.xml"
        });
    $parts[] = tagClose("Relationships");
    return partsBytes($parts);
}

/**
 * The `xl/styles.xml` part.
 *
 * OOXML normalises a style into four indexed tables - number formats, fonts,
 * fills, borders - which `cellXfs` combines by index. Each table is built
 * from the distinct values the workbook's styles use, and every `xf` points
 * into them.
 *
 * Excel is strict about the skeleton: it wants two fills with the second
 * being `gray125`, and an `xf` that sets a property has to say so with the
 * matching `applyX` flag or the property is ignored.
 *
 * @param formats {XlsxFormats} the workbook's merged style table
 * @return {bytes} the styles part
 */
func xlsxStyles(formats as XlsxFormats) {
    def numFmts as list of string init distinctFormats($formats.styles);
    def fonts as list of Style init distinctFonts($formats.styles);
    def fills as list of string init distinctFills($formats.styles);
    def borders as list of BorderStyle init distinctBorders($formats.styles);

    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<styleSheet xmlns=\"" + XLSX_NS + "\">";
    $parts[] = xlsxNumFmtTable($numFmts);
    $parts[] = xlsxFontTable($fonts);
    $parts[] = xlsxFillTable($fills);
    $parts[] = xlsxBorderTable($borders);
    $parts[] = "<cellStyleXfs count=\"1\">" +
        "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/>" +
        "</cellStyleXfs>";
    $parts[] = xlsxCellXfs($formats, $numFmts, $fonts, $fills, $borders);
    $parts[] = "<cellStyles count=\"1\">" +
        "<cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>";
    $parts[] = tagClose("styleSheet");
    return partsBytes($parts);
}

/**
 * The distinct number format codes the styles use.
 *
 * @param styles {list of Style} the workbook's styles
 * @return {list of string} the codes, in first-seen order
 */
func distinctFormats(styles as list of Style) {
    def out as list of string init [];
    for (def st in $styles) {
        if ($st.format != "" and not lists.contains($out, $st.format)) {
            $out[] = $st.format;
        }
    }
    return $out;
}

/**
 * The distinct fonts the styles use.
 *
 * A font is the four text properties together, since OOXML indexes them as
 * one record. Index 0 is the default, which is always written.
 *
 * @param styles {list of Style} the workbook's styles
 * @return {list of Style} styles reduced to their font, index 0 the default
 */
func distinctFonts(styles as list of Style) {
    def out as list of Style init [];
    $out[] = style();
    for (def st in $styles) {
        def bare as Style init fontOnly($st);
        if (not isPlain($bare) and styleSlot($out, $bare) < 0) {
            $out[] = $bare;
        }
    }
    return $out;
}

/**
 * A style with everything but its font properties cleared.
 *
 * @param st {Style} the style
 * @return {Style} the font half of it
 */
func fontOnly(st as Style) {
    def out as Style init style();
    $out.bold = $st.bold;
    $out.italic = $st.italic;
    $out.underline = $st.underline;
    $out.fontName = $st.fontName;
    $out.fontSize = $st.fontSize;
    $out.colour = $st.colour;
    return $out;
}

/**
 * The distinct fills the styles use.
 *
 * The first two entries are reserved by the format: `none` and `gray125`.
 * Excel refuses a style sheet without them.
 *
 * @param styles {list of Style} the workbook's styles
 * @return {list of string} the fill colours, the first two being the reserved
 *   pair as `""`
 */
func distinctFills(styles as list of Style) {
    def out as list of string init [];
    $out[] = "";
    $out[] = "";
    for (def st in $styles) {
        if ($st.background != "" and not lists.contains($out, $st.background)) {
            $out[] = $st.background;
        }
    }
    return $out;
}

/**
 * The distinct border weights the styles use.
 *
 * @param styles {list of Style} the workbook's styles
 * @return {list of BorderStyle} the weights, index 0 always no border
 */
func distinctBorders(styles as list of Style) {
    def out as list of BorderStyle init [];
    $out[] = BorderStyle.NoBorder;
    for (def st in $styles) {
        if (borderToOoxml($st.border) != "" and not borderSeen($out, $st.border)) {
            $out[] = $st.border;
        }
    }
    return $out;
}

/**
 * Whether a border weight is already in a list.
 *
 * `lists.contains` wants a comparable element and an enum is one, but the
 * list is short enough that a scan reads clearer than the conversion.
 *
 * @param seen {list of BorderStyle} the weights so far
 * @param weight {BorderStyle} the weight to look for
 * @return {bool} whether it is there
 */
func borderSeen(seen as list of BorderStyle, weight as BorderStyle) {
    for (def each in $seen) {
        if ($each == $weight) {
            return true;
        }
    }
    return false;
}

/**
 * The `<numFmts>` table.
 *
 * Ids start at 164, which is where the format reserves the first id a file
 * may define; everything below it is built in.
 *
 * @param codes {list of string} the distinct format codes
 * @return {string} the table, or `""` when there are none
 */
func xlsxNumFmtTable(codes as list of string) {
    if (len($codes) == 0) {
        return "";
    }
    def parts as list of string init [];
    $parts[] = tagOpenWith("numFmts", {"count": convert.toString(len($codes))});
    for (def i in 0..len($codes)) {
        $parts[] = tagEmpty(
            "numFmt",
            {"numFmtId": convert.toString(XLSX_FIRST_NUMFMT + $i), "formatCode": $codes[$i]});
    }
    $parts[] = tagClose("numFmts");
    return strings.join($parts, "");
}

/**
 * The `<fonts>` table.
 *
 * @param fonts {list of Style} the distinct fonts
 * @return {string} the table
 */
func xlsxFontTable(fonts as list of Style) {
    def parts as list of string init [];
    $parts[] = tagOpenWith("fonts", {"count": convert.toString(len($fonts))});
    for (def st in $fonts) {
        $parts[] = xlsxFont($st);
    }
    $parts[] = tagClose("fonts");
    return strings.join($parts, "");
}

/**
 * One `<font>` record.
 *
 * @param st {Style} the style, reduced to its font
 * @return {string} the font element
 */
func xlsxFont(st as Style) {
    def parts as list of string init [];
    $parts[] = tagOpen("font");
    if ($st.bold) {
        $parts[] = "<b/>";
    }
    if ($st.italic) {
        $parts[] = "<i/>";
    }
    if ($st.underline) {
        $parts[] = tagEmpty("u", {"val": "single"});
    }
    def size as float init $st.fontSize;
    if ($size <= 0.0) {
        $size = 11.0;
    }
    $parts[] = tagEmpty("sz", {"val": numberAttr($size)});
    def name as string init $st.fontName;
    if ($name == "") {
        $name = "Calibri";
    }
    $parts[] = tagEmpty("name", {"val": $name});
    if ($st.colour != "") {
        $parts[] = tagEmpty("color", {"rgb": "FF" + $st.colour});
    }
    $parts[] = tagClose("font");
    return strings.join($parts, "");
}

/**
 * The `<fills>` table.
 *
 * @param fills {list of string} the distinct fill colours
 * @return {string} the table
 */
func xlsxFillTable(fills as list of string) {
    def parts as list of string init [];
    $parts[] = tagOpenWith("fills", {"count": convert.toString(len($fills))});
    $parts[] = "<fill><patternFill patternType=\"none\"/></fill>";
    $parts[] = "<fill><patternFill patternType=\"gray125\"/></fill>";
    for (def i in 2..len($fills)) {
        $parts[] = "<fill><patternFill patternType=\"solid\">" +
            tagEmpty("fgColor", {"rgb": "FF" + $fills[$i]}) +
            tagEmpty("bgColor", {"rgb": "FF" + $fills[$i]}) +
            "</patternFill></fill>";
    }
    $parts[] = tagClose("fills");
    return strings.join($parts, "");
}

/**
 * The `<borders>` table.
 *
 * @param borders {list of BorderStyle} the distinct weights
 * @return {string} the table
 */
func xlsxBorderTable(borders as list of BorderStyle) {
    def parts as list of string init [];
    $parts[] = tagOpenWith("borders", {"count": convert.toString(len($borders))});
    $parts[] = "<border/>";
    for (def i in 1..len($borders)) {
        def weight as string init borderToOoxml($borders[$i]);
        def edges as list of string init [];
        for (def side in ["left", "right", "top", "bottom"]) {
            $edges[] = tagOpenWith($side, {"style": $weight}) +
                tagEmpty("color", {"rgb": "FF000000"}) + tagClose($side);
        }
        $parts[] = tagOpen("border") + strings.join($edges, "") + tagClose("border");
    }
    $parts[] = tagClose("borders");
    return strings.join($parts, "");
}

/**
 * The `<cellXfs>` table: the three reserved entries, then one per style.
 *
 * @param formats {XlsxFormats} the workbook's merged style table
 * @param numFmts {list of string} the distinct format codes
 * @param fonts {list of Style} the distinct fonts
 * @param fills {list of string} the distinct fill colours
 * @param borders {list of BorderStyle} the distinct weights
 * @return {string} the table
 */
func xlsxCellXfs(
    formats as XlsxFormats,
    numFmts as list of string,
    fonts as list of Style,
    fills as list of string,
    borders as list of BorderStyle) {
    def parts as list of string init [];
    def count as int init XLSX_RESERVED_XFS + len($formats.styles);
    $parts[] = tagOpenWith("cellXfs", {"count": convert.toString($count)});
    $parts[] = "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"" +
        " xfId=\"0\"/>";
    $parts[] = "<xf numFmtId=\"14\" fontId=\"0\" fillId=\"0\" borderId=\"0\"" +
        " xfId=\"0\" applyNumberFormat=\"1\"/>";
    $parts[] = "<xf numFmtId=\"22\" fontId=\"0\" fillId=\"0\" borderId=\"0\"" +
        " xfId=\"0\" applyNumberFormat=\"1\"/>";
    for (def st in $formats.styles) {
        $parts[] = xlsxCellXf($st, $numFmts, $fonts, $fills, $borders);
    }
    $parts[] = tagClose("cellXfs");
    return strings.join($parts, "");
}

/**
 * One `<xf>` combining a style's entries from the four tables.
 *
 * @param st {Style} the style
 * @param numFmts {list of string} the distinct format codes
 * @param fonts {list of Style} the distinct fonts
 * @param fills {list of string} the distinct fill colours
 * @param borders {list of BorderStyle} the distinct weights
 * @return {string} the `xf` element
 */
func xlsxCellXf(
    st as Style,
    numFmts as list of string,
    fonts as list of Style,
    fills as list of string,
    borders as list of BorderStyle) {
    def attrs as map of string to string init {};
    def numFmtId as int init 0;
    if ($st.format != "") {
        $numFmtId = XLSX_FIRST_NUMFMT + stringIndex($numFmts, $st.format);
    }
    $attrs["numFmtId"] = convert.toString($numFmtId);
    $attrs["fontId"] = convert.toString(fontIndex($fonts, $st));
    $attrs["fillId"] = convert.toString(fillIndex($fills, $st.background));
    $attrs["borderId"] = convert.toString(borderIndex($borders, $st.border));
    $attrs["xfId"] = "0";
    # Excel ignores a property the xf does not claim to apply.
    if ($numFmtId != 0) {
        $attrs["applyNumberFormat"] = "1";
    }
    if (not isPlain(fontOnly($st))) {
        $attrs["applyFont"] = "1";
    }
    if ($st.background != "") {
        $attrs["applyFill"] = "1";
    }
    if (borderToOoxml($st.border) != "") {
        $attrs["applyBorder"] = "1";
    }
    def alignment as map of string to string init xlsxAlignment($st);
    if (len($alignment) == 0) {
        return tagEmpty("xf", $attrs);
    }
    $attrs["applyAlignment"] = "1";
    return tagOpenWith("xf", $attrs) + tagEmpty("alignment", $alignment) +
        tagClose("xf");
}

/**
 * A style's `<alignment>` attributes.
 *
 * @param st {Style} the style
 * @return {map of string to string} the attributes, empty when there are none
 */
func xlsxAlignment(st as Style) {
    def attrs as map of string to string init {};
    def horizontal as string init alignToOoxml($st.align);
    if ($horizontal != "") {
        $attrs["horizontal"] = $horizontal;
    }
    def vertical as string init valignToOoxml($st.valign);
    if ($vertical != "") {
        $attrs["vertical"] = $vertical;
    }
    if ($st.wrap) {
        $attrs["wrapText"] = "1";
    }
    return $attrs;
}

/**
 * Where a string sits in a list.
 *
 * `lists` has `contains` but no index-of, and both tables here are short
 * enough that a scan is the right answer anyway.
 *
 * @param haystack {list of string} the list
 * @param needle {string} the value to find
 * @return {int} the index, or `-1` when it is not there
 */
func stringIndex(haystack as list of string, needle as string) {
    for (def i in 0..len($haystack)) {
        if ($haystack[$i] == $needle) {
            return $i;
        }
    }
    return -1;
}

/**
 * Which `<font>` a style points at.
 *
 * @param fonts {list of Style} the distinct fonts
 * @param st {Style} the style
 * @return {int} the index, 0 for the default
 */
func fontIndex(fonts as list of Style, st as Style) {
    def at as int init styleSlot($fonts, fontOnly($st));
    if ($at < 0) {
        return 0;
    }
    return $at;
}

/**
 * Which `<fill>` a style points at.
 *
 * @param fills {list of string} the distinct fill colours
 * @param background {string} the style's fill, `""` for none
 * @return {int} the index, 0 for no fill
 */
func fillIndex(fills as list of string, background as string) {
    if ($background == "") {
        return 0;
    }
    def at as int init stringIndex($fills, $background);
    if ($at < 0) {
        return 0;
    }
    return $at;
}

/**
 * Which `<border>` a style points at.
 *
 * @param borders {list of BorderStyle} the distinct weights
 * @param weight {BorderStyle} the style's weight
 * @return {int} the index, 0 for no border
 */
func borderIndex(borders as list of BorderStyle, weight as BorderStyle) {
    for (def i in 0..len($borders)) {
        if ($borders[$i] == $weight) {
            return $i;
        }
    }
    return 0;
}

/**
 * The `xl/sharedStrings.xml` part.
 *
 * `xml:space="preserve"` goes on every entry, because a label with a leading
 * or trailing space is otherwise free to be collapsed by a reader.
 *
 * @param shared {SharedStrings} the table
 * @return {bytes} the shared strings part
 */
func xlsxSharedStringsPart(shared as SharedStrings) {
    def parts as list of string init [];
    def count as string init convert.toString(len($shared.texts));
    $parts[] = XML_DECLARATION;
    $parts[] = "<sst xmlns=\"" + XLSX_NS + "\" count=\"" + $count +
        "\" uniqueCount=\"" + $count + "\">";
    for (def body in $shared.texts) {
        $parts[] = tagOpen("si") +
            tagTextWith("t", {"xml:space": "preserve"}, $body) + tagClose("si");
    }
    $parts[] = tagClose("sst");
    return partsBytes($parts);
}

/**
 * One worksheet part.
 *
 * @param s {Sheet} the sheet
 * @param sheetIndex {int} the sheet's position, to resolve its style indices
 * @param shared {SharedStrings} the shared string table
 * @param formats {XlsxFormats} the workbook's merged style table
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {bytes} the worksheet part
 */
func xlsxWorksheet(
    s as Sheet,
    sheetIndex as int,
    shared as SharedStrings,
    formats as XlsxFormats,
    date1904 as bool) {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<worksheet xmlns=\"" + XLSX_NS + "\">";
    $parts[] = tagEmpty("dimension", {"ref": areaRef(extent($s))});
    $parts[] = tagOpen("sheetData");
    def lines as list of list of Value init rows($s);
    for (def r in 0..len($lines)) {
        def styleIndices as list of string init styleIndicesForRow(
            $formats,
            $s,
            $sheetIndex,
            $r,
            $lines[$r]);
        def line as string init xlsxRowMarkup($lines[$r], $styleIndices, $r, $shared, $date1904);
        if ($line != "") {
            $parts[] = $line;
        }
    }
    $parts[] = tagClose("sheetData");
    $parts[] = tagClose("worksheet");
    return partsBytes($parts);
}

/**
 * One `<row>`, holding only the cells that are not empty.
 *
 * Unlike ODS, the format needs no run-length encoding for a gap: a cell
 * carries its own reference, so an absent cell is not written. A row
 * with nothing in it is not written either, and comes back as `""`.
 *
 * @param line {list of Value} the row's values, left to right
 * @param styleIndices {list of string} the `cellXfs` index per column
 * @param row {int} the zero-based row index
 * @param shared {SharedStrings} the shared string table
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {string} the row element, or `""` when the row is empty
 */
func xlsxRowMarkup(
    line as list of Value,
    styleIndices as list of string,
    row as int,
    shared as SharedStrings,
    date1904 as bool) {
    def cells as list of string init [];
    for (def c in 0..len($line)) {
        def styleIndex as string init XF_GENERAL;
        if ($c < len($styleIndices)) {
            $styleIndex = $styleIndices[$c];
        }
        # A styled blank cell is still written: that is how a blank gets a
        # background or a border.
        if (not isEmpty($line[$c]) or $styleIndex != XF_GENERAL) {
            $cells[] = xlsxCellMarkup(
                Ref{row: $row, col: $c},
                $line[$c],
                $styleIndex,
                $shared,
                $date1904);
        }
    }
    if (len($cells) == 0) {
        return "";
    }
    return tagOpenWith("row", {"r": convert.toString($row + 1)}) +
        strings.join($cells, "") + tagClose("row");
}

/**
 * The `cellXfs` index each cell of a row points at.
 *
 * Resolved once per row so the cell builder is handed everything it needs and
 * does not reach back into the sheet per cell.
 *
 * @param formats {XlsxFormats} the workbook's merged style table
 * @param s {Sheet} the sheet
 * @param sheetIndex {int} the sheet's position
 * @param row {int} the zero-based row index
 * @param line {list of Value} the row's values
 * @return {list of string} one index per column, as text
 */
func styleIndicesForRow(
    formats as XlsxFormats,
    s as Sheet,
    sheetIndex as int,
    row as int,
    line as list of Value) {
    def out as list of string init [];
    for (def c in 0..len($line)) {
        $out[] = xlsxStyleIndex($formats, $s, $sheetIndex, Ref{row: $row, col: $c}, $line[$c]);
    }
    return $out;
}

/**
 * One `<c>` cell element.
 *
 * @param at {Ref} where the cell sits
 * @param v {Value} the value
 * @param styleIndex {string} the `cellXfs` index to point at
 * @param shared {SharedStrings} the shared string table
 * @param date1904 {bool} whether the workbook uses the 1904 date system
 * @return {string} the cell element
 */
func xlsxCellMarkup(
    at as Ref,
    v as Value,
    styleIndex as string,
    shared as SharedStrings,
    date1904 as bool) {
    def attrs as map of string to string init {"r": cellRef($at)};
    if ($styleIndex != XF_GENERAL) {
        $attrs["s"] = $styleIndex;
    }
    match ($v) {
        when Text(t) {
            $attrs["t"] = "s";
            return xlsxWrapCell(
                $attrs,
                tagText("v", convert.toString(sharedIndex($shared, $t.body))));
        }
        when Number(n) { return xlsxWrapCell($attrs, tagText("v", numberAttr($n.amount))); }
        when Bool(b) {
            $attrs["t"] = "b";
            return xlsxWrapCell($attrs, tagText("v", boolDigit($b.flag)));
        }
        when Stamp(st) {
            return xlsxWrapCell($attrs, tagText("v", numberAttr(toSerial($st.at, $date1904))));
        }
        when Formula(f) { return xlsxFormulaCell($attrs, $f.source, $f.cached); }
        when Err(err) {
            $attrs["t"] = "e";
            return xlsxWrapCell($attrs, tagText("v", $err.code));
        }
        when Empty { return tagEmpty("c", $attrs); }
    }
}

/**
 * A `<c>` around its contents.
 *
 * @param attrs {map of string to string} the cell's attributes
 * @param inner {string} the cell's child elements
 * @return {string} the cell element
 */
func xlsxWrapCell(attrs as map of string to string, inner as string) {
    return tagOpenWith("c", $attrs) + $inner + tagClose("c");
}

/**
 * A formula cell, with its expression and its cached result.
 *
 * The expression is written as it is stored, because the model's dialect is
 * already A1 and that is what the format wants. A cached result that is not a
 * number is typed `str`, which is how the format carries a text result.
 *
 * @param attrs {map of string to string} the cell's attributes so far
 * @param source {string} the formula, with no leading `=`
 * @param cached {string} the last computed result, as text
 * @return {string} the cell element
 */
func xlsxFormulaCell(attrs as map of string to string, source as string, cached as string) {
    def cellAttrs as map of string to string init $attrs;
    def numeric as bool init true;
    def amount as float init 0.0;
    if ($cached == "") {
        $numeric = false;
    } else {
        try {
            $amount = convert.toFloat(strings.trim($cached));
        } catch (err) {
            $numeric = false;
        }
    }
    if (not $numeric and $cached != "") {
        $cellAttrs["t"] = "str";
    }
    def inner as string init tagText("f", $source);
    if ($cached != "" and $numeric) {
        $inner = $inner + tagText("v", numberAttr($amount));
    } elseif ($cached != "") {
        $inner = $inner + tagText("v", $cached);
    }
    return xlsxWrapCell($cellAttrs, $inner);
}

/**
 * Where a string sits in the shared table.
 *
 * @param shared {SharedStrings} the table
 * @param body {string} the string
 * @return {int} the index, or 0 when the string is absent
 */
func sharedIndex(shared as SharedStrings, body as string) {
    if (maps.has($shared.index, $body)) {
        return $shared.index[$body];
    }
    return 0;
}

/**
 * A boolean as the digit the format stores.
 *
 * @param flag {bool} the value
 * @return {string} `"1"` or `"0"`
 */
func boolDigit(flag as bool) {
    if ($flag) {
        return "1";
    }
    return "0";
}

/**
 * The style index a date cell points at.
 *
 * @param dateOnly {bool} whether the value carries no time of day
 * @return {string} the cell format index
 */
func stampStyleIndex(dateOnly as bool) {
    if ($dateOnly) {
        return XF_DATE;
    }
    return XF_DATETIME;
}
