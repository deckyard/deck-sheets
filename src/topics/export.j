# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - one-way exports: HTML, PDF, and records as JSON.
# Spliced into sheets.j via include - not a standalone module.
#
# These are exports rather than formats: they go out and do not come back, so
# none of them has a reader. A workbook is the input and a document or a list
# of records is the output.

/**
 * How many rows an export will lay out.
 *
 * An export turns every cell into markup or a drawn line, so a large sheet
 * becomes a very large document. Past this the export refuses rather than
 * producing something nothing can open; slice the sheet first, or stream it
 * with {@link openRows} and build the document yourself.
 */
export def const MAX_EXPORT_ROWS as int init 100000;

/**
 * Render a sheet as an HTML table.
 *
 * The styles come with it, as inline CSS: the point of an HTML export is to
 * look like the sheet, and a style sheet a caller has to paste in separately
 * would not. The table carries no class names, so it inherits whatever page
 * it is dropped into.
 *
 * Cells come through their own number formats, for the same reason: a cell
 * whose format says `0.0%` shows 7.5%, not 0.075. Use `toRecords` or
 * `toJson` when a program is the reader and the value is what it wants.
 *
 * @param s {Sheet} the sheet
 * @return {string} a `<table>` element
 * @throws {Error} kind "sheets" when the sheet has more rows than `MAX_EXPORT_ROWS`
 * @example
 *   fs.writeString("out.html", toHtml(sheetByName($wb, "Q3")));
 */
export func toHtml(s as Sheet) {
    checkExportSize($s);
    def parts as list of string init [];
    $parts[] = "<table>";
    def lines as list of list of Value init rows($s);
    for (def r in 0..len($lines)) {
        $parts[] = htmlRow($s, $r, $lines[$r]);
    }
    $parts[] = "</table>";
    return strings.join($parts, "");
}

/**
 * Render a whole workbook as HTML, one table per sheet.
 *
 * Each sheet gets an `<h2>` with its name, so a multi-sheet workbook reads as
 * one page rather than a run of unlabelled tables.
 *
 * @param wb {Workbook} the workbook
 * @return {string} the sections
 * @throws {Error} kind "sheets" when a sheet is too large to lay out
 * @example
 *   fs.writeString("book.html", workbookToHtml($wb));
 */
export func workbookToHtml(wb as Workbook) {
    def parts as list of string init [];
    for (def s in $wb.sheets) {
        $parts[] = "<h2>" + xmlEscape($s.name) + "</h2>";
        $parts[] = toHtml($s);
    }
    return strings.join($parts, "");
}

/**
 * Render a sheet as a complete HTML document.
 *
 * The standalone form, for writing straight to a file. The only styling in the
 * head is what makes a table legible; everything cell-specific is inline.
 *
 * @param s {Sheet} the sheet
 * @param title {string} the document title; `""` uses the sheet's name
 * @return {string} the document
 * @throws {Error} kind "sheets" when the sheet is too large to lay out
 * @example
 *   fs.writeString("q3.html", toHtmlDocument($s, "Q3 revenue"));
 */
export func toHtmlDocument(s as Sheet, title as string) {
    def heading as string init $title;
    if ($heading == "") {
        $heading = $s.name;
    }
    def parts as list of string init [];
    $parts[] = "<!doctype html>\n<html lang=\"en\">\n<head>\n";
    $parts[] = "<meta charset=\"utf-8\">\n";
    $parts[] = "<title>" + xmlEscape($heading) + "</title>\n";
    # Raw strings: a `{` in a cooked string opens an interpolation slot, and
    # CSS is mostly braces.
    $parts[] = "<style>\n";
    $parts[] = 'table { border-collapse: collapse; font-family: system-ui, sans-serif; font-size: 14px; }';
    $parts[] = "\n";
    $parts[] = 'td { padding: 2px 8px; vertical-align: bottom; }';
    $parts[] = "\n</style>\n</head>\n<body>\n";
    $parts[] = "<h1>" + xmlEscape($heading) + "</h1>\n";
    $parts[] = toHtml($s);
    $parts[] = "\n</body>\n</html>\n";
    return strings.join($parts, "");
}

/**
 * One row as a `<tr>`.
 *
 * @param s {Sheet} the sheet, for the styles
 * @param row {int} the zero-based row index
 * @param line {list of Value} the row's values
 * @return {string} the row element
 */
func htmlRow(s as Sheet, row as int, line as list of Value) {
    def parts as list of string init [];
    $parts[] = "<tr>";
    for (def c in 0..len($line)) {
        $parts[] = htmlCell(styleAtRef($s, Ref{row: $row, col: $c}), $line[$c]);
    }
    $parts[] = "</tr>";
    return strings.join($parts, "");
}

/**
 * One cell as a `<td>`.
 *
 * @param st {Style} the cell's style
 * @param v {Value} the cell's value
 * @return {string} the cell element
 */
func htmlCell(st as Style, v as Value) {
    def css as string init htmlStyleText($st);
    # Through the cell's own number format: a page is for a person to read,
    # and a cell that says `0.0%` should say 7.5% rather than 0.075.
    def body as string init xmlEscape(applyFormat($v, $st.format));
    if ($body == "") {
        # A non-breaking space, or a styled empty cell collapses and its
        # background and borders vanish with it.
        $body = "&#160;";
    }
    if ($css == "") {
        return "<td>" + $body + "</td>";
    }
    return "<td style=\"" + $css + "\">" + $body + "</td>";
}

/**
 * A style as inline CSS.
 *
 * @param st {Style} the style
 * @return {string} the declarations, or `""` for the default style
 */
func htmlStyleText(st as Style) {
    def rules as list of string init [];
    if ($st.bold) {
        $rules[] = "font-weight:bold";
    }
    if ($st.italic) {
        $rules[] = "font-style:italic";
    }
    if ($st.underline) {
        $rules[] = "text-decoration:underline";
    }
    if ($st.fontName != "") {
        $rules[] = "font-family:" + cssSafe($st.fontName);
    }
    if ($st.fontSize > 0.0) {
        $rules[] = "font-size:" + numberAttr($st.fontSize) + "pt";
    }
    if ($st.colour != "") {
        $rules[] = "color:#" + $st.colour;
    }
    if ($st.background != "") {
        $rules[] = "background-color:#" + $st.background;
    }
    def align as string init alignToOoxml($st.align);
    if ($align != "") {
        $rules[] = "text-align:" + $align;
    }
    def valign as string init htmlVerticalAlign($st.valign);
    if ($valign != "") {
        $rules[] = "vertical-align:" + $valign;
    }
    if ($st.wrap) {
        $rules[] = "white-space:normal";
    }
    def border as string init htmlBorder($st.border);
    if ($border != "") {
        $rules[] = "border:" + $border;
    }
    return strings.join($rules, ";");
}

/**
 * A font family name with anything CSS-significant removed.
 *
 * A font name comes from a file, so it is untrusted text going into a `style`
 * attribute. Escaping the quotes is not enough - a `;` would end the
 * declaration and a `}` could end the rule - so anything but a letter, digit,
 * space or hyphen is dropped.
 *
 * @param name {string} the font family
 * @return {string} a name safe to put in a declaration
 */
func cssSafe(name as string) {
    def safe as string init "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -";
    def out as list of string init [];
    for (def ch in strings.chars($name)) {
        if (strings.indexOf($safe, $ch) >= 0) {
            $out[] = $ch;
        }
    }
    return strings.join($out, "");
}

/**
 * The CSS vertical alignment for a style's.
 *
 * @param how {VAlign} the alignment
 * @return {string} the keyword, `""` for the default
 */
func htmlVerticalAlign(how as VAlign) {
    match ($how) {
        when Top { return "top"; }
        when Middle { return "middle"; }
        when Bottom { return ""; }
    }
}

/**
 * The CSS border for a weight.
 *
 * @param weight {BorderStyle} the weight
 * @return {string} the shorthand value, `""` when there is no border
 */
func htmlBorder(weight as BorderStyle) {
    match ($weight) {
        when Thin { return "1px solid #000"; }
        when Medium { return "2px solid #000"; }
        when Thick { return "3px solid #000"; }
        when NoBorder { return ""; }
    }
}

/**
 * A sheet's rows as header-keyed records.
 *
 * The first row is the header and every row after it becomes one record keyed
 * by it, which is the shape a caller usually wants for a database insert, an
 * API payload or a `jsonl` log. A blank header cell is keyed by its column
 * name (`"C"`) so no field is silently dropped, and a duplicate header gets
 * its column name appended for the same reason.
 *
 * @param s {Sheet} the sheet
 * @return {list of map of string to string} one record per row after the first
 * @throws {Error} kind "sheets" when the sheet is too large, or has no rows
 * @example
 *   for (def r in toRecords($s)) { insert($r["Region"], $r["Revenue"]); }
 */
export func toRecords(s as Sheet) {
    checkExportSize($s);
    def lines as list of list of Value init rows($s);
    if (len($lines) == 0) {
        fail("sheet " + quoted($s.name) + " has no rows, so it has no header");
    }
    def keys as list of string init recordKeys($lines[0]);
    def out as list of map of string to string init [];
    for (def r in 1..len($lines)) {
        def record as map of string to string init {};
        for (def c in 0..len($keys)) {
            def body as string init "";
            if ($c < len($lines[$r])) {
                $body = asString($lines[$r][$c]);
            }
            $record[$keys[$c]] = $body;
        }
        $out[] = $record;
    }
    return $out;
}

/**
 * The field names a header row gives.
 *
 * @param header {list of Value} the first row
 * @return {list of string} one distinct, non-empty key per column
 */
func recordKeys(header as list of Value) {
    def out as list of string init [];
    for (def c in 0..len($header)) {
        def key as string init strings.trim(asString($header[$c]));
        def column as string init columnName($c);
        if ($key == "") {
            $key = $column;
        }
        if (stringIndex($out, $key) >= 0) {
            $key = $key + " (" + $column + ")";
        }
        $out[] = $key;
    }
    return $out;
}

/**
 * A sheet's rows as JSON records.
 *
 * The same records {@link toRecords} gives, encoded as a JSON array. Values
 * are strings, because a spreadsheet column is not typed and guessing per cell
 * would produce an array of mixed types from one column.
 *
 * @param s {Sheet} the sheet
 * @return {string} a JSON array of objects
 * @throws {Error} kind "sheets" when the sheet is too large, or has no rows
 * @example
 *   fs.writeString("rows.json", toJson($s));
 */
export func toJson(s as Sheet) {
    return json.encodePretty(toRecords($s));
}

/**
 * A sheet's rows as JSON Lines.
 *
 * One record per line, which is what a log, a stream or a bulk loader wants.
 *
 * @param s {Sheet} the sheet
 * @return {string} the records, one JSON object per line
 * @throws {Error} kind "sheets" when the sheet is too large, or has no rows
 * @example
 *   fs.writeString("rows.jsonl", toJsonLines($s));
 */
export func toJsonLines(s as Sheet) {
    def parts as list of string init [];
    for (def record in toRecords($s)) {
        $parts[] = json.encode($record);
        $parts[] = "\n";
    }
    return strings.join($parts, "");
}

/**
 * Render a sheet as a PDF.
 *
 * A table on paginated pages: the column widths follow the widest cell in
 * each column, measured with the font the page will use, and a row that does
 * not fit starts a new page with the header repeated.
 *
 * Bold and italic become the matching standard font; a background becomes a
 * filled rectangle; a border becomes drawn lines. A font family is **not**
 * honoured - embedding one needs the font file, which only the caller has.
 * Cells come through their own number formats, and the column widths are
 * measured on the formatted text rather than the raw value.
 *
 * @param s {Sheet} the sheet
 * @param size {PageSize} the paper to lay out on
 * @return {bytes} the PDF
 * @throws {Error} kind "sheets" when the sheet is too large to lay out
 * @example
 *   fs.writeBytes("q3.pdf", toPdf($s, a4()));
 */
export func toPdf(s as Sheet, size as PageSize) {
    checkExportSize($s);
    def lines as list of list of Value init rows($s);
    def widths as list of float init columnWidths($s, $lines, $size);
    def doc as pdf.Document init pdf.document();
    $doc = pdf.info($doc, "Producer", "@deckyard/sheets " + VERSION);
    $doc = pdf.info($doc, "Title", $s.name);

    def row as int init 0;
    if (len($lines) == 0) {
        return pdf.render(pdf.addPage($doc, pdf.page($size.width, $size.height)));
    }
    while ($row < len($lines)) {
        def laid as PageFill init fillPage($s, $lines, $widths, $size, $row);
        $doc = pdf.addPage($doc, $laid.page);
        $row = $laid.nextRow;
    }
    return pdf.render($doc);
}

/**
 * A page of paper, in PDF points.
 *
 * @field width {int} the width in points
 * @field height {int} the height in points
 * @field margin {int} the margin on every side, in points
 * @field fontSize {int} the text size in points
 */
export def struct PageSize {
    width as int,
    height as int,
    margin as int,
    fontSize as int
};

/**
 * A4 portrait: 595 x 842 points, a 40-point margin, 9-point text.
 *
 * @return {PageSize} the page
 * @example
 *   toPdf($s, a4());
 */
export func a4() {
    return PageSize{width: 595, height: 842, margin: 40, fontSize: 9};
}

/**
 * A4 landscape: 842 x 595 points, margin and text as {@link a4}.
 *
 * @return {PageSize} the page
 * @example
 *   toPdf($s, a4Landscape());
 */
export func a4Landscape() {
    return PageSize{width: 842, height: 595, margin: 40, fontSize: 9};
}

/**
 * US Letter portrait: 612 x 792 points, margin and text as {@link a4}.
 *
 * @return {PageSize} the page
 * @example
 *   toPdf($s, letter());
 */
export func letter() {
    return PageSize{width: 612, height: 792, margin: 40, fontSize: 9};
}

/**
 * A laid-out page and where the next one starts.
 *
 * @field page {pdf.Page} the finished page
 * @field nextRow {int} the first row that did not fit
 */
def struct PageFill {
    page as pdf.Page,
    nextRow as int
};

/**
 * Lay out as many rows as fit on one page.
 *
 * The header row is drawn again at the top of every page, because a table
 * whose columns are unlabelled after page one is not a readable table.
 *
 * @param s {Sheet} the sheet, for the styles
 * @param lines {list of list of Value} every row
 * @param widths {list of float} the column widths in points
 * @param size {PageSize} the paper
 * @param from {int} the first row to lay out
 * @return {PageFill} the page and the next row
 */
func fillPage(
    s as Sheet,
    lines as list of list of Value,
    widths as list of float,
    size as PageSize,
    from as int) {
    def page as pdf.Page init pdf.page($size.width, $size.height);
    def lineHeight as int init $size.fontSize + 6;
    def y as int init $size.height - $size.margin - $lineHeight;
    def floor as int init $size.margin;

    if ($from > 0) {
        # The header again: a table whose columns are unlabelled after page
        # one is not a readable table.
        $page = drawRow($page, $s, $lines[0], $widths, $size, 0, $y);
        $y = $y - $lineHeight;
    }
    def row as int init $from;
    while ($row < len($lines) and $y >= $floor) {
        $page = drawRow($page, $s, $lines[$row], $widths, $size, $row, $y);
        $y = $y - $lineHeight;
        $row = $row + 1;
    }
    if ($row == $from) {
        # Nothing fit, which would loop for ever. One row per page is the
        # least-bad answer for paper too small for its own margins.
        $row = $from + 1;
    }
    return PageFill{page: $page, nextRow: $row};
}

/**
 * Draw one row at a vertical position.
 *
 * @param page {pdf.Page} the page so far
 * @param s {Sheet} the sheet, for the styles
 * @param line {list of Value} the row's values
 * @param widths {list of float} the column widths in points
 * @param size {PageSize} the paper
 * @param row {int} the zero-based row index, for its styles
 * @param y {int} the baseline to draw on
 * @return {pdf.Page} a fresh page
 */
func drawRow(
    page as pdf.Page,
    s as Sheet,
    line as list of Value,
    widths as list of float,
    size as PageSize,
    row as int,
    y as int) {
    def out as pdf.Page init $page;
    def x as float init convert.toFloat($size.margin);
    for (def c in 0..len($line)) {
        def st as Style init styleAtRef($s, Ref{row: $row, col: $c});
        def width as float init 0.0;
        if ($c < len($widths)) {
            $width = $widths[$c];
        }
        $out = drawCell($out, $st, $line[$c], $size, math.round($x), $y, math.round($width));
        $x = $x + $width;
    }
    return $out;
}

/**
 * Draw one cell: its fill, its border, then its text.
 *
 * @param page {pdf.Page} the page so far
 * @param st {Style} the cell's style
 * @param v {Value} the cell's value
 * @param size {PageSize} the paper
 * @param x {int} the left edge
 * @param y {int} the baseline
 * @param width {int} the cell's width
 * @return {pdf.Page} a fresh page
 */
func drawCell(
    page as pdf.Page,
    st as Style,
    v as Value,
    size as PageSize,
    x as int,
    y as int,
    width as int) {
    def out as pdf.Page init $page;
    def height as int init $size.fontSize + 6;
    if ($st.background != "") {
        $out = pdf.color(
            $out,
            hexByte($st.background, 0),
            hexByte($st.background, 2),
            hexByte($st.background, 4));
        $out = pdf.rect($out, $x, $y - 3, $width, $height, true);
        $out = pdf.color($out, 0, 0, 0);
    }
    if (borderToOoxml($st.border) != "") {
        $out = pdf.rect($out, $x, $y - 3, $width, $height, false);
    }
    # As in the HTML export, through the cell's own number format.
    def body as string init applyFormat($v, $st.format);
    if ($body == "") {
        return $out;
    }
    if ($st.colour != "") {
        $out = pdf.color(
            $out,
            hexByte($st.colour, 0),
            hexByte($st.colour, 2),
            hexByte($st.colour, 4));
    }
    def fontName as string init pdfFont($st);
    def shown as string init fitText($body, $fontName, $size.fontSize, $width - 6);
    $out = pdf.text(
        $out,
        $x + 3 + textOffset($st, $shown, $fontName, $size, $width),
        $y,
        $fontName,
        $size.fontSize,
        $shown);
    if ($st.colour != "") {
        $out = pdf.color($out, 0, 0, 0);
    }
    return $out;
}

/**
 * Which standard font a style maps to.
 *
 * The standard fourteen have one face per weight and slant, so bold and
 * italic become a different font rather than a property. A font *family* is
 * not honoured: embedding one needs the font file, which only the caller has.
 *
 * @param st {Style} the style
 * @return {string} a standard-14 font name
 */
func pdfFont(st as Style) {
    if ($st.bold and $st.italic) {
        return "Helvetica-BoldOblique";
    }
    if ($st.bold) {
        return "Helvetica-Bold";
    }
    if ($st.italic) {
        return "Helvetica-Oblique";
    }
    return "Helvetica";
}

/**
 * How far to indent a cell's text for its alignment.
 *
 * @param st {Style} the cell's style
 * @param body {string} the text being drawn
 * @param fontName {string} the font it is drawn in
 * @param size {PageSize} the paper
 * @param width {int} the cell's width
 * @return {int} the offset from the cell's left padding
 */
func textOffset(st as Style, body as string, fontName as string, size as PageSize, width as int) {
    def span as float init pdf.measureText($fontName, $size.fontSize, $body);
    def room as float init convert.toFloat($width - 6) - $span;
    if ($room <= 0.0) {
        return 0;
    }
    match ($st.align) {
        when Right { return math.round($room); }
        when Centre { return math.round($room / 2.0); }
        else { return 0; }
    }
}

/**
 * Cut text to what fits a width, with an ellipsis when it was cut.
 *
 * Truncating is the honest answer for a fixed table cell: wrapping would push
 * every later row down by an amount the column widths were not computed for.
 *
 * @param body {string} the text
 * @param fontName {string} the font
 * @param fontSize {int} the size in points
 * @param room {int} the width available
 * @return {string} the text, cut if it had to be
 */
func fitText(body as string, fontName as string, fontSize as int, room as int) {
    if ($room <= 0) {
        return "";
    }
    if (pdf.measureText($fontName, $fontSize, $body) <= convert.toFloat($room)) {
        return $body;
    }
    def chars as list of string init strings.chars($body);
    def keep as int init len($chars);
    while ($keep > 0) {
        def candidate as string init strings.join($chars[0..$keep], "") + "...";
        if (pdf.measureText($fontName, $fontSize, $candidate) <=
            convert.toFloat($room)) {
            return $candidate;
        }
        $keep = $keep - 1;
    }
    return "";
}

/**
 * The column widths a sheet's content asks for.
 *
 * Measured from the widest cell in each column rather than divided evenly, so
 * a column of dates does not get the same room as a column of notes. The
 * total is then scaled to the page, which is what stops a wide sheet running
 * off the paper.
 *
 * @param s {Sheet} the sheet, for the styles
 * @param lines {list of list of Value} every row
 * @param size {PageSize} the paper
 * @return {list of float} one width per column, in points
 */
func columnWidths(s as Sheet, lines as list of list of Value, size as PageSize) {
    def out as list of float init [];
    for (def c in 0..$s.colCount) {
        $out[] = widestInColumn($s, $lines, $size, $c) + 8.0;
    }
    return scaleToPage($out, $size);
}

/**
 * How wide the widest cell of one column draws.
 *
 * @param s {Sheet} the sheet, for the styles
 * @param lines {list of list of Value} every row
 * @param size {PageSize} the paper
 * @param col {int} the zero-based column index
 * @return {float} the width in points
 */
func widestInColumn(s as Sheet, lines as list of list of Value, size as PageSize, col as int) {
    def widest as float init 0.0;
    for (def r in 0..len($lines)) {
        def span as float init cellTextWidth($s, $lines[$r], $size, $r, $col);
        if ($span > $widest) {
            $widest = $span;
        }
    }
    return $widest;
}

/**
 * How wide one cell's text draws.
 *
 * @param s {Sheet} the sheet, for the styles
 * @param line {list of Value} the row's values
 * @param size {PageSize} the paper
 * @param row {int} the zero-based row index
 * @param col {int} the zero-based column index
 * @return {float} the width in points, `0.0` past the end of the row
 */
func cellTextWidth(s as Sheet, line as list of Value, size as PageSize, row as int, col as int) {
    if ($col >= len($line)) {
        return 0.0;
    }
    def st as Style init styleAtRef($s, Ref{row: $row, col: $col});
    # The formatted text, or a column sized for `0.075` would clip `7.5%`.
    return pdf.measureText(pdfFont($st), $size.fontSize, applyFormat($line[$col], $st.format));
}

/**
 * Scale column widths so they fit the page.
 *
 * @param widths {list of float} the widths the content asks for
 * @param size {PageSize} the paper
 * @return {list of float} the widths, scaled down if they did not fit
 */
func scaleToPage(widths as list of float, size as PageSize) {
    def room as float init convert.toFloat($size.width - 2 * $size.margin);
    def total as float init 0.0;
    for (def w in $widths) {
        $total = $total + $w;
    }
    if ($total <= $room or $total <= 0.0) {
        return $widths;
    }
    def factor as float init $room / $total;
    def out as list of float init [];
    for (def w in $widths) {
        $out[] = $w * $factor;
    }
    return $out;
}

/**
 * One byte of a hexadecimal colour, as 0 to 255.
 *
 * @param rgb {string} the colour as six hexadecimal digits
 * @param at {int} the first digit of the pair
 * @return {int} the value, or 0 when unreadable
 */
func hexByte(rgb as string, at as int) {
    if ($at + 2 > len($rgb)) {
        return 0;
    }
    def out as int init 0;
    try {
        $out = convert.toInt(strings.substring($rgb, $at, $at + 2), 16);
    } catch (e) {
        return 0;
    }
    return $out;
}

/**
 * Refuse a sheet too large to lay out.
 *
 * @param s {Sheet} the sheet
 * @throws {Error} kind "sheets" when it has more rows than `MAX_EXPORT_ROWS`
 */
func checkExportSize(s as Sheet) {
    if ($s.rowCount > MAX_EXPORT_ROWS) {
        fail("sheet " + quoted($s.name) + " has " + convert.toString($s.rowCount) +
            " rows, past the " + convert.toString(MAX_EXPORT_ROWS) +
            " an export will lay out; slice it, or stream it with openRows " +
            "and build the document yourself");
    }
}
