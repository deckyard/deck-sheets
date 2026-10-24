# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the element scanner the XML codecs walk a document with.
# Spliced into sheets.j via include - not a standalone module.
#
# Started life in @deckyard/geo, which solved the same problem for GPX and KML,
# and is now this deck's own: the tuning below is for the shapes a workbook
# has, and the two copies are free to diverge. Needs fail, localName and
# xmlUnescape from core.j.

/**
 * Where one element sits in a buffer.
 *
 * Byte offsets into the buffer the scanner was handed, not rune offsets:
 * `binary.indexOf` works in bytes and scans at native speed, where
 * `strings.indexOf` would have to decode the whole document to count runes.
 *
 * @field name {string} the tag as written, namespace prefix and all
 * @field start {int} the offset of the opening `<`
 * @field end {int} the offset just past the element
 * @field openEnd {int} the offset just past the `>` of the open tag
 * @field innerEnd {int} the offset of the `<` that closes the element
 * @field closed {bool} whether a closing tag was found
 */
def struct Node {
    name as string,
    start as int,
    end as int,
    openEnd as int,
    innerEnd as int,
    closed as bool
};

/** The byte value of `<`. */
def const LT as int init 0x3c;

# The one-byte needles below are what turn the scan from an interpreted loop
# per byte into one `binary.indexOf` per element: `binary` scans at native
# speed, and `bytes` has no literal, so each probe is built once here rather
# than converted on every call.

/** `<` as a one-byte buffer, for `binary.indexOf`. */
def const LT_PROBE as bytes init convert.bytesFromString("<", "utf-8");

/** `>` as a one-byte buffer. */
def const GT_PROBE as bytes init convert.bytesFromString(">", "utf-8");

/** A double quote as a one-byte buffer. */
def const DQUOTE_PROBE as bytes init convert.bytesFromString("\"", "utf-8");

/** A single quote as a one-byte buffer. */
def const SQUOTE_PROBE as bytes init convert.bytesFromString("'", "utf-8");

/** The opening of a CDATA section. */
def const CDATA_PROBE as bytes init convert.bytesFromString("<![CDATA[", "utf-8");

/** The opening of a comment. */
def const COMMENT_PROBE as bytes init convert.bytesFromString("<!--", "utf-8");

/** The byte value of `>`. */
def const GT as int init 0x3e;

/** The byte value of `/`. */
def const SLASH as int init 0x2f;

/** The byte value of `!`. */
def const BANG as int init 0x21;

/** The byte value of `?`. */
def const QUESTION as int init 0x3f;

/**
 * Whether a byte ends an XML name.
 *
 * Whitespace, `>` and `/` are the only things that can follow a tag name, so
 * this is what tells `<row>` from `<rowBreaks>` without a regex.
 *
 * @param b {int} the byte to test
 * @return {bool} whether the byte terminates a name
 */
func isNameEnd(b as int) {
    return $b == GT or $b == SLASH or $b == 0x20 or $b == 0x09 or $b == 0x0a or $b == 0x0d;
}

/**
 * The next direct element child at or after an offset.
 *
 * The streaming half of the scanner, and the reason a sheet of any size
 * costs the same memory as a short one. {@link childNodes} is the convenient
 * form, but it materialises a list - and a `<sheetData>` has as many children
 * as the sheet has rows, so for 50,000 rows that list is the largest thing in
 * the program. A reader that only ever holds one child at a time walks the same
 * document in a fraction of the memory.
 *
 * Comments, processing instructions, `DOCTYPE` declarations and CDATA sections
 * are skipped.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {Node} the next child, or a node with `start` `-1` when there is none
 * @example
 *   def at as int init $node.openEnd;
 *   def child as Node init nextChild($src, $at, $node.innerEnd);
 *   while (isNode($child)) {
 *       $child = nextChild($src, $child.end, $node.innerEnd);
 *   }
 */
func nextChild(src as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def lt as int init indexOfByte($src, LT_PROBE, $at, $limit);
        if ($lt < 0) {
            return missingNode();
        }
        def skip as int init skipNonElement($src, $lt, $limit);
        if ($skip >= 0) {
            $at = $skip;
        } else {
            def node as Node init readNode($src, $lt, $limit);
            if ($node.start < 0) {
                return missingNode();
            }
            return $node;
        }
    }
    return missingNode();
}

/**
 * The direct element children of a byte range, as a list.
 *
 * Convenient where the count is small and known to be - a document's header, a
 * row's cells. For the children of a `<sheetData>` or an ODS `<table:table>`,
 * which can number in the tens of thousands, walk them with
 * {@link nextChild} instead.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {list of Node} the direct children, in document order
 */
func childNodes(src as bytes, from as int, limit as int) {
    def out as list of Node init [];
    def child as Node init nextChild($src, $from, $limit);
    while (isNode($child)) {
        $out[] = $child;
        $child = nextChild($src, $child.end, $limit);
    }
    return $out;
}

/**
 * A node that points at nothing.
 *
 * @return {Node} a node whose `start` is `-1`
 */
func missingNode() {
    return Node{name: "", start: -1, end: 0, openEnd: 0, innerEnd: 0, closed: false};
}

/**
 * Step over a comment, processing instruction, DOCTYPE, CDATA or close tag.
 *
 * @param src {bytes} the whole document
 * @param lt {int} the offset of a `<`
 * @param limit {int} the offset to stop at
 * @return {int} where to resume, or `-1` when the `<` opens an element
 */
func skipNonElement(src as bytes, lt as int, limit as int) {
    if ($lt + 1 >= $limit) {
        return $limit;
    }
    def next as int init $src[$lt + 1];
    if ($next == SLASH) {
        return skipPast($src, $lt, ">", $limit);
    }
    if ($next == QUESTION) {
        return skipPast($src, $lt, "?>", $limit);
    }
    if ($next != BANG) {
        return -1;
    }
    if (matchesAt($src, $lt, CDATA_PROBE)) {
        return skipPast($src, $lt, "]]>", $limit);
    }
    if (matchesAt($src, $lt, COMMENT_PROBE)) {
        return skipPast($src, $lt, "-->", $limit);
    }
    return skipPast($src, $lt, ">", $limit);
}

/**
 * Read the element that starts at a `<`.
 *
 * An element with no closing tag is taken to run to `limit` rather than being
 * discarded, so a truncated document yields what it did manage to write. An
 * element whose *open tag* is truncated carries no usable name or attributes,
 * and comes back as a missing node.
 *
 * @param src {bytes} the whole document
 * @param lt {int} the offset of the opening `<`
 * @param limit {int} the offset to stop at
 * @return {Node} the element, or a node with `start` `-1` when its open tag is unterminated
 */
func readNode(src as bytes, lt as int, limit as int) {
    def nameEnd as int init $lt + 1;
    while ($nameEnd < $limit and not isNameEnd($src[$nameEnd])) {
        $nameEnd = $nameEnd + 1;
    }
    def name as string init byteText($src, $lt + 1, $nameEnd);
    def openEnd as int init endOfOpenTag($src, $nameEnd, $limit);
    if ($openEnd < 0) {
        return Node{
            name: $name,
            start: -1,
            end: $limit,
            openEnd: $limit,
            innerEnd: $limit,
            closed: false
        };
    }
    if ($src[$openEnd - 2] == SLASH) {
        # <c ... /> - no content, so the element ends where its open tag does
        return Node{
            name: $name,
            start: $lt,
            end: $openEnd,
            openEnd: $openEnd,
            innerEnd: $openEnd - 2,
            closed: true
        };
    }
    def innerEnd as int init matchingClose($src, $name, $openEnd, $limit);
    if ($innerEnd < 0) {
        # No closing tag: a file whose write was cut short - a recorder that
        # was truncated mid-write. The element is taken to run to the end of what
        # there is, so the points before the damage still read back. Only a
        # truncated *open tag*, below, is unusable.
        return Node{
            name: $name,
            start: $lt,
            end: $limit,
            openEnd: $openEnd,
            innerEnd: $limit,
            closed: false
        };
    }
    def closeLen as int init len($name) + 3;
    return Node{
        name: $name,
        start: $lt,
        end: $innerEnd + $closeLen,
        openEnd: $openEnd,
        innerEnd: $innerEnd,
        closed: true
    };
}

/**
 * The offset just past the `>` that ends an open tag.
 *
 * Quoted attribute values are stepped over, so a `>` inside one does not end
 * the tag. Driven by native searches for `>` and for the quotes, so the cost
 * is one hop per quoted attribute rather than one step per byte.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset just past the tag name
 * @param limit {int} the offset to stop at
 * @return {int} the offset just past the `>`, or `-1` when there is none
 */
func endOfOpenTag(src as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def gt as int init indexOfByte($src, GT_PROBE, $at, $limit);
        if ($gt < 0) {
            return -1;
        }
        def quote as int init nextQuote($src, $at, $gt);
        if ($quote < 0) {
            return $gt + 1;
        }
        # The `>` is inside an attribute value; resume past the closing quote.
        # Both branches pass the probe constant straight to indexOfByte: binding
        # a `def const` of a compound type to a local deep-copies it, and this
        # runs twice per element.
        def close as int init closingQuote($src, $quote, $limit);
        if ($close < 0) {
            return -1;
        }
        $at = $close + 1;
    }
    return -1;
}

/**
 * The offset of the quote that closes the one at an offset.
 *
 * @param src {bytes} the buffer to search
 * @param quote {int} the offset of the opening quote
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the closing quote, or `-1` when there is none
 */
func closingQuote(src as bytes, quote as int, limit as int) {
    if ($src[$quote] == 0x22) {
        return indexOfByte($src, DQUOTE_PROBE, $quote + 1, $limit);
    }
    return indexOfByte($src, SQUOTE_PROBE, $quote + 1, $limit);
}

/**
 * The offset of the first quote character before a limit.
 *
 * @param src {bytes} the buffer to search
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the nearer quote, or `-1` when there is none
 */
func nextQuote(src as bytes, from as int, limit as int) {
    def double as int init indexOfByte($src, DQUOTE_PROBE, $from, $limit);
    def single as int init indexOfByte($src, SQUOTE_PROBE, $from, $limit);
    if ($double < 0) {
        return $single;
    }
    if ($single < 0) {
        return $double;
    }
    return math.min($double, $single);
}

/**
 * The offset of the `</name>` that closes an element, counting nesting.
 *
 * @param src {bytes} the whole document
 * @param name {string} the tag as written
 * @param from {int} the offset just past the open tag
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the closing `<`, or `-1` when it is missing
 */
func matchingClose(src as bytes, name as string, from as int, limit as int) {
    def closeProbe as bytes init probeOf("</" + $name);
    def close as int init closeTagAt($src, $closeProbe, $from, $limit);
    if ($close < 0) {
        return -1;
    }
    # The common case by far: no element of the same name opens inside this
    # one, so the first close tag is the matching one and the whole search was
    # two native scans. Only a nested name - an ODS <table:table-cell> inside
    # a <table:table-cell>, or a <row> inside a <row> - pays for the walk below.
    #
    # The boundary test is what makes this pay: `<row` occurs inside every
    # `<rowBreaks>`, and `<c` inside every `<cols>` and `<customSheetView>`, so
    # a bare substring search would send every worksheet down the slow path.
    #
    # The open probe is built here rather than at the top of the function: it
    # is only needed from this point on, and `matchingClose` is called once per
    # element, so building it unconditionally was one wasted `bytes` per
    # element of the document.
    def openProbe as bytes init probeOf("<" + $name);
    def nested as int init openTagAt($src, $openProbe, $from, $close);
    if ($nested < 0) {
        return $close;
    }
    return nestedClose($src, $openProbe, $closeProbe, $from, $limit);
}

/**
 * The offset of the next close tag whose name is followed by its `>`.
 *
 * @param src {bytes} the whole document
 * @param closeProbe {bytes} `</` plus the tag name, as bytes
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the `<`, or `-1` when there is none
 */
func closeTagAt(src as bytes, closeProbe as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def found as int init indexOfByte($src, $closeProbe, $at, $limit);
        if ($found < 0) {
            return -1;
        }
        if (isCloseEnd($src, $found + len($closeProbe), $limit)) {
            return $found;
        }
        $at = $found + 1;
    }
    return -1;
}

/**
 * The offset of the next open tag whose name ends where the probe does.
 *
 * @param src {bytes} the whole document
 * @param openProbe {bytes} `<` plus the tag name, as bytes
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the `<`, or `-1` when there is none
 */
func openTagAt(src as bytes, openProbe as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def found as int init indexOfByte($src, $openProbe, $at, $limit);
        if ($found < 0) {
            return -1;
        }
        def after as int init $found + len($openProbe);
        if ($after >= $limit or isNameEnd($src[$after])) {
            return $found;
        }
        $at = $found + 1;
    }
    return -1;
}

/**
 * The matching close tag of an element that nests its own name.
 *
 * @param src {bytes} the whole document
 * @param openProbe {bytes} `<` plus the tag name, as bytes
 * @param closeProbe {bytes} `</` plus the tag name, as bytes
 * @param from {int} the offset just past the open tag
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the closing `<`, or `-1` when it is missing
 */
func nestedClose(src as bytes, openProbe as bytes, closeProbe as bytes, from as int, limit as int) {
    def depth as int init 1;
    def at as int init $from;
    while ($at < $limit) {
        def lt as int init indexOfByte($src, LT_PROBE, $at, $limit);
        if ($lt < 0) {
            return -1;
        }
        $depth = $depth + depthChange($src, $lt, $openProbe, $closeProbe, $limit);
        if ($depth == 0) {
            return $lt;
        }
        $at = $lt + 1;
    }
    return -1;
}

/**
 * What one `<` does to the nesting depth of a named element.
 *
 * @param src {bytes} the whole document
 * @param lt {int} the offset of the `<`
 * @param openProbe {bytes} `<` plus the tag name, as bytes
 * @param closeProbe {bytes} `</` plus the tag name, as bytes
 * @param limit {int} the offset to stop at
 * @return {int} `1` for a nested open tag, `-1` for a close tag, `0` otherwise
 */
func depthChange(src as bytes, lt as int, openProbe as bytes, closeProbe as bytes, limit as int) {
    if (matchesAt($src, $lt, $closeProbe) and isCloseEnd($src, $lt + len($closeProbe), $limit)) {
        return -1;
    }
    if (not matchesAt($src, $lt, $openProbe)) {
        return 0;
    }
    def after as int init $lt + len($openProbe);
    if ($after < $limit and not isNameEnd($src[$after])) {
        return 0;
    }
    def openEnd as int init endOfOpenTag($src, $after, $limit);
    if ($openEnd > 1 and $src[$openEnd - 2] == SLASH) {
        return 0;
    }
    return 1;
}

/**
 * Whether a close tag's name is followed by its `>`.
 *
 * @param src {bytes} the whole document
 * @param at {int} the offset just past the name in a `</name` sequence
 * @param limit {int} the offset to stop at
 * @return {bool} whether only whitespace stands between `at` and a `>`
 */
func isCloseEnd(src as bytes, at as int, limit as int) {
    def i as int init $at;
    while ($i < $limit and
        ($src[$i] == 0x20 or $src[$i] == 0x09 or $src[$i] == 0x0a or $src[$i] == 0x0d)) {
        $i = $i + 1;
    }
    return $i < $limit and $src[$i] == GT;
}

/**
 * The offset of the next occurrence of a probe, inside a range.
 *
 * `binary.indexOf` has no limit argument and searches to the end of the
 * buffer, so a probe that is *not* in the range still costs a scan of
 * everything after it. That is invisible until something probes a short
 * range many times: reading 3 000 Gnumeric style regions, each asking a
 * dozen times whether an attribute is present, turned a 110 KB document into
 * hundreds of megabytes of scanning and made the read superlinear in the
 * file's size.
 *
 * So a short range is copied out and searched on its own. The copy is what
 * bounds the work, and it is only worth it while the range is small - over
 * `BOUNDED_SEARCH` the copy would cost more than the overscan, and the
 * callers that search a whole document fall through to the plain search.
 *
 * @param src {bytes} the buffer to search
 * @param probe {bytes} the bytes to find
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset, or `-1` when the probe is not in the range
 */
func indexOfByte(src as bytes, probe as bytes, from as int, limit as int) {
    if ($from < 0 or $from >= $limit) {
        return -1;
    }
    if ($limit - $from <= BOUNDED_SEARCH and $limit < len($src)) {
        def found as int init binary.indexOf(binary.slice($src, $from, $limit), $probe, 0);
        if ($found < 0) {
            return -1;
        }
        return $from + $found;
    }
    def found as int init binary.indexOf($src, $probe, $from);
    if ($found < 0 or $found >= $limit) {
        return -1;
    }
    return $found;
}

/**
 * How short a range has to be before it is copied out to search it.
 *
 * An element's open tag is tens or hundreds of bytes, so every attribute
 * probe lands well inside this. A row or a whole document does not, and
 * copying one of those to search it would be the more expensive mistake.
 */
def const BOUNDED_SEARCH as int init 4096;

/**
 * Whether a probe stands at an offset.
 *
 * One native slice and one value comparison, rather than a loop per byte. The
 * probe is `bytes` so a caller in a loop converts it once, outside.
 *
 * @param src {bytes} the buffer to test
 * @param at {int} the offset to test at
 * @param probe {bytes} the bytes to look for
 * @return {bool} whether they are there
 */
func matchesAt(src as bytes, at as int, probe as bytes) {
    def size as int init len($probe);
    if ($at < 0 or $at + $size > len($src)) {
        return false;
    }
    return binary.slice($src, $at, $at + $size) == $probe;
}

/**
 * The offset just past the next occurrence of a literal.
 *
 * @param src {bytes} the buffer to search
 * @param from {int} the offset to start at
 * @param literal {string} the ASCII literal to find
 * @param limit {int} the offset to stop at
 * @return {int} the offset just past it, or `limit` when it is not there
 */
func skipPast(src as bytes, from as int, literal as string, limit as int) {
    def needle as bytes init convert.bytesFromString($literal, "utf-8");
    def found as int init binary.indexOf($src, $needle, $from);
    if ($found < 0 or $found + len($needle) > $limit) {
        return $limit;
    }
    return $found + len($needle);
}

/**
 * One ASCII literal as a byte probe.
 *
 * @param literal {string} the literal to convert
 * @return {bytes} its UTF-8 bytes
 */
func probeOf(literal as string) {
    return convert.bytesFromString($literal, "utf-8");
}

/**
 * A byte range as text.
 *
 * @param src {bytes} the buffer to read from
 * @param from {int} the first offset
 * @param limit {int} the offset to stop at
 * @return {string} the range, decoded as UTF-8
 * @throws {Error} kind "sheets" when the range is not valid UTF-8
 */
func byteText(src as bytes, from as int, limit as int) {
    if ($limit <= $from) {
        return "";
    }
    return convert.stringFromBytes(binary.slice($src, $from, $limit), "utf-8");
}

/**
 * One element, as a standalone XML document.
 *
 * Not used by the codecs, which read leaves in place. It is how a fragment
 * becomes reportable: an error message, or a test, can quote the element it is
 * about without the caller keeping track of offsets.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to cut out
 * @return {string} the element and everything inside it
 */
func nodeBytes(src as bytes, node as Node) {
    return byteText($src, $node.start, $node.end);
}

/**
 * The text content of an element, entities resolved.
 *
 * Only the element's own character data, not that of its children, which is
 * what every leaf in a worksheet needs.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to read
 * @return {string} the text, trimmed, with entity references resolved
 */
func nodeText(src as bytes, node as Node) {
    def raw as string init byteText($src, $node.openEnd, $node.innerEnd);
    if (strings.indexOf($raw, "<![CDATA[") >= 0) {
        return strings.trim(cdataText($raw));
    }
    if (strings.indexOf($raw, "<") >= 0) {
        return strings.trim(xmlUnescape(textOnly($raw)));
    }
    return strings.trim(xmlUnescape($raw));
}

/**
 * The content of every CDATA section in a run of character data.
 *
 * @param raw {string} the element's content as written
 * @return {string} the sections' contents, run together, verbatim
 */
func cdataText(raw as string) {
    def out as string init "";
    def parts as list of string init strings.split($raw, "<![CDATA[");
    for (def i as int init 1; $i < len($parts); $i = $i + 1) {
        def close as int init strings.indexOf($parts[$i], "]]>");
        if ($close < 0) {
            $out = $out + $parts[$i];
        } else {
            $out = $out + strings.substring($parts[$i], 0, $close);
        }
    }
    return $out;
}

/**
 * Character data with every tag dropped.
 *
 * A `<name>` that carries markup is not something this deck models, so the
 * markup is dropped and the words are kept.
 *
 * @param raw {string} the element's content as written
 * @return {string} the content with every `<...>` removed
 */
func textOnly(raw as string) {
    def out as string init "";
    def depth as int init 0;
    for (def ch in strings.chars($raw)) {
        if ($ch == "<") {
            $depth = $depth + 1;
        } elseif ($ch == ">") {
            if ($depth > 0) {
                $depth = $depth - 1;
            }
        } elseif ($depth == 0) {
            $out = $out + $ch;
        }
    }
    return $out;
}

/**
 * An attribute of an element, entities resolved.
 *
 * Read straight out of the open tag's bytes, with native searches: a row's
 * index costs no decode of the element and no per-character walk of its tag.
 * Matched on the attribute's local part, so `table:name` answers to
 * `name`, and tolerant of whitespace around the equals sign, which is legal
 * XML.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to read
 * @param name {string} the attribute to read, matched on its local part
 * @return {string} the value, or `""` when the attribute is absent
 */
func nodeAttr(src as bytes, node as Node, name as string) {
    def probe as bytes init probeOf($name);
    def at as int init $node.start + 1;
    while ($at < $node.openEnd) {
        def found as int init indexOfByte($src, $probe, $at, $node.openEnd);
        if ($found < 0) {
            return "";
        }
        def after as int init skipSpaceBytes($src, $found + len($probe), $node.openEnd);
        if (isAttrStart($src, $found) and isEquals($src, $after, $node.openEnd)) {
            return attrValueAt($src, $after + 1, $node.openEnd);
        }
        $at = $found + 1;
    }
    return "";
}

/**
 * Whether an attribute name begins at an offset.
 *
 * The byte before it must end a previous token: whitespace, or the colon of a
 * namespace prefix. Without this, `name` would match inside `style-name`.
 *
 * @param src {bytes} the whole document
 * @param at {int} the offset the name would start at
 * @return {bool} whether a name starts there
 */
func isAttrStart(src as bytes, at as int) {
    if ($at <= 0) {
        return false;
    }
    def b as int init $src[$at - 1];
    return $b == 0x20 or $b == 0x09 or $b == 0x0a or $b == 0x0d or $b == 0x3a;
}

/**
 * Whether an equals sign stands at an offset.
 *
 * @param src {bytes} the whole document
 * @param at {int} the offset to test
 * @param limit {int} the offset to stop at
 * @return {bool} whether the byte there is `=`
 */
func isEquals(src as bytes, at as int, limit as int) {
    return $at < $limit and $src[$at] == 0x3d;
}

/**
 * The offset of the first byte that is not XML whitespace.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the first non-space byte, or `limit`
 */
func skipSpaceBytes(src as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit and isSpaceByte($src[$at])) {
        $at = $at + 1;
    }
    return $at;
}

/**
 * Whether a byte is XML whitespace.
 *
 * @param b {int} the byte to test
 * @return {bool} whether it is a space, tab, newline or carriage return
 */
func isSpaceByte(b as int) {
    return $b == 0x20 or $b == 0x09 or $b == 0x0a or $b == 0x0d;
}

/**
 * An attribute value, from just past its equals sign.
 *
 * Quoted with either quote, or unquoted - which is not well-formed XML, but
 * turns up in hand-edited files and costs nothing to accept.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset just past the equals sign
 * @param limit {int} the offset to stop at
 * @return {string} the value, with entity references resolved
 */
func attrValueAt(src as bytes, from as int, limit as int) {
    def at as int init skipSpaceBytes($src, $from, $limit);
    if ($at >= $limit) {
        return "";
    }
    def opener as int init $src[$at];
    if ($opener == 0x22 or $opener == 0x27) {
        def close as int init closingQuote($src, $at, $limit);
        if ($close < 0) {
            return "";
        }
        return xmlUnescape(byteText($src, $at + 1, $close));
    }
    def end as int init $at;
    while ($end < $limit and not isNameEnd($src[$end])) {
        $end = $end + 1;
    }
    return xmlUnescape(byteText($src, $at, $end));
}

/**
 * Whether a character is XML whitespace.
 *
 * @param ch {string} a single character
 * @return {bool} whether it is a space, tab, newline or carriage return
 */
func isSpace(ch as string) {
    return $ch == " " or $ch == "\t" or $ch == "\n" or $ch == "\r";
}

/**
 * The first direct child with a local name, or a node with `start` `-1`.
 *
 * @param nodes {list of Node} the children to search
 * @param name {string} the local name to match
 * @return {Node} the child, or a missing node
 */
func findChild(nodes as list of Node, name as string) {
    for (def node in $nodes) {
        if (localName($node.name) == $name) {
            return $node;
        }
    }
    return missingNode();
}

/**
 * Every direct child with a local name.
 *
 * @param nodes {list of Node} the children to filter
 * @param name {string} the local name to match
 * @return {list of Node} the matching children, in document order
 */
func findChildren(nodes as list of Node, name as string) {
    def out as list of Node init [];
    for (def node in $nodes) {
        if (localName($node.name) == $name) {
            $out[] = $node;
        }
    }
    return $out;
}

/**
 * Whether a node was found.
 *
 * @param node {Node} the node to test
 * @return {bool} whether it points at an element
 */
func isNode(node as Node) {
    return $node.start >= 0;
}

/**
 * The text of a named child, or `""` when there is no such child.
 *
 * @param src {bytes} the whole document
 * @param nodes {list of Node} the children to search
 * @param name {string} the local name to match
 * @return {string} the child's text, or `""`
 */
func childText(src as bytes, nodes as list of Node, name as string) {
    def node as Node init findChild($nodes, $name);
    if (not isNode($node)) {
        return "";
    }
    return nodeText($src, $node);
}

/**
 * One element, decoded into a tree of its own.
 *
 * The other half of the strategy. Walking a leaf element's fields with the
 * scanner means an interpreted step per child; handing the fragment to
 * `xml.decode` is a native parse, and measurably faster at the same memory,
 * because the tree that exists at any moment covers one row rather than the
 * whole document.
 *
 * Use it for an element whose fields are wanted - a `<row>`, a
 * `<table:table-row>`. Never for a container: decoding a `<sheetData>` is
 * decoding the whole sheet, which costs about 12 KB per cell.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to decode
 * @return {xml.Value} the element as a tree
 * @throws {Error} kind "sheets" when the fragment is not well-formed XML
 */
func decodeLeaf(src as bytes, node as Node) {
    def text as string init nodeBytes($src, $node);
    def tree as xml.Value init xml.element("empty");
    try {
        $tree = xml.decode($text);
    } catch (e) {
        fail("<" + $node.name + "> is not well-formed: " + $e.message);
    }
    return $tree;
}

/**
 * The root element of a document.
 *
 * @param src {bytes} the whole document
 * @return {Node} the root
 * @throws {Error} kind "sheets" when the buffer holds no element
 */
func rootNode(src as bytes) {
    def top as list of Node init childNodes($src, 0, len($src));
    if (len($top) == 0) {
        fail("no XML element in the document");
    }
    return $top[0];
}
