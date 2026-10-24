# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the formula parser: tokens to an expression tree.
# Spliced into sheets.j via include - not a standalone module.

/**
 * One node of a parsed formula.
 *
 * `Span` is a reference to a range and `Cell` to one cell, kept apart
 * because a function takes one or the other and conflating them is how a
 * lookup silently reads the wrong thing.
 *
 *   `Num`      a number literal, in `amount`
 *   `Str`      a string literal, in `body`
 *   `Logic`    `TRUE` or `FALSE`, in `flag`
 *   `ErrLit`   an error literal such as `#N/A`, in `body`
 *   `Cell`     a single-cell reference, in `body`
 *   `Span`     a range reference, in `body`
 *   `NameRef`  a defined name, in `name`
 *   `Unary`    an operator in `symbol` over the one operand in `parts`
 *   `Binary`   an operator in `symbol` over the two operands in `parts`
 *   `Call`     a function call: the function in `name`, arguments in `parts`
 */
export def enum Expr {
    Num{amount as float},
    Str{body as string},
    Logic{flag as bool},
    ErrLit{body as string},
    Cell{body as string},
    Span{body as string},
    NameRef{name as string},
    Unary{symbol as string, parts as list of Expr},
    Binary{symbol as string, parts as list of Expr},
    Call{name as string, parts as list of Expr}
};

/**
 * How deep a formula may nest.
 *
 * Bounds two recursions: the bracket nesting a parse walks down, and the
 * chain of formulas an evaluation follows. A formula referring
 * to a formula referring to a formula is normal; a thousand of them is a file
 * built to exhaust the stack. Jennifer's own recursion limit surfaces as
 * `kind: "limit"`, and a long enough run of prefix operators killed the
 * interpreter outright with no catchable error at all, so the shape is
 * bounded here before any of it is walked. 64 is also Excel's own nesting
 * limit, so nothing a real application wrote can exceed it.
 */
export def const MAX_FORMULA_DEPTH as int init 64;

/**
 * How many tokens one formula may hold.
 *
 * Parsing is quadratic in the length of a formula and there is no way around
 * it in this language: a left-associative chain builds a left-leaning tree,
 * and `Expr.Binary{parts: [$accumulated, $next]}` deep-copies the subtree
 * built so far on every step. Measured on a bare enum, with no parser
 * involved: 200 nodes 82 ms, 400 226 ms, 800 938 ms, 1 600 5 094 ms. An
 * arena of indexed nodes is the one real fix; see `docs/internal/memory.md`.
 *
 * 512 tokens is far past any formula a person writes (a twenty-branch nested
 * `IF` is about 200). Reading and writing never parse a formula, so the cap
 * only refuses *evaluating* an extreme one; the file still round-trips.
 */
export def const MAX_FORMULA_TOKENS as int init 512;

/**
 * The most text one formula evaluation may build.
 *
 * Not the same thing as `MAX_TEXT_RESULT`, which is what a *cell* can hold.
 * Both LibreOffice and Gnumeric let an intermediate value run past the cell
 * limit - `LEN(REPT("x",32767)&REPT("x",32767))` is 65 534 in both - so
 * capping at the cell limit would answer wrongly for a legitimate formula.
 *
 * `&` amplifies: each `REPT("x",32767)&` term costs 16 characters of
 * formula and yields 32 767, so a cell holding the longest formula a sheet
 * can store builds about 65 MB, and a file full of such cells multiplies
 * that. 2 MiB is far above any real formula and far below a useful attack.
 */
export def const MAX_TEXT_GROWTH as int init 2097152;

/**
 * How tightly each binary operator binds.
 *
 * Spreadsheet precedence, checked against LibreOffice and Gnumeric. Two
 * differences from most programming languages:
 *
 *   `-2^2` is **4**, not -4: unary minus binds tighter than `^`, so the
 *   negation happens first and is then squared.
 *
 *   `2^3^2` is **64**, not 512: `^` is left-associative here, where most
 *   languages make it right-associative.
 *
 * `&` sits between arithmetic and comparison, and the comparisons are all
 * equal and lowest.
 *
 * @param symbol {string} the operator
 * @return {int} the precedence, or 0 when it is not a binary operator
 */
func precedenceOf(symbol as string) {
    match ($symbol) {
        when "=", "<>", "<", ">", "<=", ">=" { return 1; }
        when "&" { return 2; }
        when "+", "-" { return 3; }
        when "*", "/" { return 4; }
        when "^" { return 5; }
        else { return 0; }
    }
}

# The token list is threaded as a parameter rather than carried in a struct
# with the cursor. It used to be a `Parse{tokens, at}`, and rebuilding that
# struct to advance the cursor copied the whole token list every time - about
# a third of the cost of parsing a long formula, measured at 25 ms of 80 ms
# for 200 terms. A parameter is free; a struct field is not. See
# docs/internal/memory.md.

/**
 * One parsed sub-expression and where parsing stopped.
 *
 * Returned as a pair because the parser is value-semantic: it cannot advance
 * a cursor its caller holds, so it hands back how far it got.
 *
 * @field node {Expr} the expression
 * @field at {int} the next token to read
 */
def struct Parsed {
    node as Expr,
    at as int
};

/**
 * Parse a formula into an expression tree.
 *
 * @param source {string} the formula in A1; a leading `=` is dropped
 * @return {Expr} the tree
 * @throws {Error} kind "sheets" when the formula is empty or not a well-formed
 *   expression, or exceeds `MAX_FORMULA_DEPTH` or `MAX_FORMULA_TOKENS`
 * @example
 *   parseFormula("1 + SUM(A1:A5) * 2");
 */
export func parseFormula(source as string) {
    def tokens as list of Token init tokenize($source);
    if (len($tokens) == 0) {
        fail("the formula is empty");
    }
    # Both the formats and every user write the leading `=`, while the model
    # stores the expression without it. No expression can begin with a binary
    # `=`, so dropping a leading one is unambiguous and saves every caller a
    # strip. Excel's `+A1` lead-in is accepted the same way, as unary plus.
    if (isLeadingEquals($tokens[0])) {
        $tokens = lists.slice($tokens, 1, len($tokens));
        if (len($tokens) == 0) {
            fail("the formula is empty");
        }
    }
    checkFormulaShape($tokens);
    def done as Parsed init parseBinary($tokens, 0, 1);
    if ($done.at < len($tokens)) {
        fail("the formula has " + convert.toString(len($tokens) - $done.at) +
            " token(s) left over after a complete expression; a missing " +
            "operator or an extra bracket is the usual cause");
    }
    return $done.node;
}

/**
 * Refuse a formula whose shape would recurse past the depth cap.
 *
 * Checked over the flat token list before parsing starts, because the parse
 * itself is the recursion being guarded: by the time a walk is deep enough to
 * notice, the interpreter may already be gone. Two shapes nest - brackets,
 * and a run of consecutive prefix operators such as `----1` - and the width
 * is bounded too, because parsing is quadratic in it.
 *
 * @param tokens {list of Token} the whole formula
 * @throws {Error} kind "sheets" past `MAX_FORMULA_TOKENS` tokens, or either kind of
 *   nesting past `MAX_FORMULA_DEPTH`
 */
func checkFormulaShape(tokens as list of Token) {
    if (len($tokens) > MAX_FORMULA_TOKENS) {
        fail("the formula has " + convert.toString(len($tokens)) +
            " tokens, past the " + convert.toString(MAX_FORMULA_TOKENS) +
            " this evaluator will parse");
    }
    def depth as int init 0;
    def run as int init 0;
    for (def i in 0..len($tokens)) {
        def t as Token init $tokens[$i];
        match ($t) {
            when OpenParen {
                $depth = $depth + 1;
                $run = 0;
            }
            when CloseParen {
                $depth = $depth - 1;
                $run = 0;
            }
            when Operator(o) { $run = prefixRunAfter($o.symbol, $run); }
            else { $run = 0; }
        }
        if ($depth > MAX_FORMULA_DEPTH or $run > MAX_FORMULA_DEPTH) {
            fail("the formula nests deeper than " +
                convert.toString(MAX_FORMULA_DEPTH) + " levels");
        }
    }
}

/**
 * Advance the count of consecutive prefix operators.
 *
 * @param symbol {string} the operator just seen
 * @param run {int} how many prefix operators preceded it
 * @return {int} the run including this operator, or 0 when it breaks one
 */
func prefixRunAfter(symbol as string, run as int) {
    if ($symbol == "-" or $symbol == "+") {
        return $run + 1;
    }
    return 0;
}

/**
 * Whether a token is a leading `=` to be dropped.
 *
 * @param t {Token} the first token of a formula
 * @return {bool} whether it is the `=` that introduces a formula
 */
func isLeadingEquals(t as Token) {
    match ($t) {
        when Operator(o) { return $o.symbol == "="; }
        else { return false; }
    }
}

/**
 * Parse operators of at least a given precedence, left to right.
 *
 * Precedence climbing: parse one operand, then keep taking operators that
 * bind at least this tightly, parsing their right-hand side one level
 * tighter. There is no exception - see `precedenceOf` for why `^` is not one.
 *
 * @param tokens {list of Token} the whole formula
 * @param from {int} the first token of this expression
 * @param lowest {int} the loosest precedence to accept here
 * @return {Parsed} the expression and where parsing stopped
 * @throws {Error} kind "sheets" when the tokens do not form an expression
 */
func parseBinary(tokens as list of Token, from as int, lowest as int) {
    def left as Parsed init parseUnary($tokens, $from);
    def at as int init $left.at;
    def node as Expr init $left.node;
    while ($at < len($tokens)) {
        def symbol as string init operatorSymbol($tokens[$at]);
        def precedence as int init precedenceOf($symbol);
        if ($precedence == 0 or $precedence < $lowest) {
            break;
        }
        # Every operator is left-associative, `^` included. That is not what
        # a programming language does, and it is worth stating because it is
        # easy to "fix" into a bug: checked against LibreOffice and Gnumeric,
        # `2^3^2` is 64, so it groups as `(2^3)^2` and not `2^(3^2)`.
        def next as int init $precedence + 1;
        def right as Parsed init parseBinary($tokens, $at + 1, $next);
        def parts as list of Expr init [];
        $parts[] = $node;
        $parts[] = $right.node;
        $node = Expr.Binary{symbol: $symbol, parts: $parts};
        $at = $right.at;
    }
    return Parsed{node: $node, at: $at};
}

/**
 * Parse a prefix operator, or fall through to a primary.
 *
 * Unary minus binds *tighter* than `^` in a spreadsheet, which is why
 * `-2^2` is 4 and not -4: this parses the operand, and `^` then applies to
 * the already-negated value.
 *
 * @param tokens {list of Token} the whole formula
 * @param at {int} the next token to read
 * @return {Parsed} the expression and where parsing stopped
 * @throws {Error} kind "sheets" when the tokens do not form an expression
 */
func parseUnary(tokens as list of Token, at as int) {
    if ($at >= len($tokens)) {
        fail("the formula ends where a value was expected");
    }
    def symbol as string init operatorSymbol($tokens[$at]);
    if ($symbol == "-" or $symbol == "+") {
        def operand as Parsed init parseUnary($tokens, $at + 1);
        def parts as list of Expr init [];
        $parts[] = $operand.node;
        return Parsed{node: Expr.Unary{symbol: $symbol, parts: $parts}, at: $operand.at};
    }
    return parsePostfix($tokens, $at);
}

/**
 * Parse a primary, then any trailing `%`.
 *
 * `%` is a postfix operator meaning "divide by a hundred", and it binds
 * tighter than anything else.
 *
 * @param tokens {list of Token} the whole formula
 * @param at {int} the next token to read
 * @return {Parsed} the expression and where parsing stopped
 * @throws {Error} kind "sheets" when the tokens do not form an expression
 */
func parsePostfix(tokens as list of Token, at as int) {
    def inner as Parsed init parsePrimary($tokens, $at);
    def cursor as int init $inner.at;
    def node as Expr init $inner.node;
    while ($cursor < len($tokens) and
        operatorSymbol($tokens[$cursor]) == "%") {
        def parts as list of Expr init [];
        $parts[] = $node;
        $node = Expr.Unary{symbol: "%", parts: $parts};
        $cursor = $cursor + 1;
    }
    return Parsed{node: $node, at: $cursor};
}

/**
 * Parse a literal, a reference, a bracketed expression or a call.
 *
 * @param tokens {list of Token} the whole formula
 * @param at {int} the next token to read
 * @return {Parsed} the expression and where parsing stopped
 * @throws {Error} kind "sheets" when the tokens do not form an expression
 */
func parsePrimary(tokens as list of Token, at as int) {
    if ($at >= len($tokens)) {
        fail("the formula ends where a value was expected");
    }
    def token as Token init $tokens[$at];
    def after as int init $at + 1;
    match ($token) {
        when Number(n) { return Parsed{node: Expr.Num{amount: $n.amount}, at: $after}; }
        when Text(t) { return Parsed{node: Expr.Str{body: $t.body}, at: $after}; }
        when Logical(l) {
            # `TRUE` and `TRUE()` are both the literal. The bare form is far
            # more common in a file, so the lexer makes it a literal and the
            # empty argument list is swallowed here rather than making every
            # bare `TRUE` go through the call path.
            return Parsed{node: Expr.Logic{flag: $l.flag}, at: skipEmptyCall($tokens, $after)};
        }
        when ErrorToken(e) { return Parsed{node: Expr.ErrLit{body: $e.code}, at: $after}; }
        when Reference(r) { return Parsed{node: referenceExpr($r.body), at: $after}; }
        when OpenParen { return parseBracketed($tokens, $at); }
        when Name(nm) { return parseNamed($tokens, $at, $nm.body); }
        else {
            fail("the formula has " + quoted(describeToken($token)) +
                " where a value was expected");
            return Parsed{node: Expr.Num{amount: 0.0}, at: $after};
        }
    }
}

/**
 * Step over an empty argument list, if one follows.
 *
 * @param tokens {list of Token} the whole formula
 * @param at {int} the index just past a primary
 * @return {int} the index past `()`, or `at` when there is none
 */
func skipEmptyCall(tokens as list of Token, at as int) {
    if ($at + 1 < len($tokens) and isOpenParen($tokens[$at]) and
        isCloseParen($tokens[$at + 1])) {
        return $at + 2;
    }
    return $at;
}

/**
 * Parse a bracketed expression.
 *
 * @param tokens {list of Token} the whole formula
 * @param at {int} the index of the `(`
 * @return {Parsed} the expression and where parsing stopped
 * @throws {Error} kind "sheets" when the bracket is not closed
 */
func parseBracketed(tokens as list of Token, at as int) {
    def inner as Parsed init parseBinary($tokens, $at + 1, 1);
    if ($inner.at >= len($tokens) or not isCloseParen($tokens[$inner.at])) {
        fail("a bracket opened in the formula is never closed");
    }
    return Parsed{node: $inner.node, at: $inner.at + 1};
}

/**
 * Parse a name: a function call when a `(` follows, a defined name otherwise.
 *
 * @param tokens {list of Token} the whole formula
 * @param from {int} the index of the name
 * @param name {string} the name
 * @return {Parsed} the expression and where parsing stopped
 * @throws {Error} kind "sheets" when a call's brackets are unbalanced
 */
func parseNamed(tokens as list of Token, from as int, name as string) {
    def after as int init $from + 1;
    if ($after >= len($tokens) or not isOpenParen($tokens[$after])) {
        return Parsed{node: Expr.NameRef{name: $name}, at: $after};
    }
    def args as list of Expr init [];
    def at as int init $after + 1;
    if ($at < len($tokens) and isCloseParen($tokens[$at])) {
        return Parsed{node: Expr.Call{name: canonicalName($name), parts: $args}, at: $at + 1};
    }
    while (true) {
        def arg as Parsed init parseBinary($tokens, $at, 1);
        $args[] = $arg.node;
        $at = $arg.at;
        if ($at >= len($tokens)) {
            fail("the argument list of " + quoted($name) + " is never closed");
        }
        if (isSeparator($tokens[$at])) {
            $at = $at + 1;
            continue;
        }
        if (isCloseParen($tokens[$at])) {
            return Parsed{node: Expr.Call{name: canonicalName($name), parts: $args}, at: $at + 1};
        }
        fail("the argument list of " + quoted($name) +
            " has a value where a comma or a closing bracket was expected");
    }
    return Parsed{node: Expr.Call{name: $name, parts: $args}, at: $at};
}

/**
 * A function name as the evaluator looks it up.
 *
 * Upper-cased, and the `_xlfn.` prefix newer functions carry is removed: the
 * prefix is a compatibility marker for applications that predate the
 * function, not part of its name.
 *
 * @param name {string} the name as written
 * @return {string} the name to look up
 */
func canonicalName(name as string) {
    def upper as string init strings.upper($name);
    if (strings.startsWith($upper, "_XLFN.")) {
        return strings.substring($upper, 6, len($upper));
    }
    return $upper;
}

/**
 * A reference token as a `Cell` or a `Span`.
 *
 * @param body {string} the reference as written
 * @return {Expr} the node
 */
func referenceExpr(body as string) {
    if (rangeColonAt($body) >= 0) {
        return Expr.Span{body: $body};
    }
    return Expr.Cell{body: $body};
}

/**
 * The symbol an operator token carries, or `""` for any other token.
 *
 * @param token {Token} the token
 * @return {string} the symbol
 */
func operatorSymbol(token as Token) {
    match ($token) {
        when Operator(o) { return $o.symbol; }
        else { return ""; }
    }
}

/**
 * Whether a token is an opening bracket.
 *
 * @param token {Token} the token
 * @return {bool} whether it is
 */
func isOpenParen(token as Token) {
    match ($token) {
        when OpenParen { return true; }
        else { return false; }
    }
}

/**
 * Whether a token is a closing bracket.
 *
 * @param token {Token} the token
 * @return {bool} whether it is
 */
func isCloseParen(token as Token) {
    match ($token) {
        when CloseParen { return true; }
        else { return false; }
    }
}

/**
 * Whether a token separates arguments.
 *
 * @param token {Token} the token
 * @return {bool} whether it is
 */
func isSeparator(token as Token) {
    match ($token) {
        when Separator { return true; }
        else { return false; }
    }
}

/**
 * A token as text, for an error message.
 *
 * @param token {Token} the token
 * @return {string} a short description
 */
func describeToken(token as Token) {
    match ($token) {
        when Number(n) { return numberText($n.amount); }
        when Text(t) { return $t.body; }
        when Logical(l) { return boolText($l.flag); }
        when Reference(r) { return $r.body; }
        when Name(nm) { return $nm.body; }
        when Operator(o) { return $o.symbol; }
        when OpenParen { return "("; }
        when CloseParen { return ")"; }
        when Separator { return ","; }
        when ErrorToken(e) { return $e.code; }
    }
}
