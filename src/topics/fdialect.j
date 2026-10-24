# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - translating formulas between the A1 and OpenFormula dialects.
# Spliced into sheets.j via include - not a standalone module.

# The model stores every formula in **A1** - `B3*C2`, `SUM(A1:A5)`, the
# spelling a user types and XLSX stores. ODS stores OpenFormula instead:
# references are bracketed and dot-qualified (`[.B3]`), and arguments are
# separated by semicolons (`SUM([.A1:.A5])`).
#
# Writing an A1 formula into an ODS file unchanged produces a document
# LibreOffice reads as a broken expression, and writing OpenFormula into XLSX
# does the same to Excel, so every conversion translates.

/** What one piece of a formula is. */
def enum Piece {
    Ref{body as string},
    Str{body as string},
    Sep,
    Other{body as string}
};

/**
 * Translate a formula from OpenFormula to A1.
 *
 * @param source {string} the formula, with no leading `=`
 * @return {string} the A1 spelling
 * @example
 *   toA1Formula("[.B3]*[.C2]");         # "B3*C2"
 *   toA1Formula("SUM([.A1:.A5])");      # "SUM(A1:A5)"
 */
export func toA1Formula(source as string) {
    def out as list of string init [];
    def pieces as list of Piece init tokenizeOpenFormula(strings.chars($source));
    for (def piece in $pieces) {
        def part as Piece init $piece;
        match ($part) {
            when Ref(r) { $out[] = $r.body; }
            when Str(s) { $out[] = "\"" + $s.body + "\""; }
            when Sep { $out[] = ","; }
            when Other(o) { $out[] = $o.body; }
        }
    }
    return strings.join($out, "");
}

/**
 * Translate a formula from A1 to OpenFormula.
 *
 * @param source {string} the formula, with no leading `=`
 * @return {string} the OpenFormula spelling
 * @example
 *   toOpenFormula("B3*C2");        # "[.B3]*[.C2]"
 *   toOpenFormula("SUM(A1:A5)");   # "SUM([.A1:.A5])"
 */
export func toOpenFormula(source as string) {
    def out as list of string init [];
    def pieces as list of Piece init tokenizeA1(strings.chars($source));
    for (def piece in $pieces) {
        def part as Piece init $piece;
        match ($part) {
            when Ref(r) { $out[] = bracketReference($r.body); }
            when Str(s) { $out[] = "\"" + $s.body + "\""; }
            when Sep { $out[] = ";"; }
            when Other(o) { $out[] = $o.body; }
        }
    }
    return strings.join($out, "");
}

/**
 * Split an OpenFormula expression into references, strings and everything else.
 *
 * A tokeniser rather than a search and replace, because a `;` or a `[` inside
 * a string literal is literal text. `SUM([.A1];"a;b")` has one separator, not
 * two.
 *
 * Works over a list of characters rather than the string itself.
 * `strings.substring($s, $i, $i + 1)` is rune-indexed, so reading the i-th
 * character walks i runes and a per-character loop is quadratic: 64 000
 * characters measured 4 878 ms that way against 41 ms over a character list.
 *
 * @param chars {list of string} the formula, one character per entry
 * @return {list of Piece} the pieces, in order
 */
func tokenizeOpenFormula(chars as list of string) {
    def out as list of Piece init [];
    def plain as string init "";
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if ($ch != "\"" and $ch != "[" and $ch != ";") {
            $plain = $plain + $ch;
            $i = $i + 1;
            continue;
        }
        # The accumulated text is appended into the local list here rather than
        # through a helper taking the list: handing a growing list to a
        # function copies it every call. See emit.j for the same lesson.
        if ($plain != "") {
            $out[] = Piece.Other{body: $plain};
            $plain = "";
        }
        if ($ch == "\"") {
            def closed as int init closingQuoteAt($chars, $i);
            $out[] = Piece.Str{body: unquoteBody($chars, $i, $closed)};
            $i = $closed + 1;
        } elseif ($ch == "[") {
            def end as int init charIndexFrom($chars, "]", $i);
            if ($end < 0) {
                # Unclosed: take the rest of the text as the reference body
                # rather than dropping its last character.
                $end = len($chars);
            }
            $out[] = Piece.Ref{body: unbracketReference(joinChars($chars, $i + 1, $end))};
            $i = $end + 1;
        } else {
            $out[] = Piece.Sep;
            $i = $i + 1;
        }
    }
    if ($plain != "") {
        $out[] = Piece.Other{body: $plain};
    }
    return $out;
}

/**
 * Split an A1 expression into references, strings and everything else.
 *
 * A reference is recognised by shape: letters then digits, at a position
 * where a name could not be a function call. `SUM(A1:A5)` has one reference
 * pair; `LOG10(A1)` has one reference and a function whose name ends in
 * digits, which is the case a naive scan gets wrong.
 *
 * @param chars {list of string} the formula, one character per entry
 * @return {list of Piece} the pieces, in order
 */
func tokenizeA1(chars as list of string) {
    def out as list of Piece init [];
    def plain as string init "";
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        def span as int init 0;
        if ($ch != "\"" and $ch != ",") {
            $span = referenceSpanAt($chars, $i);
            if ($span == 0) {
                $plain = $plain + $ch;
                $i = $i + 1;
                continue;
            }
        }
        if ($plain != "") {
            $out[] = Piece.Other{body: $plain};
            $plain = "";
        }
        if ($span > 0) {
            $out[] = Piece.Ref{body: joinChars($chars, $i, $i + $span)};
            $i = $i + $span;
        } elseif ($ch == "\"") {
            def closed as int init closingQuoteAt($chars, $i);
            $out[] = Piece.Str{body: unquoteBody($chars, $i, $closed)};
            $i = $closed + 1;
        } else {
            $out[] = Piece.Sep;
            $i = $i + 1;
        }
    }
    if ($plain != "") {
        $out[] = Piece.Other{body: $plain};
    }
    return $out;
}

/**
 * A run of characters back as a string.
 *
 * @param chars {list of string} the characters
 * @param from {int} the first index, inclusive
 * @param to2 {int} the last index, exclusive
 * @return {string} the run
 */
func joinChars(chars as list of string, from as int, to2 as int) {
    def stop as int init $to2;
    if ($stop > len($chars)) {
        $stop = len($chars);
    }
    if ($from >= $stop) {
        return "";
    }
    return strings.join($chars[$from..$stop], "");
}

/**
 * The index of a character at or after a position.
 *
 * @param chars {list of string} the characters
 * @param needle {string} the character to find
 * @param from {int} the index to start at
 * @return {int} the index, or `-1` when it is not there
 */
func charIndexFrom(chars as list of string, needle as string, from as int) {
    def i as int init $from;
    while ($i < len($chars)) {
        if ($chars[$i] == $needle) {
            return $i;
        }
        $i = $i + 1;
    }
    return -1;
}

/**
 * Where the string literal starting at a quote closes.
 *
 * A doubled quote is an escaped quote and does not close the literal, which
 * both dialects spell the same way.
 *
 * @param chars {list of string} the characters
 * @param open {int} the index of the opening quote
 * @return {int} the index of the closing quote, or one past the end when the
 *   literal is unterminated
 */
func closingQuoteAt(chars as list of string, open as int) {
    def i as int init $open + 1;
    while ($i < len($chars)) {
        if ($chars[$i] == "\"") {
            if ($i + 1 < len($chars) and $chars[$i + 1] == "\"") {
                $i = $i + 2;
                continue;
            }
            return $i;
        }
        $i = $i + 1;
    }
    # Unterminated: report one past the end so the body runs to the end of the
    # text rather than losing its last character.
    return len($chars);
}

/**
 * The body of a string literal, without its quotes.
 *
 * @param chars {list of string} the characters
 * @param open {int} the index of the opening quote
 * @param close {int} the index of the closing quote
 * @return {string} the body as written, doubled quotes intact
 */
func unquoteBody(chars as list of string, open as int, close as int) {
    return joinChars($chars, $open + 1, $close);
}

/**
 * How many characters of an A1 reference start at a position, if any.
 *
 * A reference is an optional sheet qualifier, `$`-decorated letters, then
 * `$`-decorated digits, not followed by a `(` (which would make it a function
 * name).
 *
 * @param chars {list of string} the characters
 * @param at {int} the index to test
 * @return {int} the reference's length, or 0 when there is none here
 */
func referenceSpanAt(chars as list of string, at as int) {
    if ($at > 0 and isNameByte($chars[$at - 1])) {
        # Mid-identifier: this is part of a name that started earlier.
        return 0;
    }
    def first as int init cellPartSpan($chars, $at);
    if ($first == 0) {
        return 0;
    }
    def end as int init $at + $first;
    # A range is one reference, not two: "A1:A5" has to come out as
    # "[.A1:.A5]", and tokenising it as two references would produce
    # "[.A1]:[.A5]", which neither application reads as a range.
    if ($end < len($chars) and $chars[$end] == ":") {
        def second as int init cellPartSpan($chars, $end + 1);
        if ($second > 0 and not followedByName($chars, $end + 1 + $second)) {
            return $end + 1 + $second - $at;
        }
    }
    if (followedByName($chars, $end)) {
        return 0;
    }
    return $first;
}

/**
 * Whether the position begins a `(` or continues a name.
 *
 * Both mean what preceded it was not a cell reference: `LOG10(` is a call,
 * and `A1B` is part of a longer name.
 *
 * @param chars {list of string} the characters
 * @param at {int} the index just past a candidate reference
 * @return {bool} whether the candidate is disqualified
 */
func followedByName(chars as list of string, at as int) {
    if ($at >= len($chars)) {
        return false;
    }
    return $chars[$at] == "(" or isNameByte($chars[$at]);
}

/**
 * How many characters one half of a reference occupies, if any.
 *
 * Optionally a sheet qualifier, then `$`-decorated letters (at most three,
 * since no column name is longer), then `$`-decorated digits. No trailing
 * check: the caller decides whether a `(` or a name byte after it disqualifies
 * the match, because that differs between a single reference and a range half.
 *
 * @param chars {list of string} the characters
 * @param at {int} the index to test
 * @return {int} the length, or 0 when no reference half starts here
 */
func cellPartSpan(chars as list of string, at as int) {
    def i as int init $at;
    def sheetEnd as int init sheetQualifierEnd($chars, $at);
    if ($sheetEnd > $at) {
        $i = $sheetEnd;
    }
    if ($i < len($chars) and $chars[$i] == "$") {
        $i = $i + 1;
    }
    def letters as int init 0;
    while ($i < len($chars) and isLetter($chars[$i])) {
        $letters = $letters + 1;
        $i = $i + 1;
    }
    if ($letters == 0 or $letters > 3) {
        return 0;
    }
    if ($i < len($chars) and $chars[$i] == "$") {
        $i = $i + 1;
    }
    def digits as int init 0;
    while ($i < len($chars) and isDigit($chars[$i])) {
        $digits = $digits + 1;
        $i = $i + 1;
    }
    if ($digits == 0) {
        return 0;
    }
    return $i - $at;
}

/**
 * Where a sheet qualifier ending in `!` stops, if one starts here.
 *
 * Scanned forward over the name rather than searched to the end of the
 * formula, so the cost is the name's length and not the document's.
 *
 * @param chars {list of string} the characters
 * @param at {int} the index to test
 * @return {int} the index just past the `!`, or `at` when there is no qualifier
 */
func sheetQualifierEnd(chars as list of string, at as int) {
    if ($at < len($chars) and $chars[$at] == "'") {
        return quotedQualifierEnd($chars, $at);
    }
    def i as int init $at;
    while ($i < len($chars)) {
        if ($chars[$i] == "!") {
            if ($i == $at) {
                return $at;
            }
            return $i + 1;
        }
        if (not isNameByte($chars[$i])) {
            return $at;
        }
        $i = $i + 1;
    }
    return $at;
}

/**
 * Where a quoted sheet qualifier ends, given its opening quote.
 *
 * @param chars {list of string} the characters
 * @param at {int} the index of the opening quote
 * @return {int} the index just past the `!`, or `at` when this is not a
 *   qualifier after all
 */
func quotedQualifierEnd(chars as list of string, at as int) {
    def closing as int init $at + 1;
    while ($closing < len($chars)) {
        if ($chars[$closing] != "'") {
            $closing = $closing + 1;
            continue;
        }
        if ($closing + 1 < len($chars) and $chars[$closing + 1] == "'") {
            $closing = $closing + 2;
            continue;
        }
        if ($closing + 1 < len($chars) and $chars[$closing + 1] == "!") {
            return $closing + 2;
        }
        return $at;
    }
    return $at;
}

/**
 * Whether a character can appear inside an unquoted name.
 *
 * @param ch {string} a single character
 * @return {bool} whether it is a letter, a digit, an underscore or a dot
 */
func isNameByte(ch as string) {
    return isLetter($ch) or isDigit($ch) or $ch == "_" or $ch == ".";
}

/**
 * Whether a character is an ASCII letter.
 *
 * @param ch {string} a single character
 * @return {bool} whether it is a letter
 */
func isLetter(ch as string) {
    return $ch != "" and strings.indexOf("ABCDEFGHIJKLMNOPQRSTUVWXYZ", strings.upper($ch)) >= 0;
}

/**
 * Whether a character is an ASCII digit.
 *
 * @param ch {string} a single character
 * @return {bool} whether it is a digit
 */
func isDigit(ch as string) {
    return $ch != "" and strings.indexOf("0123456789", $ch) >= 0;
}

/**
 * Wrap an A1 reference or range in OpenFormula brackets.
 *
 * `B3` becomes `[.B3]`, `A1:A5` becomes `[.A1:.A5]`, and a sheet qualifier
 * moves inside the bracket and loses its `!`: `Sheet2!B3` becomes `[Sheet2.B3]`.
 *
 * @param body {string} the A1 reference or range
 * @return {string} the bracketed form
 * @example
 *   bracketReference("B3");          # "[.B3]"
 *   bracketReference("Sheet2!B3");   # "[Sheet2.B3]"
 */
func bracketReference(body as string) {
    def colon as int init rangeColonAt($body);
    if ($colon < 0) {
        return "[" + qualifyPart($body) + "]";
    }
    def left as string init strings.substring($body, 0, $colon);
    def right as string init strings.substring($body, $colon + 1, len($body));
    return "[" + qualifyPart($left) + ":" + qualifyPart($right) + "]";
}

/**
 * The index of the colon separating a range's halves, if there is one.
 *
 * A colon inside a quoted sheet name does not separate anything.
 *
 * @param body {string} the A1 reference or range
 * @return {int} the colon's index, or `-1` when this is a single reference
 */
func rangeColonAt(body as string) {
    def inQuote as bool init false;
    for (def i in 0..len($body)) {
        def ch as string init strings.substring($body, $i, $i + 1);
        if ($ch == "'") {
            $inQuote = not $inQuote;
        } elseif ($ch == ":" and not $inQuote) {
            return $i;
        }
    }
    return -1;
}

/**
 * One half of a bracketed reference: a dot, with any sheet name before it.
 *
 * @param part {string} an A1 reference, possibly sheet-qualified
 * @return {string} the OpenFormula inner form, such as `.B3` or `Sheet2.B3`
 */
func qualifyPart(part as string) {
    def halves as list of string init splitSheetRef($part);
    if ($halves[0] == "") {
        return "." + $halves[1];
    }
    if (needsOpenFormulaQuotes($halves[0])) {
        return "'" + strings.replace($halves[0], "'", "''") + "'." + $halves[1];
    }
    return $halves[0] + "." + $halves[1];
}

/**
 * Whether a sheet name has to be quoted inside an OpenFormula bracket.
 *
 * @param sheetName {string} the sheet name
 * @return {bool} whether it needs quoting
 */
func needsOpenFormulaQuotes(sheetName as string) {
    if ($sheetName == "") {
        return false;
    }
    for (def ch in strings.chars($sheetName)) {
        if (not isLetter($ch) and not isDigit($ch) and $ch != "_") {
            return true;
        }
    }
    return isDigit(strings.substring($sheetName, 0, 1));
}

/**
 * Unwrap the inside of an OpenFormula bracket into A1.
 *
 * `.B3` becomes `B3`, `.A1:.A5` becomes `A1:A5`, `Sheet2.B3` becomes
 * `Sheet2!B3`, and `'Second Sheet'.B3` becomes `'Second Sheet'!B3`.
 *
 * @param inner {string} what stood between `[` and `]`
 * @return {string} the A1 spelling
 * @example
 *   unbracketReference(".B3");        # "B3"
 *   unbracketReference("Sheet2.B3");  # "Sheet2!B3"
 */
func unbracketReference(inner as string) {
    def colon as int init rangeColonAt($inner);
    if ($colon < 0) {
        return unqualifyPart($inner);
    }
    def left as string init unqualifyPart(strings.substring($inner, 0, $colon));
    def right as string init unqualifyPart(strings.substring($inner, $colon + 1, len($inner)));
    return $left + ":" + dropSheet($right);
}

/**
 * One half of a bracketed reference, as A1.
 *
 * @param part {string} the inner form, such as `.B3` or `Sheet2.B3`
 * @return {string} the A1 spelling
 */
func unqualifyPart(part as string) {
    if (strings.startsWith($part, ".")) {
        return strings.substring($part, 1, len($part));
    }
    if (strings.startsWith($part, "'")) {
        def closing as int init closingSheetQuoteAt($part);
        if ($closing > 0 and $closing + 1 < len($part) and
            strings.substring($part, $closing + 1, $closing + 2) == ".") {
            return strings.substring($part, 0, $closing + 1) + "!" +
                strings.substring($part, $closing + 2, len($part));
        }
        return $part;
    }
    def dot as int init strings.indexOf($part, ".");
    if ($dot < 0) {
        return $part;
    }
    return strings.substring($part, 0, $dot) + "!" +
        strings.substring($part, $dot + 1, len($part));
}

/**
 * The closing quote of a quoted sheet name at the start of a reference.
 *
 * @param part {string} the reference
 * @return {int} the closing quote's index, or `-1` when there is none
 */
func closingSheetQuoteAt(part as string) {
    def i as int init 1;
    while ($i < len($part)) {
        if (strings.substring($part, $i, $i + 1) == "'") {
            if ($i + 1 < len($part) and strings.substring($part, $i + 1, $i + 2) == "'") {
                $i = $i + 2;
                continue;
            }
            return $i;
        }
        $i = $i + 1;
    }
    return -1;
}

/**
 * Strip a sheet qualifier from the far half of a range.
 *
 * A1 writes a range's sheet once (`Sheet2!A1:A5`), where OpenFormula repeats
 * it on both halves (`[Sheet2.A1:Sheet2.A5]`), so the second one comes off.
 *
 * @param part {string} the A1 spelling of a range's far half
 * @return {string} the half with no sheet qualifier
 */
func dropSheet(part as string) {
    def halves as list of string init splitSheetRef($part);
    return $halves[1];
}
