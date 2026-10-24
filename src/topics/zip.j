# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the ZIP container ODS and XLSX are packaged in.
# Spliced into sheets.j via include - not a standalone module.

/**
 * One member of an archive, on its way in.
 *
 * `stored` is the reason this file exists. ODF requires the `mimetype` member
 * to come first **and be stored uncompressed**, so that a magic-byte sniffer
 * finds the media type at a fixed offset. `archive.pack` preserves order but
 * always deflates with no per-entry control, and the file it produces is
 * identified as a generic ZIP rather than a spreadsheet. So the writer here
 * emits the headers itself. The measurement is in `docs/internal/zip.md`.
 *
 * @field name {string} the member path, forward slashes, no leading slash
 * @field data {bytes} the member's contents
 * @field stored {bool} whether to store it uncompressed rather than deflate it
 */
def struct Member {
    name as string,
    data as bytes,
    stored as bool
};

/** The local file header signature. */
def const SIG_LOCAL as int init 0x04034b50;

/** The central directory header signature. */
def const SIG_CENTRAL as int init 0x02014b50;

/** The end-of-central-directory signature. */
def const SIG_END as int init 0x06054b50;

/** The ZIP version needed to extract: 2.0, which is deflate. */
def const ZIP_VERSION as int init 20;

/** The deflate compression method. */
def const METHOD_DEFLATE as int init 8;

/** The store-only compression method. */
def const METHOD_STORE as int init 0;

/**
 * The most members this writer will put in one archive.
 *
 * The end-of-central-directory record counts members in 16 bits, and this
 * writer emits no ZIP64 record, so past 65535 the archive would be silently
 * wrong. Refused rather than written corrupt.
 */
def const MAX_MEMBERS as int init 65535;

/**
 * The largest archive this writer will produce.
 *
 * Offsets in the central directory are 32 bits without a ZIP64 record, so 4
 * GiB is the hard ceiling. Refused rather than wrapped.
 */
def const MAX_ARCHIVE as int init 4294967295;

/**
 * The most a container may inflate to: 256 MiB.
 *
 * `archive.unpack` cannot be bounded: it inflates every member and hands back
 * the result, so by the time this deck sees the bytes the memory is already
 * spent. A 61 KB file of compressible padding measured 495 MB of resident
 * memory, and zip does far better than that ratio on XML.
 *
 * So the declared sizes in the central directory are summed first and the
 * container refused before a byte is inflated. The directory is only a claim,
 * but a claim that is honest about being enormous is what should be refused,
 * and a dishonest one is still caught by the CRC afterwards.
 */
def const MAX_INFLATED as int init 268435456;

/**
 * The most members one container may hold.
 *
 * A directory with millions of tiny members costs as much to walk as a few
 * large ones cost to inflate.
 */
def const MAX_ENTRIES as int init 4096;

/**
 * A member to be deflated.
 *
 * @param name {string} the member path
 * @param data {bytes} the contents
 * @return {Member} the member
 * @example
 *   member("content.xml", $bytes);
 */
func member(name as string, data as bytes) {
    return Member{name: $name, data: $data, stored: false};
}

/**
 * A member to be stored uncompressed.
 *
 * Only ODF's `mimetype` needs this, and it needs to be the first member too.
 *
 * @param name {string} the member path
 * @param data {bytes} the contents
 * @return {Member} the member
 * @example
 *   storedMember("mimetype", $bytes);
 */
func storedMember(name as string, data as bytes) {
    return Member{name: $name, data: $data, stored: true};
}

/**
 * Read an archive into its members, keyed by path.
 *
 * Reading goes through `archive.unpack`, which handles what real files carry:
 * data descriptors (Excel emits them), and the central directory as the
 * authority on what is in the archive.
 *
 * @param raw {bytes} the archive
 * @return {map of string to bytes} the members, keyed by path
 * @throws {Error} kind "sheets" when the archive cannot be read
 * @example
 *   def parts as map of string to bytes init unzip($raw);
 */
func unzip(raw as bytes) {
    checkDeclaredSize($raw);
    def out as map of string to bytes init {};
    def entries as list of archive.Entry init [];
    try {
        $entries = archive.unpack($raw, "zip");
    } catch (e) {
        fail("not a readable ZIP container: " + $e.message);
    }
    for (def entry in $entries) {
        $out[$entry.name] = $entry.data;
    }
    return $out;
}

/**
 * Refuse a container that says it inflates to more than we will hold.
 *
 * Reads the central directory rather than the local headers, because the
 * directory is the authority on what is in an archive and a local header may
 * carry zeroes when the member was streamed with a data descriptor.
 *
 * A container whose directory cannot be found is passed through rather than
 * refused: `archive.unpack` gives a better message for a malformed archive
 * than this would, and this is a size guard, not a validator.
 *
 * @param raw {bytes} the container
 * @throws {Error} kind "sheets" when it declares more than `MAX_INFLATED` bytes or
 *   `MAX_ENTRIES` members
 */
func checkDeclaredSize(raw as bytes) {
    def eocd as int init findEndRecord($raw);
    if ($eocd < 0) {
        return;
    }
    def count as int init readLe16($raw, $eocd + 10);
    if ($count > MAX_ENTRIES) {
        fail("the container declares " + convert.toString($count) +
            " members, past the " + convert.toString(MAX_ENTRIES) +
            " this reader will open");
    }
    def at as int init readLe32($raw, $eocd + 16);
    def total as int init 0;
    for (def i in 0..$count) {
        if ($at + 46 > len($raw) or readLe32($raw, $at) != SIG_CENTRAL) {
            return;
        }
        $total = $total + readLe32($raw, $at + 24);
        if ($total > MAX_INFLATED) {
            fail("the container declares at least " + convert.toString($total) +
                " bytes of content, past the " + convert.toString(MAX_INFLATED) +
                " this reader will inflate; bound the input or unpack it in a " +
                "disposable process");
        }
        $at = $at + 46 + readLe16($raw, $at + 28) + readLe16($raw, $at + 30) +
            readLe16($raw, $at + 32);
    }
}

/**
 * Where the end-of-central-directory record starts.
 *
 * Searched backwards from the end, because the record sits last and may be
 * followed by a comment of up to 65535 bytes.
 *
 * @param raw {bytes} the container
 * @return {int} the record's offset, or `-1` when there is none
 */
func findEndRecord(raw as bytes) {
    def probe as bytes init le32(SIG_END);
    def from as int init len($raw) - 22;
    def lowest as int init $from - 65535;
    if ($lowest < 0) {
        $lowest = 0;
    }
    def at as int init $from;
    while ($at >= $lowest) {
        if (matchesAt($raw, $at, $probe)) {
            return $at;
        }
        $at = $at - 1;
    }
    return -1;
}

/**
 * Two bytes at an offset, little-endian.
 *
 * @param raw {bytes} the container
 * @param at {int} the offset
 * @return {int} the value, or 0 when the offset is past the end
 */
func readLe16(raw as bytes, at as int) {
    if ($at < 0 or $at + 2 > len($raw)) {
        return 0;
    }
    return $raw[$at] | ($raw[$at + 1] << 8);
}

/**
 * Four bytes at an offset, little-endian.
 *
 * @param raw {bytes} the container
 * @param at {int} the offset
 * @return {int} the value, or 0 when the offset is past the end
 */
func readLe32(raw as bytes, at as int) {
    if ($at < 0 or $at + 4 > len($raw)) {
        return 0;
    }
    return $raw[$at] | ($raw[$at + 1] << 8) | ($raw[$at + 2] << 16) |
        ($raw[$at + 3] << 24);
}

/**
 * One member of an archive, as text.
 *
 * @param parts {map of string to bytes} the members
 * @param name {string} the member path
 * @return {string} the member decoded as UTF-8
 * @throws {Error} kind "sheets" when the member is not in the archive
 * @example
 *   def xmlText as string init partText($parts, "content.xml");
 */
func partText(parts as map of string to bytes, name as string) {
    if (not maps.has($parts, $name)) {
        fail("the container has no " + quoted($name) + " (it holds " +
            partNameList($parts) + ")");
    }
    return convert.stringFromBytes($parts[$name], "utf-8");
}

/**
 * The member paths, for an error message.
 *
 * @param parts {map of string to bytes} the members
 * @return {string} the paths quoted and joined, bounded in length
 */
func partNameList(parts as map of string to bytes) {
    if (len($parts) == 0) {
        return "nothing";
    }
    def names as list of string init [];
    for (def name in $parts) {
        $names[] = quoted($name);
    }
    return quoted(strings.join($names, ", "));
}

/**
 * Build an archive from its members, in the order given.
 *
 * Order is preserved because ODF depends on it. Each member is deflated
 * unless it asked to be stored.
 *
 * @param members {list of Member} the members
 * @return {bytes} the archive
 * @throws {Error} kind "sheets" when there are too many members or the result is too large
 * @example
 *   def raw as bytes init zip($members);
 */
func zip(members as list of Member) {
    if (len($members) > MAX_MEMBERS) {
        fail("a container may hold at most " + convert.toString(MAX_MEMBERS) +
            " members; this one has " + convert.toString(len($members)));
    }
    def locals as list of bytes init [];
    def centrals as list of bytes init [];
    def offset as int init 0;
    for (def m in $members) {
        def encoded as bytes init memberBody($m);
        def nameBytes as bytes init convert.bytesFromString($m.name, "utf-8");
        def method as int init METHOD_DEFLATE;
        if ($m.stored) {
            $method = METHOD_STORE;
        }
        def sum as int init crc32Of($m.data);

        $locals[] = localHeader($nameBytes, $method, $sum, len($encoded), len($m.data));
        $locals[] = $encoded;
        $centrals[] = centralHeader(
            $nameBytes,
            $method,
            $sum,
            len($encoded),
            len($m.data),
            $offset);

        $offset = $offset +
            localHeaderSize(len($nameBytes)) + len($encoded);
        if ($offset > MAX_ARCHIVE) {
            fail("the container is larger than the 4 GiB a ZIP without ZIP64 " +
                "can address");
        }
    }
    def directory as bytes init binary.join($centrals);
    def out as list of bytes init [];
    $out[] = binary.join($locals);
    $out[] = $directory;
    $out[] = endRecord(len($members), len($directory), $offset);
    return binary.join($out);
}

/**
 * A member's contents as they go on the wire.
 *
 * @param m {Member} the member
 * @return {bytes} the contents, deflated unless the member is stored
 */
func memberBody(m as Member) {
    if ($m.stored) {
        return $m.data;
    }
    return compress.pack($m.data, "deflate");
}

/**
 * How long a local file header is, for the running offset.
 *
 * @param nameLength {int} the member path's length in bytes
 * @return {int} the header length
 */
func localHeaderSize(nameLength as int) {
    return 30 + $nameLength;
}

/**
 * The CRC-32 of a member, as the integer the headers carry.
 *
 * `crc.compute` hands back four big-endian bytes rather than an int, so this
 * is where they become one.
 *
 * @param data {bytes} the contents
 * @return {int} the checksum
 */
func crc32Of(data as bytes) {
    def digest as bytes init crc.compute($data, "crc32");
    return ($digest[0] << 24) | ($digest[1] << 16) | ($digest[2] << 8) | $digest[3];
}

/**
 * A local file header.
 *
 * The modification time and date are written as zero rather than from the
 * clock, so that writing the same workbook twice produces the same bytes and
 * a golden file stays stable.
 *
 * @param nameBytes {bytes} the member path, UTF-8
 * @param method {int} the compression method
 * @param sum {int} the CRC-32 of the uncompressed contents
 * @param packedSize {int} the stored length
 * @param plainSize {int} the uncompressed length
 * @return {bytes} the header
 */
func localHeader(
    nameBytes as bytes,
    method as int,
    sum as int,
    packedSize as int,
    plainSize as int) {
    def out as list of bytes init [];
    $out[] = le32(SIG_LOCAL);
    $out[] = le16(ZIP_VERSION);
    $out[] = le16(0);
    $out[] = le16($method);
    $out[] = le16(0);
    $out[] = le16(0);
    $out[] = le32($sum);
    $out[] = le32($packedSize);
    $out[] = le32($plainSize);
    $out[] = le16(len($nameBytes));
    $out[] = le16(0);
    $out[] = $nameBytes;
    return binary.join($out);
}

/**
 * A central directory header.
 *
 * @param nameBytes {bytes} the member path, UTF-8
 * @param method {int} the compression method
 * @param sum {int} the CRC-32 of the uncompressed contents
 * @param packedSize {int} the stored length
 * @param plainSize {int} the uncompressed length
 * @param offset {int} where the member's local header sits
 * @return {bytes} the header
 */
func centralHeader(
    nameBytes as bytes,
    method as int,
    sum as int,
    packedSize as int,
    plainSize as int,
    offset as int) {
    def out as list of bytes init [];
    $out[] = le32(SIG_CENTRAL);
    $out[] = le16(ZIP_VERSION);
    $out[] = le16(ZIP_VERSION);
    $out[] = le16(0);
    $out[] = le16($method);
    $out[] = le16(0);
    $out[] = le16(0);
    $out[] = le32($sum);
    $out[] = le32($packedSize);
    $out[] = le32($plainSize);
    $out[] = le16(len($nameBytes));
    $out[] = le16(0);
    $out[] = le16(0);
    $out[] = le16(0);
    $out[] = le16(0);
    $out[] = le32(0);
    $out[] = le32($offset);
    $out[] = $nameBytes;
    return binary.join($out);
}

/**
 * The end-of-central-directory record.
 *
 * @param count {int} how many members the archive holds
 * @param directorySize {int} the central directory's length
 * @param directoryOffset {int} where the central directory starts
 * @return {bytes} the record
 */
func endRecord(count as int, directorySize as int, directoryOffset as int) {
    def out as list of bytes init [];
    $out[] = le32(SIG_END);
    $out[] = le16(0);
    $out[] = le16(0);
    $out[] = le16($count);
    $out[] = le16($count);
    $out[] = le32($directorySize);
    $out[] = le32($directoryOffset);
    $out[] = le16(0);
    return binary.join($out);
}

/**
 * Two bytes, little-endian.
 *
 * @param n {int} the value, 0 to 65535
 * @return {bytes} the two bytes
 */
func le16(n as int) {
    def out as bytes;
    $out[] = $n & 0xff;
    $out[] = ($n >> 8) & 0xff;
    return $out;
}

/**
 * Four bytes, little-endian.
 *
 * @param n {int} the value, 0 to 4294967295
 * @return {bytes} the four bytes
 */
func le32(n as int) {
    def out as bytes;
    $out[] = $n & 0xff;
    $out[] = ($n >> 8) & 0xff;
    $out[] = ($n >> 16) & 0xff;
    $out[] = ($n >> 24) & 0xff;
    return $out;
}
