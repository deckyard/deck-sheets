# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for emit.j.
# Spliced into sheets_test.j via include - not a standalone module.

func testTagOpenAndClose() {
    testing.assertEqual(tagOpen("sheetData"), "<sheetData>");
    testing.assertEqual(tagClose("sheetData"), "</sheetData>");
    testing.assertEqual(tagOpen("table:table-row"), "<table:table-row>");
}

func testTagOpenWithAttributes() {
    testing.assertEqual(
        tagOpenWith("row", {"r": "1", "spans": "1:3"}),
        "<row r=\"1\" spans=\"1:3\">");
}

func testAttributeOrderFollowsTheMap() {
    # Insertion-ordered maps are what keep a written file byte-stable.
    testing.assertEqual(
        tagOpenWith("c", {"r": "A1", "t": "s", "s": "2"}),
        "<c r=\"A1\" t=\"s\" s=\"2\">");
}

func testTagEmptySelfCloses() {
    testing.assertEqual(
        tagEmpty("table:table-cell", {"table:number-columns-repeated": "3"}),
        "<table:table-cell table:number-columns-repeated=\"3\"/>");
    testing.assertEqual(tagEmpty("dimension", {}), "<dimension/>");
}

func testTagTextEscapesItsBody() {
    testing.assertEqual(tagText("t", "Widget & Co"), "<t>Widget &amp; Co</t>");
    testing.assertEqual(tagText("t", "<x>"), "<t>&lt;x&gt;</t>");
    testing.assertEqual(tagText("t", ""), "<t></t>");
}

func testTagTextWithEscapesBothHalves() {
    testing.assertEqual(
        tagTextWith("t", {"xml:space": "preserve"}, "a & b"),
        "<t xml:space=\"preserve\">a &amp; b</t>");
}

func testAttributeValuesAreEscaped() {
    testing.assertEqual(
        tagEmpty("sheet", {"name": "a&b\"c<d"}),
        "<sheet name=\"a&amp;b&quot;c&lt;d\"/>");
}

func testPartsBytesJoinsAndEncodes() {
    def parts as list of string init [];
    $parts[] = tagOpen("si");
    $parts[] = tagText("t", "café & crème");
    $parts[] = tagClose("si");
    testing.assertEqual(
        convert.stringFromBytes(partsBytes($parts), "utf-8"),
        "<si><t>café &amp; crème</t></si>");
}

func testPartsBytesOfNothingIsEmpty() {
    def parts as list of string init [];
    testing.assertEqual(len(partsBytes($parts)), 0);
}

func testTheDeclarationIsWellFormed() {
    testing.assertTrue(strings.startsWith(XML_DECLARATION, "<?xml version=\"1.0\""));
    testing.assertTrue(strings.endsWith(XML_DECLARATION, "?>"));
}

func testWhatTheBuildersWriteParsesBack() {
    # The builders write text, not a tree, so nothing but a test proves the
    # output is real XML.
    def parts as list of string init [];
    $parts[] = tagOpen("sheetData");
    $parts[] = tagOpenWith("row", {"r": "1"});
    $parts[] = tagText("v", "Widget & Co <b>");
    $parts[] = tagClose("row");
    $parts[] = tagClose("sheetData");
    def doc as xml.Value init xml.decode(strings.join($parts, ""));
    testing.assertEqual(xml.tag($doc), "sheetData");
    testing.assertEqual(xml.attr(xml.get($doc, "row"), "r"), "1");
    testing.assertEqual(xml.text(xml.get($doc, "row/v")), "Widget & Co <b>");
}

func testBuildingADocumentIsLinearNotQuadratic() {
    # The regression this file exists for. The first design wrapped the pieces
    # in a struct that each builder took and returned, which copies the
    # accumulated list on every call: 8 000 appends measured 14.8 s that way
    # against 4 ms appending into a local list. Appending 20 000 pieces here
    # takes milliseconds, and would take minutes if that design came back.
    def started as time.Time init time.now();
    def parts as list of string init [];
    for (def i in 0..20000) {
        $parts[] = tagEmpty("c", {"r": "A1"});
    }
    def joined as string init strings.join($parts, "");
    def elapsed as int init time.milliseconds(time.sub(time.now(), $started));
    testing.assertEqual(len($parts), 20000);
    testing.assertTrue(len($joined) > 20000);
    testing.assertTrue($elapsed < 5000);
}
