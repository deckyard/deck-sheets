# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - choosing a format, and the filesystem entry points.
# Spliced into sheets.j via include - not a standalone module.

/**
 * A spreadsheet file format.
 *
 * The enum is what makes a conversion explicit: `open` detects one, `save`
 * takes one, and a `match` over it is exhaustive, so adding a format cannot
 * silently leave a hole in the dispatch.
 */
export def enum Format {
    Ods,
    Xlsx,
    Gnumeric,
    Csv,
    Tsv
};

/**
 * The format a filename's extension names.
 *
 * @param name {string} the filename or path
 * @return {Format} the format
 * @throws {Error} kind "sheets" when the extension names no format this deck knows
 * @example
 *   formatOf("sales.xlsx");   # Format.Xlsx
 */
export func formatOf(name as string) {
    def ext as string init strings.lower(path.ext($name));
    match ($ext) {
        when ".ods" { return Format.Ods; }
        when ".xlsx", ".xlsm" { return Format.Xlsx; }
        when ".gnumeric", ".gnm" { return Format.Gnumeric; }
        when ".csv" { return Format.Csv; }
        when ".tsv", ".tab" { return Format.Tsv; }
        else {
            fail("cannot tell the format of " + quoted($name) +
                " from its extension (known: .ods, .xlsx, .gnumeric, .csv, .tsv)");
            return Format.Ods;
        }
    }
}

/**
 * The format a file's own bytes identify, independent of its name.
 *
 * For an upload or a temporary file, whose name is unreliable. Any gzip
 * stream is taken to be Gnumeric; a ZIP is unpacked far enough to tell ODS
 * (`content.xml`) from XLSX (`xl/workbook.xml`); an uncompressed Gnumeric
 * document is recognised by its first 512 bytes. Delimited text has no
 * signature and is not detected.
 *
 * @param raw {bytes} the file
 * @return {Format} the format
 * @throws {Error} kind "sheets" when the bytes identify no format this deck reads
 * @example
 *   formatOfBytes(fs.readBytes("download.bin"));
 */
export func formatOfBytes(raw as bytes) {
    if (len($raw) >= 2 and $raw[0] == 0x1f and $raw[1] == 0x8b) {
        return Format.Gnumeric;
    }
    if (len($raw) >= 4 and $raw[0] == 0x50 and $raw[1] == 0x4b) {
        return zipFlavour($raw);
    }
    if (looksLikeGnumericXml($raw)) {
        return Format.Gnumeric;
    }
    fail("the file's bytes match no format this deck reads (expected a ZIP " +
        "container for ODS or XLSX, or a gzipped document for Gnumeric)");
    return Format.Ods;
}

/**
 * Which spreadsheet a ZIP container holds.
 *
 * @param raw {bytes} the container
 * @return {Format} the format
 * @throws {Error} kind "sheets" when it is neither an ODS nor an XLSX
 */
func zipFlavour(raw as bytes) {
    def parts as map of string to bytes init unzip($raw);
    if (maps.has($parts, "content.xml")) {
        return Format.Ods;
    }
    if (maps.has($parts, XLSX_WORKBOOK)) {
        return Format.Xlsx;
    }
    fail("the container holds neither content.xml nor " + quoted(XLSX_WORKBOOK) +
        ", so it is not a spreadsheet this deck reads");
    return Format.Ods;
}

/**
 * Whether a plain document looks like an ungzipped Gnumeric file.
 *
 * @param raw {bytes} the file
 * @return {bool} whether its opening carries the Gnumeric root element
 */
func looksLikeGnumericXml(raw as bytes) {
    def head as int init 512;
    if (len($raw) < $head) {
        $head = len($raw);
    }
    def opening as string init "";
    try {
        $opening = convert.stringFromBytes(binary.slice($raw, 0, $head), "utf-8");
    } catch (e) {
        return false;
    }
    return strings.contains($opening, "gnumeric.org") or
        strings.contains($opening, "gnm:Workbook");
}

/**
 * Read a workbook from bytes in a named format.
 *
 * CSV and TSV are read typed (see {@link readCsv}) and must be UTF-8.
 *
 * @param raw {bytes} the file
 * @param kind {Format} the format to read it as
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the bytes are not that format
 * @example
 *   readFormat($bytes, Format.Xlsx);
 */
export func readFormat(raw as bytes, kind as Format) {
    match ($kind) {
        when Ods { return readOds($raw); }
        when Xlsx { return readXlsx($raw); }
        when Gnumeric { return readGnumeric($raw); }
        when Csv { return readCsv(utf8Text($raw), true); }
        when Tsv { return readDelimited(utf8Text($raw), "\t", true); }
    }
}

/**
 * Write a workbook to bytes in a named format.
 *
 * CSV and TSV carry the first sheet only, as UTF-8.
 *
 * @param wb {Workbook} the workbook
 * @param kind {Format} the format to write
 * @return {bytes} the file
 * @throws {Error} kind "sheets" when the workbook cannot be written as that format
 * @example
 *   writeFormat($wb, Format.Ods);
 */
export func writeFormat(wb as Workbook, kind as Format) {
    match ($kind) {
        when Ods { return writeOds($wb); }
        when Xlsx { return writeXlsx($wb); }
        when Gnumeric { return writeGnumeric($wb); }
        when Csv { return convert.bytesFromString(writeCsv($wb, ""), "utf-8"); }
        when Tsv { return convert.bytesFromString(writeDelimited($wb, "", "\t"), "utf-8"); }
    }
}

/**
 * Decode bytes as UTF-8, with a clear error when they are not.
 *
 * @param raw {bytes} the bytes
 * @return {string} the text
 * @throws {Error} kind "sheets" when the bytes are not valid UTF-8
 */
func utf8Text(raw as bytes) {
    def out as string init "";
    try {
        $out = convert.stringFromBytes($raw, "utf-8");
    } catch (e) {
        fail("the text is not valid UTF-8; convert it first with the " +
            "encoding library");
    }
    return $out;
}

/**
 * Read a workbook from a file, choosing the format by extension.
 *
 * @param filePath {string} the file to read
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the file is missing, or is not the format its name says
 * @example
 *   def wb as Workbook init open("sales.xlsx");
 */
export func open(filePath as string) {
    if (not fs.exists($filePath)) {
        fail("no such file: " + quoted($filePath));
    }
    return readFormat(fs.readBytes($filePath), formatOf($filePath));
}

/**
 * Read a workbook from a file, choosing the format by its contents.
 *
 * For a file whose name says nothing useful. Delimited text has no signature,
 * so a `.csv` still has to go through {@link open}.
 *
 * @param filePath {string} the file to read
 * @return {Workbook} the workbook
 * @throws {Error} kind "sheets" when the file is missing or its bytes match no format
 * @example
 *   def wb as Workbook init openDetected("upload.bin");
 */
export func openDetected(filePath as string) {
    if (not fs.exists($filePath)) {
        fail("no such file: " + quoted($filePath));
    }
    def raw as bytes init fs.readBytes($filePath);
    return readFormat($raw, formatOfBytes($raw));
}

/**
 * Write a workbook to a file, choosing the format by extension.
 *
 * A conversion is a read and a write: `save(open("in.xlsx"), "out.ods")`.
 * The extension is checked before anything is written.
 *
 * @param wb {Workbook} the workbook
 * @param filePath {string} the file to write
 * @throws {Error} kind "sheets" when the extension names no format, or the write fails
 * @example
 *   save($wb, "out.ods");
 */
export func save(wb as Workbook, filePath as string) {
    fs.writeBytes($filePath, writeFormat($wb, formatOf($filePath)));
}

/**
 * The name of a format, for a message or a log line.
 *
 * @param kind {Format} the format
 * @return {string} the name
 * @example
 *   formatName(Format.Ods);   # "ods"
 */
export func formatName(kind as Format) {
    match ($kind) {
        when Ods { return "ods"; }
        when Xlsx { return "xlsx"; }
        when Gnumeric { return "gnumeric"; }
        when Csv { return "csv"; }
        when Tsv { return "tsv"; }
    }
}
