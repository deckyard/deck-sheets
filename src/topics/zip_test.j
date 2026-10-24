# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for zip.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * Some bytes with a known length, for the container tests.
 *
 * @param body {string} the text
 * @return {bytes} the text as UTF-8
 */
func zipBytes(body as string) {
    return convert.bytesFromString($body, "utf-8");
}

func testZipAndUnzipRoundTrip() {
    def members as list of Member init [];
    $members[] = member("content.xml", zipBytes("<x/>"));
    $members[] = member("styles.xml", zipBytes("<y/>"));
    def parts as map of string to bytes init unzip(zip($members));
    testing.assertEqual(len($parts), 2);
    testing.assertEqual(convert.stringFromBytes($parts["content.xml"], "utf-8"), "<x/>");
    testing.assertEqual(convert.stringFromBytes($parts["styles.xml"], "utf-8"), "<y/>");
}

func testAStoredMemberRoundTripsToo() {
    def members as list of Member init [];
    $members[] = storedMember("mimetype", zipBytes("application/x-test"));
    def parts as map of string to bytes init unzip(zip($members));
    testing.assertEqual(convert.stringFromBytes($parts["mimetype"], "utf-8"), "application/x-test");
}

func testTheFirstMemberStaysFirst() {
    # ODF requires mimetype first; the writer must not reorder.
    def members as list of Member init [];
    $members[] = storedMember("mimetype", zipBytes("application/x-test"));
    $members[] = member("content.xml", zipBytes("<x/>"));
    def raw as bytes init zip($members);
    # Compared as byte offsets: a ZIP header is not decodable text.
    def mimetypeAt as int init binary.indexOf($raw, zipBytes("mimetype"));
    def contentAt as int init binary.indexOf($raw, zipBytes("content.xml"));
    testing.assertTrue($mimetypeAt >= 0);
    testing.assertTrue($contentAt >= 0);
    testing.assertTrue($mimetypeAt < $contentAt);
    # And it sits in the first local header, at the fixed offset a sniffer reads.
    testing.assertEqual($mimetypeAt, 30);
}

func testAStoredMemberIsNotCompressed() {
    # The media type has to sit in the clear at a fixed offset, so the bytes
    # must appear verbatim in the archive.
    def members as list of Member init [];
    $members[] = storedMember("mimetype", zipBytes("application/x-marker"));
    def raw as bytes init zip($members);
    testing.assertTrue(binary.contains($raw, zipBytes("application/x-marker")));
}

func testADeflatedMemberIsCompressed() {
    # The same text, deflated, must not appear verbatim.
    def body as string init strings.repeat("compress me ", 40);
    def members as list of Member init [];
    $members[] = member("content.xml", zipBytes($body));
    def raw as bytes init zip($members);
    testing.assertFalse(binary.contains($raw, zipBytes($body)));
    def parts as map of string to bytes init unzip($raw);
    testing.assertEqual(convert.stringFromBytes($parts["content.xml"], "utf-8"), $body);
}

func testAnEmptyMemberRoundTrips() {
    def members as list of Member init [];
    $members[] = member("empty.xml", zipBytes(""));
    def parts as map of string to bytes init unzip(zip($members));
    testing.assertEqual(len($parts["empty.xml"]), 0);
}

func testNestedPathsRoundTrip() {
    def members as list of Member init [];
    $members[] = member("xl/worksheets/sheet1.xml", zipBytes("<a/>"));
    $members[] = member("META-INF/manifest.xml", zipBytes("<b/>"));
    def parts as map of string to bytes init unzip(zip($members));
    testing.assertTrue(maps.has($parts, "xl/worksheets/sheet1.xml"));
    testing.assertTrue(maps.has($parts, "META-INF/manifest.xml"));
}

func testNonAsciiMemberContentRoundTrips() {
    def members as list of Member init [];
    $members[] = member("content.xml", zipBytes("<t>café &amp; crème</t>"));
    def parts as map of string to bytes init unzip(zip($members));
    testing.assertEqual(
        convert.stringFromBytes($parts["content.xml"], "utf-8"),
        "<t>café &amp; crème</t>");
}

func testAnEmptyArchiveIsStillReadable() {
    def members as list of Member init [];
    testing.assertEqual(len(unzip(zip($members))), 0);
}

func testABigMemberRoundTrips() {
    # Exercises the deflate path with something past one buffer.
    def body as string init strings.repeat("0123456789", 20000);
    def members as list of Member init [];
    $members[] = member("big.xml", zipBytes($body));
    def parts as map of string to bytes init unzip(zip($members));
    testing.assertEqual(len($parts["big.xml"]), 200000);
    testing.assertEqual(convert.stringFromBytes($parts["big.xml"], "utf-8"), $body);
}

func testWritingTheSameMembersTwiceGivesTheSameBytes() {
    # The headers carry a zero timestamp rather than the clock, so a golden
    # file stays stable and a rebuild is reproducible.
    def members as list of Member init [];
    $members[] = storedMember("mimetype", zipBytes("application/x-test"));
    $members[] = member("content.xml", zipBytes("<x/>"));
    testing.assertTrue(binary.indexOf(zip($members), zip($members)) == 0);
    testing.assertEqual(len(zip($members)), len(zip($members)));
}

func failOnUnreadableContainer() {
    unzip(convert.bytesFromString("this is not a zip file", "utf-8"));
}

func testUnzipRefusesWhatIsNotAContainer() {
    testing.assertThrows("failOnUnreadableContainer", ERROR_KIND);
}

func testPartTextReadsAMember() {
    def members as list of Member init [];
    $members[] = member("content.xml", zipBytes("<x/>"));
    testing.assertEqual(partText(unzip(zip($members)), "content.xml"), "<x/>");
}

func failOnMissingPart() {
    def members as list of Member init [];
    $members[] = member("content.xml", zipBytes("<x/>"));
    partText(unzip(zip($members)), "styles.xml");
}

func testPartTextRefusesAMissingMember() {
    testing.assertThrows("failOnMissingPart", ERROR_KIND);
}

func testTheMissingPartErrorNamesWhatIsThere() {
    def message as string init "";
    def members as list of Member init [];
    $members[] = member("content.xml", zipBytes("<x/>"));
    try {
        partText(unzip(zip($members)), "styles.xml");
    } catch (e) {
        $message = $e.message;
    }
    testing.assertTrue(strings.contains($message, "content.xml"));
}

/**
 * A container whose directory declares one member of a given size.
 *
 * Hand-assembled rather than written through `zip`, because `zip` would have
 * to actually produce the bytes to declare them honestly - and the point of
 * the guard is to refuse the claim before anything is inflated. Only the
 * end-of-central-directory record and one central header are built, which is
 * all `checkDeclaredSize` reads.
 *
 * @param declared {int} the uncompressed size to claim
 * @param count {int} the member count to claim
 * @return {bytes} the container
 */
func declaringContainer(declared as int, count as int) {
    def name as bytes init zipBytes("big.xml");
    def central as list of bytes init [];
    $central[] = le32(0x02014b50);
    $central[] = le16(20);
    $central[] = le16(20);
    $central[] = le16(0);
    $central[] = le16(0);
    $central[] = le16(0);
    $central[] = le16(0);
    $central[] = le32(0);
    $central[] = le32(16);
    $central[] = le32($declared);
    $central[] = le16(len($name));
    $central[] = le16(0);
    $central[] = le16(0);
    $central[] = le16(0);
    $central[] = le16(0);
    $central[] = le32(0);
    $central[] = le32(0);
    $central[] = $name;
    def directory as bytes init binary.join($central);

    def end as list of bytes init [];
    $end[] = le32(0x06054b50);
    $end[] = le16(0);
    $end[] = le16(0);
    $end[] = le16($count);
    $end[] = le16($count);
    $end[] = le32(len($directory));
    $end[] = le32(0);
    $end[] = le16(0);

    def whole as list of bytes init [];
    $whole[] = $directory;
    $whole[] = binary.join($end);
    return binary.join($whole);
}

func failOnAContainerDeclaringTooMuchContent() {
    unzip(declaringContainer(1073741824, 1));
}

func testUnzipRefusesAContainerThatWouldInflateTooFar() {
    # archive.unpack cannot be bounded, so the declared sizes are summed from
    # the central directory before a byte is inflated. A 1 MB file declaring
    # 1 GiB is refused in milliseconds instead of costing a gigabyte.
    testing.assertThrows("failOnAContainerDeclaringTooMuchContent", ERROR_KIND);
}

func testTheRefusalNamesTheSizeAndTheLimit() {
    def message as string init "";
    try {
        unzip(declaringContainer(1073741824, 1));
    } catch (e) {
        $message = $e.message;
    }
    testing.assertTrue(strings.contains($message, "1073741824"));
    testing.assertTrue(strings.contains($message, convert.toString(MAX_INFLATED)));
}

func testAModestDeclarationPassesTheGuard() {
    # Under the cap the guard says nothing and archive.unpack gives its own
    # error for the (deliberately truncated) container.
    def refused as bool init false;
    def message as string init "";
    try {
        unzip(declaringContainer(1024, 1));
    } catch (e) {
        $refused = true;
        $message = $e.message;
    }
    testing.assertTrue($refused);
    testing.assertFalse(strings.contains($message, "will inflate"));
}

func failOnAContainerWithTooManyMembers() {
    def members as list of Member init [];
    for (def i in 0..(MAX_ENTRIES + 1)) {
        $members[] = member("p" + convert.toString($i) + ".xml", zipBytes("x"));
    }
    unzip(zip($members));
}

func testUnzipRefusesTooManyMembers() {
    testing.assertThrows("failOnAContainerWithTooManyMembers", ERROR_KIND);
}

func testAnOrdinaryContainerPassesTheSizeGuard() {
    def members as list of Member init [];
    $members[] = member("content.xml", zipBytes(strings.repeat("<x/>", 5000)));
    testing.assertEqual(len(unzip(zip($members))), 1);
}

func testFindEndRecordLocatesTheRecord() {
    def members as list of Member init [];
    $members[] = member("a.xml", zipBytes("<a/>"));
    def raw as bytes init zip($members);
    def at as int init findEndRecord($raw);
    testing.assertTrue($at > 0);
    testing.assertEqual(readLe32($raw, $at), 0x06054b50);
    testing.assertEqual(readLe16($raw, $at + 10), 1);
}

func testTheLittleEndianReadersAreBoundsChecked() {
    def raw as bytes init zipBytes("ab");
    testing.assertEqual(readLe16($raw, 0), 0x6261);
    testing.assertEqual(readLe16($raw, 1), 0);
    testing.assertEqual(readLe32($raw, 0), 0);
    testing.assertEqual(readLe16($raw, -1), 0);
    testing.assertEqual(readLe32($raw, -4), 0);
}

func testFindEndRecordOnSomethingThatIsNotAContainer() {
    testing.assertEqual(findEndRecord(zipBytes("not a zip at all")), -1);
    testing.assertEqual(findEndRecord(zipBytes("")), -1);
}
