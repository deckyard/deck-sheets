# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for flex.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * Name a token's variant, so a lexing can be stated in one readable line.
 *
 * @param t {Token} the token
 * @return {string} a short tag, plus the payload where there is one
 */
func tokenTag(t as Token) {
    match ($t) {
        when Number(n) { return "num:" + convert.toString($n.amount); }
        when Text(s) { return "txt:" + $s.body; }
        when Logical(l) { return "log:" + convert.toString($l.flag); }
        when ErrorToken(e) { return "err:" + $e.code; }
        when Name(nm) { return "name:" + $nm.body; }
        when Reference(r) { return "ref:" + $r.body; }
        when Operator(o) { return "op:" + $o.symbol; }
        when OpenParen { return "("; }
        when CloseParen { return ")"; }
        when Separator { return "sep"; }
    }
}

/**
 * Lex a formula into a list of tags.
 *
 * @param source {string} the formula
 * @return {list of string} one tag per token
 */
func tagsOf(source as string) {
    def out as list of string init [];
    for (def t in tokenize($source)) {
        $out[] = tokenTag($t);
    }
    return $out;
}

func testTokenizeNumbers() {
    testing.assertEqual(tagsOf("1"), ["num:1.0"]);
    testing.assertEqual(tagsOf("12.5"), ["num:12.5"]);
    testing.assertEqual(tagsOf(".5"), ["num:0.5"]);
    testing.assertEqual(tagsOf("1e3"), ["num:1000.0"]);
    testing.assertEqual(tagsOf("1E-2"), ["num:0.01"]);
}

func testTokenizeOperators() {
    testing.assertEqual(tagsOf("1+2"), ["num:1.0", "op:+", "num:2.0"]);
    testing.assertEqual(tagsOf("A1>=B1"), ["ref:A1", "op:>=", "ref:B1"]);
    testing.assertEqual(tagsOf("A1<>B1"), ["ref:A1", "op:<>", "ref:B1"]);
    # `<` must not swallow what follows unless it is `=` or `>`.
    testing.assertEqual(tagsOf("1<2"), ["num:1.0", "op:<", "num:2.0"]);
    testing.assertEqual(tagsOf("A1&B1"), ["ref:A1", "op:&", "ref:B1"]);
    testing.assertEqual(tagsOf("2^3"), ["num:2.0", "op:^", "num:3.0"]);
    testing.assertEqual(tagsOf("B1%"), ["ref:B1", "op:%"]);
    testing.assertEqual(tagsOf("-A1"), ["op:-", "ref:A1"]);
}

func testTokenizeStrings() {
    testing.assertEqual(tagsOf("\"abc\""), ["txt:abc"]);
    # A doubled quote is one literal quote, not the end of the string.
    testing.assertEqual(tagsOf("\"a\"\"b\""), ["txt:a\"b"]);
    testing.assertEqual(tagsOf("\"\""), ["txt:"]);
}

func testTokenizeErrorLiterals() {
    testing.assertEqual(tagsOf("#DIV/0!"), ["err:#DIV/0!"]);
    testing.assertEqual(tagsOf("#N/A"), ["err:#N/A"]);
    testing.assertEqual(tagsOf("#NAME?"), ["err:#NAME?"]);
    testing.assertEqual(tagsOf("#REF!"), ["err:#REF!"]);
    testing.assertEqual(tagsOf("#VALUE!"), ["err:#VALUE!"]);
    testing.assertEqual(tagsOf("#NUM!"), ["err:#NUM!"]);
}

func testTokenizeBooleans() {
    # A bare TRUE is the literal; the parser swallows the `()` of a call form.
    testing.assertEqual(tagsOf("TRUE"), ["log:true"]);
    testing.assertEqual(tagsOf("false"), ["log:false"]);
}

func testTokenizeReferencesAndNames() {
    testing.assertEqual(tagsOf("A1"), ["ref:A1"]);
    testing.assertEqual(tagsOf("$B$3"), ["ref:$B$3"]);
    testing.assertEqual(tagsOf("SUM"), ["name:SUM"]);
    testing.assertEqual(tagsOf("Sheet2!A1"), ["ref:Sheet2!A1"]);
    testing.assertEqual(tagsOf("'Other Sheet'!A1"), ["ref:'Other Sheet'!A1"]);
    # A range is one token: the colon binds tighter than anything else and
    # never appears outside a reference.
    testing.assertEqual(tagsOf("A1:B2"), ["ref:A1:B2"]);
}

func testTokenizeStructure() {
    testing.assertEqual(tagsOf("SUM(A1:B2)"), ["name:SUM", "(", "ref:A1:B2", ")"]);
    testing.assertEqual(
        tagsOf("IF(A1,1,2)"),
        ["name:IF", "(", "ref:A1", "sep", "num:1.0", "sep", "num:2.0", ")"]);
    # A semicolon separates arguments too, because that is what an
    # OpenFormula file carries.
    testing.assertEqual(tagsOf("SUM(1;2)"), ["name:SUM", "(", "num:1.0", "sep", "num:2.0", ")"]);
}

func testTokenizeSkipsWhitespace() {
    testing.assertEqual(tagsOf("  1 +  2 "), ["num:1.0", "op:+", "num:2.0"]);
    testing.assertEqual(tagsOf(""), []);
}

func failOnUnterminatedString() {
    tokenize("\"abc");
}

func failOnStrayCharacter() {
    tokenize("1 ~ 2");
}

func failOnUnknownErrorLiteral() {
    tokenize("#NOPE!");
}

func testTokenizeRejectsMalformedInput() {
    testing.assertThrows("failOnUnterminatedString", ERROR_KIND);
    testing.assertThrows("failOnStrayCharacter", ERROR_KIND);
    testing.assertThrows("failOnUnknownErrorLiteral", ERROR_KIND);
}

func testErrorCodeConstants() {
    # The spellings are fixed by the formats and by what applications show,
    # not chosen here, so pinning them guards against a typo reaching a file.
    testing.assertEqual(ERR_DIV0, "#DIV/0!");
    testing.assertEqual(ERR_VALUE, "#VALUE!");
    testing.assertEqual(ERR_REF, "#REF!");
    testing.assertEqual(ERR_NAME, "#NAME?");
    testing.assertEqual(ERR_NUM, "#NUM!");
    testing.assertEqual(ERR_NA, "#N/A");
    testing.assertEqual(ERR_CIRCULAR, ERR_REF);
}
