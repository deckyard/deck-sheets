# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the formula lexer: expression text to a list of tokens.
# Spliced into sheets.j via include - not a standalone module.
#
# Separate from fdialect.j: that file translates between the dialects without
# understanding a formula and leaves anything it does not recognise as
# written. This one reads the expression and may reject it.

/** What one token of a formula is. */
export def enum Token {
    Number{amount as float},
    Text{body as string},
    Logical{flag as bool},
    Reference{body as string},
    Name{body as string},
    Operator{symbol as string},
    OpenParen,
    CloseParen,
    Separator,
    ErrorToken{code as string}
};

/**
 * A division or modulo by zero.
 *
 * This and the `ERR_` constants below are the spellings both formats and
 * every application use: what a cell holds and what an evaluation yields.
 */
export def const ERR_DIV0 as string init "#DIV/0!";

/** The value is not of the type an operation needed. */
export def const ERR_VALUE as string init "#VALUE!";

/** A reference does not point at anything. */
export def const ERR_REF as string init "#REF!";

/** A name is not defined. */
export def const ERR_NAME as string init "#NAME?";

/** A number is outside the domain of the operation. */
export def const ERR_NUM as string init "#NUM!";

/** A lookup found nothing. */
export def const ERR_NA as string init "#N/A";

/**
 * A formula depends on itself, or a chain of formulas runs deeper than
 * `MAX_FORMULA_DEPTH`. Spelled `#REF!`, the same as `ERR_REF`.
 */
export def const ERR_CIRCULAR as string init "#REF!";

/**
 * Split a formula into tokens.
 *
 * Works over a character list: `strings.substring($s, $i, $i + 1)` is
 * rune-indexed, so a per-character loop over the string is quadratic (64 000
 * characters: 4 878 ms against 41 ms here).
 *
 * @param source {string} the formula, with no leading `=`
 * @return {list of Token} the tokens, in order
 * @throws {Error} kind "sheets" when a character starts no token
 * @example
 *   tokenize("1+SUM(A1:A5)");
 */
export func tokenize(source as string) {
    def chars as list of string init strings.chars($source);
    def out as list of Token init [];
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if (isFormulaSpace($ch)) {
            $i = $i + 1;
            continue;
        }
        def taken as int init takeToken($chars, $i);
        if ($taken <= 0) {
            fail("formula holds " + quoted($ch) + " at position " +
                convert.toString($i) + ", which is not part of an expression");
        }
        $out[] = tokenAt($chars, $i, $taken);
        $i = $i + $taken;
    }
    return $out;
}

/**
 * Whether a character is formula whitespace.
 *
 * @param ch {string} a single character
 * @return {bool} whether it separates tokens without being one
 */
func isFormulaSpace(ch as string) {
    return $ch == " " or $ch == "\t" or $ch == "\n" or $ch == "\r";
}

/**
 * How many characters the token at a position spans.
 *
 * @param chars {list of string} the formula
 * @param at {int} where the token starts
 * @return {int} the span, or 0 when nothing can be read here
 */
func takeToken(chars as list of string, at as int) {
    def ch as string init $chars[$at];
    if ($ch == "\"") {
        return quotedSpan($chars, $at);
    }
    if ($ch == "(" or $ch == ")" or $ch == "," or $ch == ";") {
        return 1;
    }
    if ($ch == "#") {
        return errorSpan($chars, $at);
    }
    def operator as int init operatorSpan($chars, $at);
    if ($operator > 0) {
        return $operator;
    }
    if (isDigit($ch) or ($ch == "." and $at + 1 < len($chars) and
        isDigit($chars[$at + 1]))) {
        return numberSpan($chars, $at);
    }
    def reference as int init referenceSpanAt($chars, $at);
    if ($reference > 0) {
        return $reference;
    }
    if ($ch == "'") {
        def quoted as int init quotedNameSpan($chars, $at);
        if ($quoted > 0) {
            return $quoted;
        }
    }
    if (isLetter($ch) or $ch == "_") {
        return nameSpan($chars, $at);
    }
    if ($ch == "$") {
        # A lone `$` only makes sense inside a reference, and
        # `referenceSpanAt` already had its chance.
        return 0;
    }
    return 0;
}

/**
 * The token a span of characters is.
 *
 * @param chars {list of string} the formula
 * @param at {int} where the token starts
 * @param span {int} how long it is
 * @return {Token} the token
 */
func tokenAt(chars as list of string, at as int, span as int) {
    def body as string init joinChars($chars, $at, $at + $span);
    def ch as string init $chars[$at];
    if ($ch == "\"") {
        return Token.Text{body: unquoteFormulaText($body)};
    }
    if ($ch == "(") {
        return Token.OpenParen;
    }
    if ($ch == ")") {
        return Token.CloseParen;
    }
    if ($ch == "," or $ch == ";") {
        return Token.Separator;
    }
    if ($ch == "#") {
        return Token.ErrorToken{code: strings.upper($body)};
    }
    if (isOperatorStart($ch)) {
        return Token.Operator{symbol: $body};
    }
    if (isDigit($ch) or $ch == ".") {
        return numberToken($body);
    }
    if (referenceSpanAt($chars, $at) == $span) {
        return Token.Reference{body: $body};
    }
    def word as string init strings.upper($body);
    if ($word == "TRUE") {
        return Token.Logical{flag: true};
    }
    if ($word == "FALSE") {
        return Token.Logical{flag: false};
    }
    return Token.Name{body: $body};
}

/**
 * A numeric literal as a token.
 *
 * @param body {string} the literal as written
 * @return {Token} the number, or an error token when it will not parse
 */
func numberToken(body as string) {
    def amount as float init 0.0;
    try {
        $amount = convert.toFloat($body);
    } catch (e) {
        return Token.ErrorToken{code: ERR_NUM};
    }
    return Token.Number{amount: $amount};
}

/**
 * How long the string literal at a quote is.
 *
 * A doubled quote is an escaped quote, which is how both dialects spell one.
 *
 * @param chars {list of string} the formula
 * @param at {int} the index of the opening quote
 * @return {int} the span, including both quotes
 */
func quotedSpan(chars as list of string, at as int) {
    def i as int init $at + 1;
    while ($i < len($chars)) {
        if ($chars[$i] == "\"") {
            if ($i + 1 < len($chars) and $chars[$i + 1] == "\"") {
                $i = $i + 2;
                continue;
            }
            return $i - $at + 1;
        }
        $i = $i + 1;
    }
    # The dialect translator tolerates an unterminated string, because its job
    # is to round-trip whatever a file holds. An evaluator's job is to compute,
    # and computing over a guessed closing quote silently invents a value, so
    # here it is an error.
    fail("the formula has a string that is never closed");
    return 0;
}

/**
 * A string literal's body, with its quotes removed and doubles undoubled.
 *
 * @param body {string} the literal as written
 * @return {string} the text it denotes
 */
func unquoteFormulaText(body as string) {
    def inner as string init $body;
    if (strings.startsWith($inner, "\"")) {
        $inner = strings.substring($inner, 1, len($inner));
    }
    if (strings.endsWith($inner, "\"") and len($inner) > 0) {
        $inner = strings.substring($inner, 0, len($inner) - 1);
    }
    return strings.replace($inner, "\"\"", "\"");
}

/**
 * How long the quoted sheet name at a position is, if it starts a reference.
 *
 * @param chars {list of string} the formula
 * @param at {int} the index of the opening quote
 * @return {int} the span, or 0 when this is not a reference
 */
func quotedNameSpan(chars as list of string, at as int) {
    return referenceSpanAt($chars, $at);
}

/**
 * How long the error literal at a `#` is.
 *
 * @param chars {list of string} the formula
 * @param at {int} the index of the `#`
 * @return {int} the span, or 0 when it is not an error code
 */
func errorSpan(chars as list of string, at as int) {
    for (def code in [ERR_DIV0, ERR_VALUE, ERR_REF, ERR_NAME, ERR_NUM, ERR_NA]) {
        def span as int init len(strings.chars($code));
        if (matchesChars($chars, $at, $code)) {
            return $span;
        }
    }
    return 0;
}

/**
 * Whether a literal appears at a position, case-insensitively.
 *
 * @param chars {list of string} the formula
 * @param at {int} the index to test
 * @param literal {string} the text to match
 * @return {bool} whether it is there
 */
func matchesChars(chars as list of string, at as int, literal as string) {
    def wanted as list of string init strings.chars(strings.upper($literal));
    if ($at + len($wanted) > len($chars)) {
        return false;
    }
    for (def i in 0..len($wanted)) {
        if (strings.upper($chars[$at + $i]) != $wanted[$i]) {
            return false;
        }
    }
    return true;
}

/**
 * How long the operator at a position is.
 *
 * The two-character comparisons are tried first, or `<=` would read as `<`
 * followed by an `=` that means nothing.
 *
 * @param chars {list of string} the formula
 * @param at {int} the index to test
 * @return {int} 2, 1, or 0 when there is no operator here
 */
func operatorSpan(chars as list of string, at as int) {
    if ($at + 1 < len($chars)) {
        def pair as string init $chars[$at] + $chars[$at + 1];
        if ($pair == "<=" or $pair == ">=" or $pair == "<>") {
            return 2;
        }
    }
    if (isOperatorStart($chars[$at])) {
        return 1;
    }
    return 0;
}

/**
 * Whether a character can begin an operator.
 *
 * @param ch {string} a single character
 * @return {bool} whether it is an operator character
 */
func isOperatorStart(ch as string) {
    return strings.indexOf("+-*/^&=<>%", $ch) >= 0 and $ch != "";
}

/**
 * How long the numeric literal at a position is.
 *
 * Accepts a decimal point and an exponent and stops before anything else, so
 * `1E5` is one number and `1EXTRA` is a number followed by a name.
 *
 * @param chars {list of string} the formula
 * @param at {int} where the literal starts
 * @return {int} the span
 */
func numberSpan(chars as list of string, at as int) {
    def i as int init $at;
    def dots as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if (isDigit($ch)) {
            $i = $i + 1;
            continue;
        }
        if ($ch == "." and $dots == 0) {
            $dots = 1;
            $i = $i + 1;
            continue;
        }
        if (($ch == "e" or $ch == "E") and $i + 1 < len($chars) and
            exponentFollows($chars, $i + 1)) {
            $i = $i + 2;
            while ($i < len($chars) and isDigit($chars[$i])) {
                $i = $i + 1;
            }
            return $i - $at;
        }
        break;
    }
    return $i - $at;
}

/**
 * Whether an exponent's digits follow a position, with an optional sign.
 *
 * @param chars {list of string} the formula
 * @param at {int} the index just past the `e`
 * @return {bool} whether this is an exponent
 */
func exponentFollows(chars as list of string, at as int) {
    def i as int init $at;
    if ($i < len($chars) and ($chars[$i] == "+" or $chars[$i] == "-")) {
        $i = $i + 1;
    }
    return $i < len($chars) and isDigit($chars[$i]);
}

/**
 * How long the name at a position is.
 *
 * A function name or a defined name: letters, digits, underscores and dots,
 * plus the `_xlfn.` prefix newer functions carry.
 *
 * @param chars {list of string} the formula
 * @param at {int} where the name starts
 * @return {int} the span
 */
func nameSpan(chars as list of string, at as int) {
    def i as int init $at;
    while ($i < len($chars) and isNameByte($chars[$i])) {
        $i = $i + 1;
    }
    return $i - $at;
}
