# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - how a cell looks: fonts, colours, alignment, borders, formats.
# Spliced into sheets.j via include - not a standalone module.

/**
 * How a cell's contents sit horizontally.
 *
 * `General` is the format's own default, which both applications render as
 * text to the left and numbers to the right. It is not the same as `Left`.
 */
export def enum Align {
    General,
    Left,
    Centre,
    Right
};

/** How a cell's contents sit vertically. */
export def enum VAlign {
    Bottom,
    Middle,
    Top
};

/**
 * How one edge of a cell is drawn.
 *
 * The four weights both formats agree on. Anything more exotic - dashed,
 * dotted, a double rule of a chosen colour - is not carried, and reads back
 * as the nearest of these.
 */
export def enum BorderStyle {
    NoBorder,
    Thin,
    Medium,
    Thick
};

/**
 * How a cell looks.
 *
 * The builders copy and return rather than mutate:
 * `$st = withBold(style(), true)`. Two styles that look the same are equal,
 * which lets a sheet intern them into a table instead of holding one per cell.
 *
 * The empty strings and zeroes are "say nothing", not "say this": a `Style`
 * with no font name does not write a font name, so a cell inherits whatever
 * the application's default is rather than being pinned to this deck's idea
 * of one.
 *
 * @field bold {bool} whether the text is bold
 * @field italic {bool} whether the text is italic
 * @field underline {bool} whether the text is underlined
 * @field fontName {string} the font family, `""` for the default
 * @field fontSize {float} the size in points, `0.0` for the default
 * @field colour {string} the text colour as `"RRGGBB"`, `""` for the default
 * @field background {string} the fill colour as `"RRGGBB"`, `""` for none
 * @field align {Align} how the contents sit horizontally
 * @field valign {VAlign} how the contents sit vertically
 * @field wrap {bool} whether long text wraps inside the cell
 * @field border {BorderStyle} the weight drawn on all four edges
 * @field format {string} the number format code, `""` for the general format
 */
export def struct Style {
    bold as bool,
    italic as bool,
    underline as bool,
    fontName as string,
    fontSize as float,
    colour as string,
    background as string,
    align as Align,
    valign as VAlign,
    wrap as bool,
    border as BorderStyle,
    format as string
};

/**
 * The default style: everything left to the application.
 *
 * The starting point for the builders, and the style every cell has until one
 * is set on it.
 *
 * @return {Style} the default style
 * @example
 *   def st as Style init style();
 */
export func style() {
    return Style{
        bold: false,
        italic: false,
        underline: false,
        fontName: "",
        fontSize: 0.0,
        colour: "",
        background: "",
        align: Align.General,
        valign: VAlign.Bottom,
        wrap: false,
        border: BorderStyle.NoBorder,
        format: ""
    };
}

/**
 * Whether a style says nothing at all.
 *
 * A cell with the default style needs no style written for it, which is what
 * keeps a plain sheet's style tables empty.
 *
 * @param st {Style} the style
 * @return {bool} whether it is the default
 * @example
 *   isPlain(style());   # true
 */
export func isPlain(st as Style) {
    return $st == style();
}

/**
 * The same style, bold or not.
 *
 * @param st {Style} the style
 * @param on {bool} whether the text is bold
 * @return {Style} a fresh style
 * @example
 *   $st = withBold(style(), true);
 */
export func withBold(st as Style, on as bool) {
    def out as Style init $st;
    $out.bold = $on;
    return $out;
}

/**
 * The same style, italic or not.
 *
 * @param st {Style} the style
 * @param on {bool} whether the text is italic
 * @return {Style} a fresh style
 * @example
 *   $st = withItalic($st, true);
 */
export func withItalic(st as Style, on as bool) {
    def out as Style init $st;
    $out.italic = $on;
    return $out;
}

/**
 * The same style, underlined or not.
 *
 * @param st {Style} the style
 * @param on {bool} whether the text is underlined
 * @return {Style} a fresh style
 * @example
 *   $st = withUnderline($st, true);
 */
export func withUnderline(st as Style, on as bool) {
    def out as Style init $st;
    $out.underline = $on;
    return $out;
}

/**
 * The same style with a font family and size.
 *
 * An empty name or a size of zero leaves that half to the application, so
 * `withFont($st, "", 12.0)` sets the size and not the family.
 *
 * @param st {Style} the style
 * @param name {string} the font family, `""` to leave it alone
 * @param size {float} the size in points, `0.0` to leave it alone
 * @return {Style} a fresh style
 * @throws {Error} kind "sheets" when the size is negative or above 4000 points
 * @example
 *   $st = withFont($st, "Calibri", 11.0);
 */
export func withFont(st as Style, name as string, size as float) {
    if ($size < 0.0 or $size > 4000.0) {
        fail("font size " + convert.toString($size) +
            " is outside the 0 to 4000 points a spreadsheet accepts");
    }
    def out as Style init $st;
    $out.fontName = $name;
    $out.fontSize = $size;
    return $out;
}

/**
 * The same style with a text colour.
 *
 * @param st {Style} the style
 * @param rgb {string} the colour as `"RRGGBB"`, `""` for the default
 * @return {Style} a fresh style
 * @throws {Error} kind "sheets" when the colour is not six hexadecimal digits
 * @example
 *   $st = withColour($st, "CC0000");
 */
export func withColour(st as Style, rgb as string) {
    def out as Style init $st;
    $out.colour = checkedColour($rgb, "text colour");
    return $out;
}

/**
 * The same style with a background fill.
 *
 * @param st {Style} the style
 * @param rgb {string} the colour as `"RRGGBB"`, `""` for no fill
 * @return {Style} a fresh style
 * @throws {Error} kind "sheets" when the colour is not six hexadecimal digits
 * @example
 *   $st = withBackground($st, "FFF2CC");
 */
export func withBackground(st as Style, rgb as string) {
    def out as Style init $st;
    $out.background = checkedColour($rgb, "background colour");
    return $out;
}

/**
 * Normalise and check a colour.
 *
 * Accepts `"RRGGBB"` and the `"#RRGGBB"` spelling a caller is likely to have
 * to hand, and returns the former in upper case so that two spellings of one
 * colour intern to one style.
 *
 * @param rgb {string} the colour as written
 * @param what {string} the field being set, for the message
 * @return {string} the colour as six upper-case hexadecimal digits, or `""`
 * @throws {Error} kind "sheets" when the text is not a colour
 */
func checkedColour(rgb as string, what as string) {
    def body as string init strings.trim($rgb);
    if (strings.startsWith($body, "#")) {
        $body = strings.substring($body, 1, len($body));
    }
    if ($body == "") {
        return "";
    }
    if (len($body) != 6) {
        fail($what + " " + quoted($rgb) + " is not six hexadecimal digits");
    }
    def upper as string init strings.upper($body);
    for (def ch in strings.chars($upper)) {
        if (strings.indexOf("0123456789ABCDEF", $ch) < 0) {
            fail($what + " " + quoted($rgb) + " is not six hexadecimal digits");
        }
    }
    return $upper;
}

/**
 * The same style with a horizontal alignment.
 *
 * @param st {Style} the style
 * @param how {Align} where the contents sit
 * @return {Style} a fresh style
 * @example
 *   $st = withAlign($st, Align.Centre);
 */
export func withAlign(st as Style, how as Align) {
    def out as Style init $st;
    $out.align = $how;
    return $out;
}

/**
 * The same style with a vertical alignment.
 *
 * @param st {Style} the style
 * @param how {VAlign} where the contents sit
 * @return {Style} a fresh style
 * @example
 *   $st = withVerticalAlign($st, VAlign.Middle);
 */
export func withVerticalAlign(st as Style, how as VAlign) {
    def out as Style init $st;
    $out.valign = $how;
    return $out;
}

/**
 * The same style, wrapping long text or not.
 *
 * @param st {Style} the style
 * @param on {bool} whether text wraps inside the cell
 * @return {Style} a fresh style
 * @example
 *   $st = withWrap($st, true);
 */
export func withWrap(st as Style, on as bool) {
    def out as Style init $st;
    $out.wrap = $on;
    return $out;
}

/**
 * The same style with a border on all four edges.
 *
 * Per-edge borders are not carried: both formats allow them, but a model that
 * does needs four more fields and a reader that resolves four inherited
 * edges, and the common case by far is a box or nothing.
 *
 * @param st {Style} the style
 * @param weight {BorderStyle} how the edges are drawn
 * @return {Style} a fresh style
 * @example
 *   $st = withBorder($st, BorderStyle.Thin);
 */
export func withBorder(st as Style, weight as BorderStyle) {
    def out as Style init $st;
    $out.border = $weight;
    return $out;
}

/**
 * The same style with a number format code.
 *
 * The code is the one both formats use: `#,##0.00`, `yyyy-mm-dd`, `0%`, and
 * the `;`-separated positive/negative/zero/text sections. It is carried
 * through a read and a write unchanged.
 *
 * Setting a code does not change what `asString` returns, which is always the
 * plain value. {@link applyFormat} and {@link displayAt} render a value
 * through its code.
 *
 * @param st {Style} the style
 * @param code {string} the number format code, `""` or `"General"` for none
 * @return {Style} a fresh style
 * @example
 *   $st = withFormat($st, "#,##0.00");
 *   $st = withFormat($st, "yyyy-mm-dd");
 */
export func withFormat(st as Style, code as string) {
    def out as Style init $st;
    $out.format = normalisedFormat($code);
    return $out;
}

/**
 * A format code with the ways of saying "no format" reduced to one.
 *
 * `General` *is* the absence of a format - it is what a file writes for a
 * cell that has none - so carrying it as a code made the three writers
 * disagree about what to do with it. XLSX wrote it back verbatim, Gnumeric
 * dropped it, and ODF had no component for it and wrote it as a **literal**,
 * so the cell displayed the word "General" instead of the number.
 *
 * Every entry point goes through here: the builder, and each reader as it
 * takes a code out of a file.
 *
 * @param code {string} the code as given or as a file spells it
 * @return {string} the code, or `""` when it means no format at all
 */
func normalisedFormat(code as string) {
    def trimmed as string init strings.trim($code);
    if (strings.lower($trimmed) == "general") {
        return "";
    }
    return $trimmed;
}

/**
 * Whether a style's number format describes a date.
 *
 * In XLSX a date is a number, and only its format says otherwise. Uses the
 * same scan the reader applies to a file's own format codes.
 *
 * @param st {Style} the style
 * @return {bool} whether the format is a date or time format
 * @example
 *   isDateFormat(withFormat(style(), "yyyy-mm-dd"));   # true
 */
export func isDateFormat(st as Style) {
    if ($st.format == "") {
        return false;
    }
    return looksLikeDateFormat($st.format);
}

/**
 * The alignment a format's own name for it maps to.
 *
 * Shared by the readers, which spell the alignments differently (`center`
 * in OOXML and ODF, `GNM_HALIGN_CENTER` in Gnumeric, `start` and `end` in
 * ODF), so the match is on the tail of whatever was written.
 *
 * @param name {string} the alignment as the file spells it
 * @return {Align} the alignment, `General` when it is not recognised
 */
func alignFromName(name as string) {
    def word as string init strings.lower(strings.trim($name));
    if (strings.endsWith($word, "left") or strings.endsWith($word, "start")) {
        return Align.Left;
    }
    if (strings.endsWith($word, "center") or strings.endsWith($word, "centre")) {
        return Align.Centre;
    }
    if (strings.endsWith($word, "right") or strings.endsWith($word, "end")) {
        return Align.Right;
    }
    return Align.General;
}

/**
 * The vertical alignment a format's own name for it maps to.
 *
 * @param name {string} the alignment as the file spells it
 * @return {VAlign} the alignment, `Bottom` when it is not recognised
 */
func valignFromName(name as string) {
    def word as string init strings.lower(strings.trim($name));
    if (strings.endsWith($word, "top")) {
        return VAlign.Top;
    }
    if (strings.endsWith($word, "middle") or strings.endsWith($word, "center")) {
        return VAlign.Middle;
    }
    return VAlign.Bottom;
}

/**
 * The border weight a format's own name for it maps to.
 *
 * Anything this deck does not carry - dashed, dotted, double - lands on the
 * nearest weight rather than being dropped, so a box drawn in another
 * application survives as a box.
 *
 * @param name {string} the border style as the file spells it
 * @return {BorderStyle} the weight, `NoBorder` when it is absent or none
 */
func borderFromName(name as string) {
    def word as string init strings.lower(strings.trim($name));
    if ($word == "" or $word == "none" or strings.startsWith($word, "0")) {
        return BorderStyle.NoBorder;
    }
    if (strings.contains($word, "thick")) {
        return BorderStyle.Thick;
    }
    if (strings.contains($word, "medium") or strings.contains($word, "double")) {
        return BorderStyle.Medium;
    }
    return BorderStyle.Thin;
}

/**
 * The `Align` as OOXML spells it.
 *
 * @param how {Align} the alignment
 * @return {string} the attribute value, `""` for the general alignment
 */
func alignToOoxml(how as Align) {
    match ($how) {
        when Left { return "left"; }
        when Centre { return "center"; }
        when Right { return "right"; }
        when General { return ""; }
    }
}

/**
 * The `VAlign` as OOXML spells it.
 *
 * @param how {VAlign} the alignment
 * @return {string} the attribute value, `""` for the default
 */
func valignToOoxml(how as VAlign) {
    match ($how) {
        when Top { return "top"; }
        when Middle { return "center"; }
        when Bottom { return ""; }
    }
}

/**
 * The `Align` as ODF spells it.
 *
 * @param how {Align} the alignment
 * @return {string} the attribute value, `""` for the general alignment
 */
func alignToOdf(how as Align) {
    match ($how) {
        when Left { return "start"; }
        when Centre { return "center"; }
        when Right { return "end"; }
        when General { return ""; }
    }
}

/**
 * The `VAlign` as ODF spells it.
 *
 * @param how {VAlign} the alignment
 * @return {string} the attribute value, `""` for the default
 */
func valignToOdf(how as VAlign) {
    match ($how) {
        when Top { return "top"; }
        when Middle { return "middle"; }
        when Bottom { return ""; }
    }
}

/**
 * The border weight as OOXML spells it.
 *
 * @param weight {BorderStyle} the weight
 * @return {string} the style value, `""` when there is no border
 */
func borderToOoxml(weight as BorderStyle) {
    match ($weight) {
        when Thin { return "thin"; }
        when Medium { return "medium"; }
        when Thick { return "thick"; }
        when NoBorder { return ""; }
    }
}

/**
 * The border weight as an ODF stroke width.
 *
 * ODF has no named weights: a border is a width, a style and a colour in one
 * attribute value, so the weights become the three widths applications draw
 * for them.
 *
 * @param weight {BorderStyle} the weight
 * @return {string} the `fo:border` value, `""` when there is no border
 */
func borderToOdf(weight as BorderStyle) {
    match ($weight) {
        when Thin { return "0.5pt solid #000000"; }
        when Medium { return "1pt solid #000000"; }
        when Thick { return "2pt solid #000000"; }
        when NoBorder { return ""; }
    }
}
