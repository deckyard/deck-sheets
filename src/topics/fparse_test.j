# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for fparse.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * Print an expression tree as a prefix form.
 *
 * Precedence and associativity are the whole point of a parser, and they are
 * invisible in an infix rendering. A prefix string makes the shape of the
 * tree the thing the test asserts on.
 *
 * @param e {Expr} the tree
 * @return {string} the tree in prefix form
 */
func prefixOf(e as Expr) {
    match ($e) {
        when Num(n) { return convert.toString($n.amount); }
        when Str(s) { return "\"" + $s.body + "\""; }
        when Logic(l) { return convert.toString($l.flag); }
        when ErrLit(x) { return $x.body; }
        when Cell(c) { return $c.body; }
        when Span(sp) { return $sp.body; }
        when NameRef(nr) { return "@" + $nr.name; }
        when Unary(u) { return "(" + $u.symbol + " " + prefixParts($u.parts) + ")"; }
        when Binary(b) { return "(" + $b.symbol + " " + prefixParts($b.parts) + ")"; }
        when Call(c) { return "[" + $c.name + " " + prefixParts($c.parts) + "]"; }
    }
}

/**
 * Render a list of sub-expressions, space separated.
 *
 * @param parts {list of Expr} the sub-expressions
 * @return {string} the rendered parts
 */
func prefixParts(parts as list of Expr) {
    def out as list of string init [];
    for (def p in $parts) {
        $out[] = prefixOf($p);
    }
    return strings.join($out, " ");
}

/**
 * Assert the shape a formula parses to.
 *
 * @param source {string} the formula
 * @param shape {string} the expected prefix form
 */
func assertParse(source as string, shape as string) {
    testing.assertEqual(prefixOf(parseFormula($source)), $shape);
}

func testParseLiterals() {
    assertParse("1", "1.0");
    assertParse("12.5", "12.5");
    assertParse("\"abc\"", "\"abc\"");
    assertParse("TRUE", "true");
    assertParse("FALSE", "false");
    assertParse("#DIV/0!", "#DIV/0!");
}

func testParseReferences() {
    assertParse("A1", "A1");
    assertParse("$B$3", "$B$3");
    assertParse("Sheet2!A1", "Sheet2!A1");
    assertParse("A1:B2", "A1:B2");
}

func testParseArithmeticIsLeftAssociative() {
    assertParse("1+2+3", "(+ (+ 1.0 2.0) 3.0)");
    assertParse("1-2-3", "(- (- 1.0 2.0) 3.0)");
    assertParse("8/4/2", "(/ (/ 8.0 4.0) 2.0)");
}

func testParsePrecedence() {
    assertParse("1+2*3", "(+ 1.0 (* 2.0 3.0))");
    assertParse("1*2+3", "(+ (* 1.0 2.0) 3.0)");
    # `&` binds looser than arithmetic and tighter than comparison.
    assertParse("1+2&3", "(& (+ 1.0 2.0) 3.0)");
    assertParse("1&2=3", "(= (& 1.0 2.0) 3.0)");
    assertParse("2+3*4^2", "(+ 2.0 (* 3.0 (^ 4.0 2.0)))");
}

func testParsePowerIsLeftAssociative() {
    # `2^3^2` is 64 in both LibreOffice and Gnumeric, so the tree leans left -
    # the opposite of most programming languages. Verified against both before
    # this was written, because the first implementation had it the other way.
    assertParse("2^3^2", "(^ (^ 2.0 3.0) 2.0)");
}

func testParseUnaryMinusBindsTighterThanPower() {
    # `-2^2` is 4, not -4: the negation happens first.
    assertParse("-2^2", "(^ (- 2.0) 2.0)");
    assertParse("-A1", "(- A1)");
    assertParse("--1", "(- (- 1.0))");
    assertParse("+1", "(+ 1.0)");
}

func testParsePercentIsPostfix() {
    assertParse("50%", "(% 50.0)");
    assertParse("50%*2", "(* (% 50.0) 2.0)");
}

func testParseBrackets() {
    assertParse("(1+2)*3", "(* (+ 1.0 2.0) 3.0)");
    assertParse("((1))", "1.0");
}

func testParseCalls() {
    assertParse("SUM(A1:A5)", "[SUM A1:A5]");
    assertParse("IF(A1>0,1,2)", "[IF (> A1 0.0) 1.0 2.0]");
    assertParse("NOW()", "[NOW ]");
    assertParse("SUM(1,SUM(2,3))", "[SUM 1.0 [SUM 2.0 3.0]]");
}

func testParseBooleanCallForm() {
    # `TRUE` and `TRUE()` mean the same thing, and the lexer makes both the
    # literal, so the empty argument list has to be swallowed by the parser.
    assertParse("TRUE()", "true");
    assertParse("FALSE()", "false");
    assertParse("NOT(TRUE())", "[NOT true]");
}

func testParseAcceptsALeadingEquals() {
    # The formats and users both write the `=`; the model stores the
    # expression without it. Accepting it saves every caller a strip.
    assertParse("=1+2", "(+ 1.0 2.0)");
    assertParse(" = A1", "A1");
}

func testParseStripsTheXlfnPrefix() {
    # Excel writes newer functions as `_xlfn.XOR`; the name we dispatch on is
    # the bare one.
    assertParse("_xlfn.XOR(TRUE,FALSE)", "[XOR true false]");
}

func testParseNames() {
    # A bare name that is not a call is a defined-name reference, which the
    # evaluator reports as `#NAME?` rather than the parser refusing it.
    assertParse("Total", "@Total");
}

func failOnEmptyFormula() {
    parseFormula("");
}

func failOnBareEquals() {
    parseFormula("=");
}

func failOnLeftoverTokens() {
    parseFormula("1 2");
}

func failOnMissingOperand() {
    parseFormula("1+");
}

func failOnUnclosedBracket() {
    parseFormula("SUM(A1");
}

func failOnUnopenedBracket() {
    parseFormula("1)");
}

func failOnEmptyBrackets() {
    parseFormula("()");
}

func testParseRejectsMalformedFormulas() {
    testing.assertThrows("failOnEmptyFormula", ERROR_KIND);
    testing.assertThrows("failOnBareEquals", ERROR_KIND);
    testing.assertThrows("failOnLeftoverTokens", ERROR_KIND);
    testing.assertThrows("failOnMissingOperand", ERROR_KIND);
    testing.assertThrows("failOnUnclosedBracket", ERROR_KIND);
    testing.assertThrows("failOnUnopenedBracket", ERROR_KIND);
    testing.assertThrows("failOnEmptyBrackets", ERROR_KIND);
}

func failOnDeeplyNestedFormula() {
    # A formula nested past the depth cap must be refused rather than
    # exhausting the interpreter's own stack.
    def source as string init "";
    for (def i in 0..200) {
        $source = $source + "(";
    }
    $source = $source + "1";
    for (def i in 0..200) {
        $source = $source + ")";
    }
    parseFormula($source);
}

func testParseRefusesRunawayNesting() {
    testing.assertThrows("failOnDeeplyNestedFormula", ERROR_KIND);
}

func failOnAWideFormula() {
    # Parsing is quadratic in a formula's width, so the width is capped as
    # well as the depth. See MAX_FORMULA_TOKENS.
    def terms as list of string init [];
    for (def i in 0..MAX_FORMULA_TOKENS) {
        $terms[] = "1";
    }
    parseFormula(strings.join($terms, "+"));
}

func testParseRefusesAFormulaWiderThanTheCap() {
    testing.assertThrows("failOnAWideFormula", ERROR_KIND);
    # 512 is far past any formula a person writes, and the cap applies only
    # to evaluation - a file's formulas are stored as text and never parsed.
    testing.assertEqual(MAX_FORMULA_TOKENS, 512);
}

func testParseAcceptsAFormulaUpToTheCap() {
    def terms as list of string init [];
    for (def i in 0..200) {
        $terms[] = "1";
    }
    def tree as Expr init parseFormula(strings.join($terms, "+"));
    # Left-leaning, so the outermost node is the last operator.
    match ($tree) {
        when Binary(b) { testing.assertEqual($b.symbol, "+"); }
        else {
            throw Error{
                kind: "test",
                message: "a chain of additions is a Binary",
                file: "",
                line: 0,
                col: 0
            };
        }
    }
}
