# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - errors, and the XML text helpers every codec shares.
# Spliced into sheets.j via include - not a standalone module.

/** The `kind` every error this deck raises carries. */
export def const ERROR_KIND as string init "sheets";

/**
 * How deep a document may nest before the reader gives up.
 *
 * Descending is quadratic in depth, so a pathological file of deeply nested
 * elements costs far more than its size suggests. The cap turns that into a
 * clean error instead of an apparent hang, and keeps the failure inside this
 * deck's error contract rather than surfacing Jennifer's own recursion limit
 * as `kind: "runtime"`.
 */
export def const MAX_NESTING as int init 100;

/**
 * Raise this deck's error.
 *
 * Every refusal goes through here, so the `kind` is uniform and a caller can
 * tell a spreadsheet problem from a runtime one.
 *
 * @param message {string} what went wrong, already bounded by `quoted` if it
 *   quotes any input
 * @throws {Error} kind "sheets" always
 */
func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: $message, file: "", line: 0, col: 0};
}

/**
 * Quote a snippet of input for an error message, bounded.
 *
 * An error that quotes the offending text is far easier to act on, but a cell
 * or an attribute can hold megabytes, and an unbounded message is its own
 * denial of service. Past 48 characters this reports the length instead.
 *
 * @param text {string} the input to quote
 * @return {string} the text in double quotes, truncated with its length when
 *   it is long
 * @example
 *   quoted("A1");   # "\"A1\""
 */
func quoted(text as string) {
    if (len($text) <= 48) {
        return "\"" + $text + "\"";
    }
    return "\"" + strings.substring($text, 0, 48) + "\"... (" +
        convert.toString(len($text)) + " characters)";
}

/**
 * Refuse a document that nests past `MAX_NESTING`.
 *
 * @param depth {int} how deep the reader currently is
 * @param what {string} the construct being descended, for the message
 * @throws {Error} kind "sheets" when `depth` is past `MAX_NESTING`
 */
func checkDepth(depth as int, what as string) {
    if ($depth > MAX_NESTING) {
        fail($what + " nested more than " + convert.toString(MAX_NESTING) +
            " deep; refusing to descend further");
    }
}

/**
 * The local part of an XML tag or attribute name.
 *
 * Jennifer's `xml` keeps namespace prefixes verbatim and does not resolve
 * them, so `<table:table-row>` and `<row>` are different tags to it. The two
 * formats sit on opposite sides of that: ODS prefixes everything
 * (`table:`, `office:`, `text:`), while an XLSX worksheet uses a default
 * namespace and arrives unprefixed with only the odd attribute carrying one
 * (`r:id`). So every name this deck matches is matched on its local part.
 *
 * @param name {string} a tag or attribute name, with or without a prefix
 * @return {string} everything after the first colon, or the whole name
 * @example
 *   localName("table:table-row");   # "table-row"
 *   localName("row");               # "row"
 */
func localName(name as string) {
    def colon as int init strings.indexOf($name, ":");
    if ($colon < 0) {
        return $name;
    }
    return strings.substring($name, $colon + 1, len($name));
}

/**
 * Escape a string for XML character data or an attribute value.
 *
 * All five predefined entities are written, not the three a text node
 * strictly needs, so one function serves both positions.
 *
 * @param s {string} the text to escape
 * @return {string} the text with `& < > " '` replaced by their entities
 * @example
 *   xmlEscape("Widget & Co");   # "Widget &amp; Co"
 */
func xmlEscape(s as string) {
    def out as string init strings.replace($s, "&", "&amp;");
    $out = strings.replace($out, "<", "&lt;");
    $out = strings.replace($out, ">", "&gt;");
    $out = strings.replace($out, "\"", "&quot;");
    return strings.replace($out, "'", "&apos;");
}

/**
 * Decode the entity references in XML character data.
 *
 * The five predefined entities plus numeric character references, decimal and
 * hexadecimal. An unknown entity is **left standing** rather than raising: a
 * spreadsheet exporter writing `&nbsp;` should not make a workbook unreadable.
 *
 * @param s {string} text that may carry entity references
 * @return {string} the text with every reference this deck knows resolved
 * @example
 *   xmlUnescape("Widget &amp; Co");   # "Widget & Co"
 *   xmlUnescape("caf&#233;");         # "café"
 */
func xmlUnescape(s as string) {
    if (strings.indexOf($s, "&") < 0) {
        return $s;
    }
    def parts as list of string init strings.split($s, "&");
    def out as string init $parts[0];
    for (def i as int init 1; $i < len($parts); $i = $i + 1) {
        $out = $out + resolveReference($parts[$i]);
    }
    return $out;
}

/**
 * Resolve one entity reference, given the text that followed its `&`.
 *
 * @param part {string} everything after an `&`, reference and trailing text
 * @return {string} the replacement followed by the trailing text, or the
 *   original with its `&` restored when the reference is not understood
 */
func resolveReference(part as string) {
    def semi as int init strings.indexOf($part, ";");
    if ($semi < 0) {
        return "&" + $part;
    }
    def body as string init strings.substring($part, 0, $semi);
    def replacement as string init entityBody($body);
    if ($replacement == "") {
        return "&" + $part;
    }
    return $replacement + strings.substring($part, $semi + 1, len($part));
}

/**
 * Resolve one entity reference body, without its `&` and `;`.
 *
 * @param body {string} what stood between the `&` and the `;`
 * @return {string} the replacement, or `""` when the name is not known
 */
func entityBody(body as string) {
    if ($body == "amp") {
        return "&";
    }
    if ($body == "lt") {
        return "<";
    }
    if ($body == "gt") {
        return ">";
    }
    if ($body == "quot") {
        return "\"";
    }
    if ($body == "apos") {
        return "'";
    }
    return numericEntity($body);
}

/**
 * Resolve a numeric character reference, without its `&` and `;`.
 *
 * @param body {string} `#NN` for decimal, `#xNN` for hexadecimal
 * @return {string} the character, or `""` when the body is not a usable
 *   reference
 */
func numericEntity(body as string) {
    if (len($body) < 2 or strings.substring($body, 0, 1) != "#") {
        return "";
    }
    def digits as string init strings.substring($body, 1, len($body));
    def radix as int init 10;
    if (len($digits) > 1 and strings.lower(strings.substring($digits, 0, 1)) == "x") {
        $radix = 16;
        $digits = strings.substring($digits, 1, len($digits));
    }
    def code as int init 0;
    try {
        $code = convert.toInt($digits, $radix);
    } catch (e) {
        return "";
    }
    if ($code <= 0) {
        return "";
    }
    def out as string init "";
    try {
        $out = convert.fromCodepoint($code);
    } catch (e) {
        return "";
    }
    return $out;
}
