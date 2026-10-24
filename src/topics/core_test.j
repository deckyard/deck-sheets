# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for core.j.
# Spliced into sheets_test.j via include - not a standalone module.

func testFailCarriesTheDeckKind() {
    def kind as string init "";
    def message as string init "";
    try {
        fail("nope");
    } catch (e) {
        $kind = $e.kind;
        $message = $e.message;
    }
    testing.assertEqual($kind, "sheets");
    testing.assertEqual($message, "nope");
}

func testQuotedWrapsShortText() {
    testing.assertEqual(quoted("A1"), "\"A1\"");
    testing.assertEqual(quoted(""), "\"\"");
}

func testQuotedBoundsLongText() {
    def long as string init strings.repeat("x", 500);
    def out as string init quoted($long);
    testing.assertTrue(len($out) < 100);
    testing.assertTrue(strings.contains($out, "500 characters"));
}

func testCheckDepthAllowsTheCap() {
    checkDepth(MAX_NESTING, "row");
}

func failOnTooDeep() {
    checkDepth(MAX_NESTING + 1, "row");
}

func testCheckDepthRefusesPastTheCap() {
    testing.assertThrows("failOnTooDeep", ERROR_KIND);
}

func testLocalNameStripsAPrefix() {
    testing.assertEqual(localName("table:table-row"), "table-row");
    testing.assertEqual(localName("office:value-type"), "value-type");
}

func testLocalNameLeavesAnUnprefixedName() {
    testing.assertEqual(localName("row"), "row");
    testing.assertEqual(localName(""), "");
}

func testXmlEscapeWritesAllFiveEntities() {
    testing.assertEqual(xmlEscape("a&b"), "a&amp;b");
    testing.assertEqual(xmlEscape("<x>"), "&lt;x&gt;");
    testing.assertEqual(xmlEscape("\"q\""), "&quot;q&quot;");
    testing.assertEqual(xmlEscape("it's"), "it&apos;s");
}

func testXmlEscapeEscapesTheAmpersandFirst() {
    # Escaping "<" before "&" would turn "a<b" into "a&amp;lt;b".
    testing.assertEqual(xmlEscape("a<b&c"), "a&lt;b&amp;c");
}

func testXmlUnescapeResolvesNamedEntities() {
    testing.assertEqual(xmlUnescape("Widget &amp; Co"), "Widget & Co");
    testing.assertEqual(xmlUnescape("&lt;x&gt;"), "<x>");
    testing.assertEqual(xmlUnescape("&quot;q&quot;"), "\"q\"");
    testing.assertEqual(xmlUnescape("it&apos;s"), "it's");
}

func testXmlUnescapeResolvesNumericReferences() {
    testing.assertEqual(xmlUnescape("caf&#233;"), "café");
    testing.assertEqual(xmlUnescape("caf&#xe9;"), "café");
    testing.assertEqual(xmlUnescape("caf&#xE9;"), "café");
}

func testXmlUnescapeLeavesAnUnknownEntityStanding() {
    # Deliberate: an exporter writing &nbsp; should not make a file unreadable.
    testing.assertEqual(xmlUnescape("a&nbsp;b"), "a&nbsp;b");
    testing.assertEqual(xmlUnescape("a&b"), "a&b");
    testing.assertEqual(xmlUnescape("50% &#; off"), "50% &#; off");
}

func testXmlUnescapePassesTextWithNoAmpersand() {
    testing.assertEqual(xmlUnescape("plain text"), "plain text");
}

func testXmlRoundTrip() {
    def raw as string init "a & b < c > d \" e ' f";
    testing.assertEqual(xmlUnescape(xmlEscape($raw)), $raw);
}

func testEntityBodyRejectsAnUnknownName() {
    testing.assertEqual(entityBody("nbsp"), "");
    testing.assertEqual(entityBody(""), "");
}

func testNumericEntityRejectsNonNumeric() {
    testing.assertEqual(numericEntity("#zz"), "");
    testing.assertEqual(numericEntity("#xzz"), "");
    testing.assertEqual(numericEntity("abc"), "");
    testing.assertEqual(numericEntity("#0"), "");
}
