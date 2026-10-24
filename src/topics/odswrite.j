# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the OpenDocument spreadsheet writer.
# Spliced into sheets.j via include - not a standalone module.

/** The ODF version the written documents declare. */
def const ODF_VERSION as string init "1.3";

/** The namespace declarations `content.xml` needs. */
def const CONTENT_NAMESPACES as string init " xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\"" +
    " xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\"" +
    " xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"" +
    " xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\"" +
    " xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0\"" +
    " xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\"" +
    " xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\"";

/** The style a date cell points at, declared once in the automatic styles. */
def const DATE_STYLE as string init "ceDate";

/** The style a date-and-time cell points at. */
def const DATETIME_STYLE as string init "ceDateTime";

/**
 * Write a workbook as an ODS container.
 *
 * The container is assembled with this deck's own ZIP writer rather than
 * `archive.pack`, because ODF requires `mimetype` first and uncompressed and
 * `archive.pack` cannot do either. See `zip.j`.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the `.ods` file
 * @throws {Error} kind "sheets" when the workbook has no sheets
 * @example
 *   fs.writeBytes("out.ods", writeOds($wb));
 */
export func writeOds(wb as Workbook) {
    if (len($wb.sheets) == 0) {
        fail("cannot write a workbook with no sheets");
    }
    def members as list of Member init [];
    $members[] = storedMember("mimetype", convert.bytesFromString(ODS_MIMETYPE, "utf-8"));
    $members[] = member("META-INF/manifest.xml", odsManifest());
    $members[] = member("content.xml", writeOdsContent($wb));
    $members[] = member("styles.xml", odsStyles());
    $members[] = member("meta.xml", odsMeta());
    return zip($members);
}

/**
 * The `META-INF/manifest.xml` listing the container's parts.
 *
 * @return {bytes} the manifest
 */
func odsManifest() {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<manifest:manifest xmlns:manifest=" +
        "\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\"" +
        " manifest:version=\"" + ODF_VERSION + "\">";
    for (def entry in ["/", "content.xml", "styles.xml", "meta.xml"]) {
        def mediaType as string init "text/xml";
        if ($entry == "/") {
            $mediaType = ODS_MIMETYPE;
        }
        $parts[] = tagEmpty(
            "manifest:file-entry",
            {"manifest:full-path": $entry, "manifest:media-type": $mediaType});
    }
    $parts[] = tagClose("manifest:manifest");
    return partsBytes($parts);
}

/**
 * A minimal `styles.xml`.
 *
 * ODF requires the part. Every style this deck writes is an automatic style
 * in `content.xml`, so this one is well-formed and empty.
 *
 * @return {bytes} the styles part
 */
func odsStyles() {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<office:document-styles" + CONTENT_NAMESPACES +
        " office:version=\"" + ODF_VERSION + "\">";
    $parts[] = "<office:styles/>";
    $parts[] = tagClose("office:document-styles");
    return partsBytes($parts);
}

/**
 * A minimal `meta.xml`.
 *
 * The generator is named but no timestamp is written, so that writing the
 * same workbook twice produces the same bytes.
 *
 * @return {bytes} the metadata part
 */
func odsMeta() {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<office:document-meta" + CONTENT_NAMESPACES +
        " xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\"" +
        " office:version=\"" + ODF_VERSION + "\">";
    $parts[] = tagOpen("office:meta");
    $parts[] = tagText("meta:generator", "@deckyard/sheets " + VERSION);
    $parts[] = tagClose("office:meta");
    $parts[] = tagClose("office:document-meta");
    return partsBytes($parts);
}

/**
 * Write a workbook's `content.xml`.
 *
 * The bare part, without the container around it.
 *
 * The pieces are accumulated into one local list here and each sheet returns
 * its own finished markup, so nothing hands the accumulator down. See
 * `emit.j` for why that matters.
 *
 * @param wb {Workbook} the workbook
 * @return {bytes} the content part
 * @example
 *   def content as bytes init writeOdsContent($wb);
 */
export func writeOdsContent(wb as Workbook) {
    def parts as list of string init [];
    $parts[] = XML_DECLARATION;
    $parts[] = "<office:document-content" + CONTENT_NAMESPACES +
        " office:version=\"" + ODF_VERSION + "\">";
    $parts[] = odsAutomaticStyles($wb);
    $parts[] = tagOpen("office:body");
    $parts[] = tagOpen("office:spreadsheet");
    for (def i in 0..len($wb.sheets)) {
        $parts[] = odsTableMarkup($wb.sheets[$i], $i);
    }
    $parts[] = tagClose("office:spreadsheet");
    $parts[] = tagClose("office:body");
    $parts[] = tagClose("office:document-content");
    return partsBytes($parts);
}

/**
 * The automatic styles the written cells point at.
 *
 * Two date styles, always written: without them a date cell carries the
 * right value but an application has no format to render it with and shows
 * the serial number. Then each sheet's own cell styles, named by the sheet's
 * position so two sheets' tables cannot collide.
 *
 * @param wb {Workbook} the workbook whose sheets' styles are declared
 * @return {string} the automatic styles element
 */
func odsAutomaticStyles(wb as Workbook) {
    def parts as list of string init [];
    $parts[] = tagOpen("office:automatic-styles");

    $parts[] = tagOpenWith("number:date-style", {"style:name": "nDate"});
    $parts[] = odsDateParts();
    $parts[] = tagClose("number:date-style");

    $parts[] = tagOpenWith("number:date-style", {"style:name": "nDateTime"});
    $parts[] = odsDateParts();
    $parts[] = tagText("number:text", " ");
    $parts[] = tagEmpty("number:hours", {"number:style": "long"});
    $parts[] = tagText("number:text", ":");
    $parts[] = tagEmpty("number:minutes", {"number:style": "long"});
    $parts[] = tagText("number:text", ":");
    $parts[] = tagEmpty("number:seconds", {"number:style": "long"});
    $parts[] = tagClose("number:date-style");

    $parts[] = tagEmpty(
        "style:style",
        {"style:name": DATE_STYLE, "style:family": "table-cell", "style:data-style-name": "nDate"});
    $parts[] = tagEmpty(
        "style:style",
        {
            "style:name": DATETIME_STYLE,
            "style:family": "table-cell",
            "style:data-style-name": "nDateTime"
        });

    # Then one cell style per distinct style each sheet uses. The names are
    # qualified by the sheet's position so two sheets' tables cannot collide.
    for (def i in 0..len($wb.sheets)) {
        $parts[] = odsSheetStyles($wb.sheets[$i], $i);
    }

    $parts[] = tagClose("office:automatic-styles");
    return strings.join($parts, "");
}

/**
 * The cell styles one sheet's table declares.
 *
 * Index 0 is the default and is never written: a cell with no style name
 * inherits the application's own default, which is what the default style
 * means.
 *
 * @param s {Sheet} the sheet
 * @param sheetIndex {int} the sheet's position, to qualify the style names
 * @return {string} the style elements
 */
func odsSheetStyles(s as Sheet, sheetIndex as int) {
    def parts as list of string init [];
    for (def i in 1..len($s.styles)) {
        def st as Style init $s.styles[$i];
        def name as string init odsStyleName($sheetIndex, $i);
        if ($st.format != "") {
            $parts[] = odsNumberStyle($name + "N", $st.format);
        }
        $parts[] = odsCellStyle($name, $st, $sheetIndex, $i);
    }
    return strings.join($parts, "");
}

/**
 * The name a sheet's style index is written under.
 *
 * @param sheetIndex {int} the sheet's position
 * @param styleIndex {int} the index in the sheet's style table
 * @return {string} the style name
 */
func odsStyleName(sheetIndex as int, styleIndex as int) {
    return "ce" + convert.toString($sheetIndex) + "x" + convert.toString($styleIndex);
}

/**
 * One `<style:style>` for a cell style.
 *
 * @param name {string} the style name
 * @param st {Style} the style
 * @param sheetIndex {int} the sheet's position
 * @param styleIndex {int} the index in the sheet's style table
 * @return {string} the style element
 */
func odsCellStyle(name as string, st as Style, sheetIndex as int, styleIndex as int) {
    def attrs as map of string to string init {"style:name": $name, "style:family": "table-cell"};
    if ($st.format != "") {
        $attrs["style:data-style-name"] = $name + "N";
    }
    def parts as list of string init [];
    $parts[] = tagOpenWith("style:style", $attrs);
    def cellProps as map of string to string init odsCellProperties($st);
    if (len($cellProps) > 0) {
        $parts[] = tagEmpty("style:table-cell-properties", $cellProps);
    }
    def paraProps as map of string to string init odsParagraphProperties($st);
    if (len($paraProps) > 0) {
        $parts[] = tagEmpty("style:paragraph-properties", $paraProps);
    }
    def textProps as map of string to string init odsTextProperties($st);
    if (len($textProps) > 0) {
        $parts[] = tagEmpty("style:text-properties", $textProps);
    }
    $parts[] = tagClose("style:style");
    return strings.join($parts, "");
}

/**
 * The cell-level properties a style sets: fill, border, wrapping, vertical fit.
 *
 * @param st {Style} the style
 * @return {map of string to string} the attributes, empty when there are none
 */
func odsCellProperties(st as Style) {
    def attrs as map of string to string init {};
    if ($st.background != "") {
        $attrs["fo:background-color"] = "#" + $st.background;
    }
    def border as string init borderToOdf($st.border);
    if ($border != "") {
        $attrs["fo:border"] = $border;
    }
    if ($st.wrap) {
        $attrs["fo:wrap-option"] = "wrap";
    }
    def valign as string init valignToOdf($st.valign);
    if ($valign != "") {
        $attrs["style:vertical-align"] = $valign;
    }
    return $attrs;
}

/**
 * The paragraph-level property a style sets: the horizontal alignment.
 *
 * ODF puts the horizontal alignment on the paragraph rather than the cell,
 * which is the one place its model differs from OOXML's by more than a name.
 *
 * @param st {Style} the style
 * @return {map of string to string} the attributes, empty when there are none
 */
func odsParagraphProperties(st as Style) {
    def attrs as map of string to string init {};
    def align as string init alignToOdf($st.align);
    if ($align != "") {
        $attrs["fo:text-align"] = $align;
    }
    return $attrs;
}

/**
 * The text-level properties a style sets: the font and its colour.
 *
 * @param st {Style} the style
 * @return {map of string to string} the attributes, empty when there are none
 */
func odsTextProperties(st as Style) {
    def attrs as map of string to string init {};
    if ($st.bold) {
        $attrs["fo:font-weight"] = "bold";
    }
    if ($st.italic) {
        $attrs["fo:font-style"] = "italic";
    }
    if ($st.underline) {
        $attrs["style:text-underline-style"] = "solid";
        $attrs["style:text-underline-width"] = "auto";
    }
    if ($st.fontName != "") {
        # `fo:font-family`, not `style:font-name`: the latter is a reference to
        # a font face that has to be declared in `<office:font-face-decls>`,
        # and without the declaration an application silently ignores it.
        # Checked in LibreOffice, which kept the font from the XLSX and
        # dropped it from the ODS until this changed.
        $attrs["fo:font-family"] = $st.fontName;
    }
    if ($st.fontSize > 0.0) {
        $attrs["fo:font-size"] = numberAttr($st.fontSize) + "pt";
    }
    if ($st.colour != "") {
        $attrs["fo:color"] = "#" + $st.colour;
    }
    return $attrs;
}

/**
 * A number style for a format code.
 *
 * The whole code, as ODF's tree of components - see odsfmt.j, which is where
 * the taking-apart lives. This used to write the decimal places and nothing
 * else, so `$#,##0.00` came back from a round trip as `0.00` and every date
 * format as `yyyy-mm-dd`.
 *
 * @param name {string} the style name
 * @param code {string} the number format code
 * @return {string} the number style element, with any sub-styles it needs
 */
func odsNumberStyle(name as string, code as string) {
    return odfNumberStyle($name, $code);
}

/**
 * The year-month-day run both date styles open with.
 *
 * @return {string} the date components
 */
func odsDateParts() {
    def parts as list of string init [];
    $parts[] = tagEmpty("number:year", {"number:style": "long"});
    $parts[] = tagText("number:text", "-");
    $parts[] = tagEmpty("number:month", {"number:style": "long"});
    $parts[] = tagText("number:text", "-");
    $parts[] = tagEmpty("number:day", {"number:style": "long"});
    return strings.join($parts, "");
}

/**
 * One sheet as a `<table:table>`.
 *
 * @param s {Sheet} the sheet
 * @param sheetIndex {int} the sheet's position, to name its styles
 * @return {string} the table element
 */
func odsTableMarkup(s as Sheet, sheetIndex as int) {
    def parts as list of string init [];
    $parts[] = tagOpenWith("table:table", {"table:name": $s.name});
    def width as int init $s.colCount;
    if ($width < 1) {
        $width = 1;
    }
    $parts[] = tagEmpty(
        "table:table-column",
        {"table:number-columns-repeated": convert.toString($width)});
    # One row of the sheet is pulled out once and read from the list, rather
    # than asking the sheet for each cell: `cellAt` per cell would be a lookup
    # per cell where this is one pass.
    def lines as list of list of Value init rows($s);
    for (def r in 0..len($lines)) {
        $parts[] = odsRowMarkup($lines[$r], styleNamesForRow($s, $r, $sheetIndex));
    }
    $parts[] = tagClose("table:table");
    return strings.join($parts, "");
}

/**
 * One row as a `<table:table-row>`.
 *
 * Runs of empty cells are re-compressed into `table:number-columns-repeated`
 * rather than written out one by one. An uncompressed row is valid but a
 * sheet with a few scattered cells would grow to the size of its bounding
 * box, which is what the encoding exists to avoid.
 *
 * @param line {list of Value} the row's values, left to right
 * @param styleNames {list of string} each column's cell style, "" for none
 * @return {string} the row element
 */
func odsRowMarkup(line as list of Value, styleNames as list of string) {
    def parts as list of string init [];
    $parts[] = tagOpen("table:table-row");
    def col as int init 0;
    while ($col < len($line)) {
        def styleName as string init "";
        if ($col < len($styleNames)) {
            $styleName = $styleNames[$col];
        }
        if (isEmpty($line[$col]) and $styleName == "") {
            def run as int init emptyUnstyledRun($line, $styleNames, $col);
            $parts[] = odsEmptyCells($run);
            $col = $col + $run;
        } else {
            $parts[] = odsCellMarkup($line[$col], $styleName);
            $col = $col + 1;
        }
    }
    $parts[] = tagClose("table:table-row");
    return strings.join($parts, "");
}

/**
 * The style name each cell of a row points at.
 *
 * Returned as a list so the row builder is handed everything it needs and
 * does not reach back into the sheet per cell.
 *
 * @param s {Sheet} the sheet
 * @param row {int} the zero-based row index
 * @param sheetIndex {int} the sheet's position
 * @return {list of string} one name per column, `""` where the style is the
 *   default
 */
func styleNamesForRow(s as Sheet, row as int, sheetIndex as int) {
    def out as list of string init [];
    for (def c in 0..$s.colCount) {
        def key as string init cellRef(Ref{row: $row, col: $c});
        if (not maps.has($s.cellStyles, $key)) {
            $out[] = "";
            continue;
        }
        def index as int init $s.cellStyles[$key];
        if ($index <= 0 or $index >= len($s.styles)) {
            $out[] = "";
            continue;
        }
        $out[] = odsStyleName($sheetIndex, $index);
    }
    return $out;
}

/**
 * How many cells run empty *and* unstyled from a position.
 *
 * A styled blank cell cannot join a repeated run, because the run would carry
 * its style across every cell it covers.
 *
 * @param line {list of Value} the row's values
 * @param styleNames {list of string} the row's style names
 * @param col {int} where the run starts
 * @return {int} the run's length, at least 1
 */
func emptyUnstyledRun(line as list of Value, styleNames as list of string, col as int) {
    def run as int init 0;
    def at as int init $col;
    while ($at < len($line) and isEmpty($line[$at]) and
        ($at >= len($styleNames) or $styleNames[$at] == "")) {
        $run = $run + 1;
        $at = $at + 1;
    }
    if ($run < 1) {
        return 1;
    }
    return $run;
}

/**
 * A run of empty cells as one element.
 *
 * @param run {int} how many cells the run covers
 * @return {string} the element
 */
func odsEmptyCells(run as int) {
    if ($run == 1) {
        return tagEmpty("table:table-cell", {});
    }
    return tagEmpty("table:table-cell", {"table:number-columns-repeated": convert.toString($run)});
}

/**
 * One cell as a `<table:table-cell>`.
 *
 * Every cell carries both the machine-readable value (in a typed attribute)
 * and the displayed text (in a `<text:p>`), because that is what ODF asks for
 * and what lets an application show the cell without recomputing anything.
 *
 * @param v {Value} the value
 * @param styleName {string} the style to point at, `""` for the default
 * @return {string} the cell element
 */
func odsCellMarkup(v as Value, styleName as string) {
    def attrs as map of string to string init odsCellAttrs($v);
    if ($styleName != "") {
        $attrs["table:style-name"] = $styleName;
    }
    def shown as string init asString($v);
    if ($shown == "") {
        return tagEmpty("table:table-cell", $attrs);
    }
    return tagOpenWith("table:table-cell", $attrs) + odsParagraphs($shown) +
        tagClose("table:table-cell");
}

/**
 * A cell's displayed text as `<text:p>` elements.
 *
 * A newline in a cell becomes a separate paragraph, which is how ODF carries
 * a multi-line cell and how this deck reads one back.
 *
 * @param shown {string} the displayed text
 * @return {string} the paragraphs
 */
func odsParagraphs(shown as string) {
    if (not strings.contains($shown, "\n")) {
        return tagText("text:p", $shown);
    }
    def parts as list of string init [];
    for (def line in strings.split($shown, "\n")) {
        $parts[] = tagText("text:p", $line);
    }
    return strings.join($parts, "");
}

/**
 * The typed attributes one value needs on its cell element.
 *
 * @param v {Value} the value
 * @return {map of string to string} the attributes
 */
func odsCellAttrs(v as Value) {
    def attrs as map of string to string init {};
    match ($v) {
        when Empty {
        }
        when Text(t) { $attrs["office:value-type"] = "string"; }
        when Number(n) {
            $attrs["office:value-type"] = "float";
            $attrs["office:value"] = numberAttr($n.amount);
        }
        when Bool(b) {
            $attrs["office:value-type"] = "boolean";
            $attrs["office:boolean-value"] = boolAttr($b.flag);
        }
        when Stamp(s) {
            $attrs["table:style-name"] = stampStyle($s.dateOnly);
            $attrs["office:value-type"] = "date";
            $attrs["office:date-value"] = stampAttr($s.at, $s.dateOnly);
        }
        when Formula(f) {
            $attrs["table:formula"] = "of:=" + toOpenFormula($f.source);
            $attrs = formulaValueAttrs($attrs, $f.cached);
        }
        when Err(err) {
            # ODF has no error type, so the code goes in the displayed text
            # with no value-type at all. Typing it as a string instead would
            # read back as text, losing the fact that it was an error; left
            # untyped, the reader recovers it. The cost is that a text cell
            # whose content genuinely looks like an error code round-trips as
            # an error, which is an ambiguity the format cannot resolve.
        }
    }
    return $attrs;
}

/**
 * The style a date cell points at.
 *
 * @param dateOnly {bool} whether the value carries no time of day
 * @return {string} the style name
 */
func stampStyle(dateOnly as bool) {
    if ($dateOnly) {
        return DATE_STYLE;
    }
    return DATETIME_STYLE;
}

/**
 * The typed value attributes a formula's cached result needs.
 *
 * A formula cell carries its last computed result alongside the expression,
 * so an application can show the sheet before recalculating. A numeric result
 * is written as a float; anything else as a string.
 *
 * @param attrs {map of string to string} the attributes so far
 * @param cached {string} the cached result, as text
 * @return {map of string to string} the attributes with the value added
 */
func formulaValueAttrs(attrs as map of string to string, cached as string) {
    def out as map of string to string init $attrs;
    if ($cached == "") {
        return $out;
    }
    def amount as float init 0.0;
    def numeric as bool init true;
    try {
        $amount = convert.toFloat(strings.trim($cached));
    } catch (e) {
        $numeric = false;
    }
    if ($numeric) {
        $out["office:value-type"] = "float";
        $out["office:value"] = numberAttr($amount);
        return $out;
    }
    $out["office:value-type"] = "string";
    return $out;
}

/**
 * A number as an ODS attribute value.
 *
 * Always the full precision, never a locale-dependent rendering: the
 * attribute is the machine-readable half of the cell.
 *
 * @param amount {float} the number
 * @return {string} the attribute value
 */
func numberAttr(amount as float) {
    if ($amount == math.floor($amount) and math.abs($amount) < 1e15) {
        return convert.toString(convert.toInt($amount));
    }
    return convert.toString($amount);
}

/**
 * A boolean as an ODS attribute value.
 *
 * @param flag {bool} the value
 * @return {string} `"true"` or `"false"`
 */
func boolAttr(flag as bool) {
    if ($flag) {
        return "true";
    }
    return "false";
}

/**
 * An instant as an ODS `office:date-value`.
 *
 * @param at {time.Time} the instant
 * @param dateOnly {bool} whether to omit the time of day
 * @return {string} the ISO 8601 spelling ODF expects, with no zone
 */
func stampAttr(at as time.Time, dateOnly as bool) {
    if ($dateOnly) {
        return time.format($at, "%Y-%m-%d");
    }
    return time.format($at, "%Y-%m-%dT%H:%M:%S");
}
