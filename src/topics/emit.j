# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the XML text the writers assemble documents from.
# Spliced into sheets.j via include - not a standalone module.
#
# Every function here returns a string and holds no state. That is the whole
# design, and it is the second attempt: the first wrapped the pieces in an
# `Emitter` struct that each builder took and returned. Under value semantics
# that copies the accumulated list on every call, so writing a document was
# quadratic in its own length - 8 000 appends measured 14 792 ms threaded
# against 4 ms appending into a local list. Writing an ODS of 400 rows took
# 12.1 s.
#
# So the rule a writer follows is: keep the `list of string` as a local, append
# into it with `$parts[] = ...` (amortised O(1) in place), and call these to
# build each piece. A helper may return a piece or a whole joined subtree, but
# it must never be handed the accumulator.

/** The XML declaration both formats open every part with. */
def const XML_DECLARATION as string init "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>";

/**
 * An opening tag with no attributes.
 *
 * @param tag {string} the tag name, prefix and all
 * @return {string} the opening tag
 * @example
 *   tagOpen("sheetData");   # "<sheetData>"
 */
func tagOpen(tag as string) {
    return "<" + $tag + ">";
}

/**
 * An opening tag with attributes.
 *
 * Attribute values are escaped. The order is the map's, which is
 * insertion-ordered, so a writer controls how the output reads and a golden
 * file stays stable.
 *
 * @param tag {string} the tag name, prefix and all
 * @param attrs {map of string to string} the attributes
 * @return {string} the opening tag
 * @example
 *   tagOpenWith("row", {"r": "1"});   # "<row r=\"1\">"
 */
func tagOpenWith(tag as string, attrs as map of string to string) {
    return "<" + $tag + attributeText($attrs) + ">";
}

/**
 * A self-closed tag with attributes.
 *
 * @param tag {string} the tag name, prefix and all
 * @param attrs {map of string to string} the attributes
 * @return {string} the element
 * @example
 *   tagEmpty("dimension", {"ref": "A1:C4"});
 */
func tagEmpty(tag as string, attrs as map of string to string) {
    return "<" + $tag + attributeText($attrs) + "/>";
}

/**
 * A closing tag.
 *
 * @param tag {string} the tag name, prefix and all
 * @return {string} the closing tag
 * @example
 *   tagClose("sheetData");   # "</sheetData>"
 */
func tagClose(tag as string) {
    return "</" + $tag + ">";
}

/**
 * An element holding one piece of escaped text.
 *
 * The common leaf: `<t>Name</t>`, `<text:p>Name</text:p>`.
 *
 * @param tag {string} the tag name, prefix and all
 * @param body {string} the character data
 * @return {string} the element
 * @example
 *   tagText("text:p", "Widget & Co");   # "<text:p>Widget &amp; Co</text:p>"
 */
func tagText(tag as string, body as string) {
    return "<" + $tag + ">" + xmlEscape($body) + tagClose($tag);
}

/**
 * An element with attributes holding one piece of escaped text.
 *
 * @param tag {string} the tag name, prefix and all
 * @param attrs {map of string to string} the attributes
 * @param body {string} the character data
 * @return {string} the element
 * @example
 *   tagTextWith("t", {"xml:space": "preserve"}, " padded ");
 */
func tagTextWith(tag as string, attrs as map of string to string, body as string) {
    return "<" + $tag + attributeText($attrs) + ">" + xmlEscape($body) +
        tagClose($tag);
}

/**
 * Render an attribute list, each value escaped.
 *
 * @param attrs {map of string to string} the attributes
 * @return {string} the rendered attributes, each preceded by a space
 */
func attributeText(attrs as map of string to string) {
    if (len($attrs) == 0) {
        return "";
    }
    def out as list of string init [];
    for (def name in $attrs) {
        $out[] = " " + $name + "=\"" + xmlEscape($attrs[$name]) + "\"";
    }
    return strings.join($out, "");
}

/**
 * A finished document, as UTF-8 bytes.
 *
 * One join over every piece, which is the point of collecting them.
 *
 * @param parts {list of string} the pieces, in order
 * @return {bytes} the document
 * @example
 *   return partsBytes($parts);
 */
func partsBytes(parts as list of string) {
    return convert.bytesFromString(strings.join($parts, ""), "utf-8");
}
