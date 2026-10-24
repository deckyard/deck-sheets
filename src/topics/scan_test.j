# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - white-box tests for the scan topic.
#
# The fixtures are the markup this deck actually meets: OOXML worksheets and
# ODS tables, prefixed and not. Where a test exists for a boundary case, the
# names are chosen so the collision is a real one - <row> against <rowBreaks>,
# <c> against <cols> - because that is the case the scanner has to get right.
# Spliced into sheets_test.j via include - run with:
#   jennifer test src/sheets_test.j

/** A string as the byte buffer the scanner works on. */
func buffer(text as string) {
    return convert.bytesFromString($text, "utf-8");
}

/** The direct children of a document's root element. */
func rootChildren(text as string) {
    def src as bytes init buffer($text);
    def root as Node init rootNode($src);
    return childNodes($src, $root.openEnd, $root.innerEnd);
}

func testRootNodeFindsTheRootPastThePrologue() {
    def src as bytes init buffer("<?xml version=\"1.0\"?>\n<!-- note -->\n<worksheet></worksheet>");
    testing.assertEqual(rootNode($src).name, "worksheet");
}

func testRootNodeSkipsADoctype() {
    def src as bytes init buffer("<!DOCTYPE x><office:document-content></office:document-content>");
    testing.assertEqual(rootNode($src).name, "office:document-content");
}

func failOnNoElement() {
    rootNode(buffer("<?xml version=\"1.0\"?><!-- nothing here -->"));
}

func testRootNodeOfADocumentWithNoElement() {
    testing.assertThrows("failOnNoElement", ERROR_KIND);
}

func testChildNodesFindsDirectChildrenOnly() {
    def doc as string init "<sheetData><row><c>A</c></row><row /><cols></cols></sheetData>";
    def kids as list of Node init rootChildren($doc);
    testing.assertEqual(len($kids), 3);
    testing.assertEqual($kids[0].name, "row");
    testing.assertEqual($kids[1].name, "row");
    testing.assertEqual($kids[2].name, "cols");
}

func testChildNodesTellsATagFromAPrefixOfIt() {
    # <row> and <rowBreaks> share four characters; a scanner that matched on the
    # prefix would see the wrong boundaries
    def kids as list of Node init rootChildren("<worksheet><rowBreaks /><row /></worksheet>");
    testing.assertEqual($kids[0].name, "rowBreaks");
    testing.assertEqual($kids[1].name, "row");
}

func testChildNodesCountsNestingOfTheSameName() {
    def doc as string init "<body><table><table><row /></table>" +
        "</table><table /></body>";
    def src as bytes init buffer($doc);
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    # two outer tables, not four: the nested one does not close the outer one
    testing.assertEqual(len($kids), 2);
    def inner as list of Node init childNodes($src, $kids[0].openEnd, $kids[0].innerEnd);
    testing.assertEqual(len($inner), 1);
    testing.assertEqual($inner[0].name, "table");
}

func testChildNodesSkipsCommentsAndInstructions() {
    def doc as string init "<sheetData><!-- <row /> --><?php echo 1; ?><row /></sheetData>";
    def kids as list of Node init rootChildren($doc);
    # the commented-out row is not an element
    testing.assertEqual(len($kids), 1);
}

func testChildNodesSkipsCdata() {
    def kids as list of Node init rootChildren("<sheetData><![CDATA[<row />]]><cols /></sheetData>");
    testing.assertEqual(len($kids), 1);
    testing.assertEqual($kids[0].name, "cols");
}

func testChildNodesIsNotFooledByAGreaterThanInAnAttribute() {
    def kids as list of Node init rootChildren("<sheetData><row desc=\"a > b\" /><cols /></sheetData>");
    testing.assertEqual(len($kids), 2);
    testing.assertEqual($kids[0].name, "row");
    testing.assertEqual($kids[1].name, "cols");
}

func testChildNodesRecoversFromATruncatedDocument() {
    # a writer that was cut off mid-stream: the elements before the damage
    # still read back rather than the whole file being refused
    def kids as list of Node init rootChildren("<sheetData><row /><cols><col>");
    testing.assertEqual(len($kids), 2);
    testing.assertEqual($kids[0].name, "row");
    testing.assertEqual($kids[1].name, "cols");
}

func testChildNodesIgnoresATruncatedOpenTag() {
    # no closing angle bracket at all: there is no name or attribute to read
    def kids as list of Node init rootChildren("<sheetData><row /><cols");
    testing.assertEqual(len($kids), 1);
    testing.assertEqual($kids[0].name, "row");
}

func testTheScannerRecoversTheLeavesBeforeTheDamage() {
    # A document cut off mid-stream still yields every complete leaf that
    # arrived before the truncation, rather than the whole file being refused.
    def src as bytes init buffer("<sheetData><row r=\"1\" /><row r=\"2\" /><row r=\"3\"");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(len($kids), 2);
    testing.assertEqual(nodeAttr($src, $kids[0], "r"), "1");
    testing.assertEqual(nodeAttr($src, $kids[1], "r"), "2");
}

func testNodeTextReadsCharacterData() {
    def src as bytes init buffer("<si><t>  Widget and Co  </t></si>");
    def kids as list of Node init childNodes($src, rootNode($src).openEnd, rootNode($src).innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "Widget and Co");
}

func testNodeTextResolvesEntities() {
    def src as bytes init buffer("<si><t>Ca&#241;on &amp; Rim</t></si>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "Cañon & Rim");
}

func testNodeTextReadsCdata() {
    def src as bytes init buffer("<si><t><![CDATA[a < b & c]]></t></si>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    # a CDATA section is verbatim: the entities inside it are not entities
    testing.assertEqual(nodeText($src, $kids[0]), "a < b & c");
}

func testNodeTextDropsMarkupItDoesNotModel() {
    def src as bytes init buffer("<si><t>a <b>bold</b> word</t></si>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "a bold word");
}

func testNodeTextOfAnEmptyElement() {
    def src as bytes init buffer("<si><t /><t></t></si>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "");
    testing.assertEqual(nodeText($src, $kids[1]), "");
}

func testNodeAttrReadsEitherQuote() {
    def src as bytes init buffer("<row><c r=\"A1\" t='s' /></row>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "r"), "A1");
    testing.assertEqual(nodeAttr($src, $kids[0], "t"), "s");
}

func testNodeAttrIsEmptyWhenAbsent() {
    def src as bytes init buffer("<row><c r=\"A1\" /></row>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "t"), "");
}

func testNodeAttrIgnoresAPrefixAndResolvesEntities() {
    def src as bytes init buffer("<row><c office:value=\"47.2692\" desc=\"a &amp; b\" /></row>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    # ODS prefixes everything, so a lookup for "value" has to find
    # "office:value".
    testing.assertEqual(nodeAttr($src, $kids[0], "value"), "47.2692");
    testing.assertEqual(nodeAttr($src, $kids[0], "desc"), "a & b");
}

func testNodeAttrSurvivesAwkwardSpacing() {
    def src as bytes init buffer("<row><c\n   r = \"A1\"\n   t=\"s\"\n/></row>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "r"), "A1");
    testing.assertEqual(nodeAttr($src, $kids[0], "t"), "s");
}

func testNodeAttrDoesNotReadTheChildrensAttributes() {
    def src as bytes init buffer("<sheetData><row><c r=\"A1\" /></row></sheetData>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "");
}

func testFindChildAndFindChildren() {
    def src as bytes init buffer("<sheetData><row /><cols /><row /></sheetData>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertTrue(isNode(findChild($kids, "cols")));
    testing.assertFalse(isNode(findChild($kids, "nope")));
    testing.assertEqual(len(findChildren($kids, "row")), 2);
    testing.assertEqual(len(findChildren($kids, "nope")), 0);
}

func testFindChildMatchesOnTheLocalName() {
    def src as bytes init buffer("<table:table><table:table-row /></table:table>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertTrue(isNode(findChild($kids, "table-row")));
}

func testChildTextIsEmptyForAMissingChild() {
    def src as bytes init buffer("<si><t>A</t></si>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(childText($src, $kids, "t"), "A");
    testing.assertEqual(childText($src, $kids, "v"), "");
}

func testNodeBytesCutsOutAWholeElement() {
    def src as bytes init buffer("<row><c r=\"A1\"><v>A</v></c></row>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeBytes($src, $kids[0]), "<c r=\"A1\"><v>A</v></c>");
}

func testMatchesAtAndIndexOfByte() {
    def src as bytes init buffer("<sheetData><row /></sheetData>");
    testing.assertTrue(matchesAt($src, 0, probeOf("<sheetData")));
    testing.assertFalse(matchesAt($src, 1, probeOf("<sheetData")));
    testing.assertFalse(matchesAt($src, -1, probeOf("<")));
    testing.assertFalse(matchesAt($src, 16, probeOf("</nope>")));
    testing.assertEqual(indexOfByte($src, LT_PROBE, 0, len($src)), 0);
    # "<sheetData>" is 11 bytes, so the next "<" opens <row at 11
    testing.assertEqual(indexOfByte($src, LT_PROBE, 1, len($src)), 11);
    # the limit is applied to the answer, not just to where the search starts
    testing.assertEqual(indexOfByte($src, LT_PROBE, 1, 3), -1);
    testing.assertEqual(indexOfByte($src, LT_PROBE, 0, 0), -1);
}

func testProbeOf() {
    testing.assertEqual(probeOf("<"), LT_PROBE);
    testing.assertEqual(len(probeOf("<![CDATA[")), 9);
}

func testIsNameEndAndIsSpace() {
    testing.assertTrue(isNameEnd(GT));
    testing.assertTrue(isNameEnd(SLASH));
    testing.assertTrue(isNameEnd(0x20));
    testing.assertFalse(isNameEnd(0x61));
    testing.assertTrue(isSpace(" "));
    testing.assertTrue(isSpace("\n"));
    testing.assertFalse(isSpace("a"));
}

func testNodeAttrReadsAnUnquotedValue() {
    # not well-formed XML, but hand-edited files carry it and it costs nothing
    def src as bytes init buffer("<row><c r=A1 t=s /></row>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "r"), "A1");
    testing.assertEqual(nodeAttr($src, $kids[0], "t"), "s");
}

func testNodeAttrDoesNotMatchANameInsideAnother() {
    # "spans" ends in "s"; a search for the attribute "s" must not find it.
    def src as bytes init buffer("<row><c spans=\"1:3\" s=\"7\" /></row>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "s"), "7");
}

func testSkipSpaceBytesAndIsSpaceByte() {
    def src as bytes init buffer("a   b");
    testing.assertEqual(skipSpaceBytes($src, 1, len($src)), 4);
    testing.assertEqual(skipSpaceBytes($src, 0, len($src)), 0);
    testing.assertEqual(skipSpaceBytes($src, 1, 2), 2);
    testing.assertTrue(isSpaceByte(0x20));
    testing.assertFalse(isSpaceByte(0x61));
}

func testTextOnlyAndCdataText() {
    testing.assertEqual(textOnly("a <b>c</b> d"), "a c d");
    testing.assertEqual(textOnly("plain"), "plain");
    testing.assertEqual(cdataText("<![CDATA[one]]> and <![CDATA[two]]>"), "onetwo");
    # an unterminated section keeps what is left of it
    testing.assertEqual(cdataText("<![CDATA[tail"), "tail");
}

func testSkipPastStopsAtTheLimit() {
    def src as bytes init buffer("<!-- comment --><row />");
    testing.assertEqual(skipPast($src, 0, "-->", len($src)), 16);
    # the literal is past the limit, so the limit is the answer
    testing.assertEqual(skipPast($src, 0, "-->", 5), 5);
    testing.assertEqual(skipPast($src, 0, "nowhere", len($src)), len($src));
}

func testByteTextOfAnEmptyRange() {
    def src as bytes init buffer("<row />");
    testing.assertEqual(byteText($src, 3, 3), "");
    testing.assertEqual(byteText($src, 5, 3), "");
    testing.assertEqual(byteText($src, 1, 4), "row");
}
