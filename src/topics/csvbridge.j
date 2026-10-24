# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the bridge to and from delimited text.
# Spliced into sheets.j via include - not a standalone module.

/** The sheet name a CSV read produces, since the format carries none. */
export def const CSV_SHEET_NAME as string init "Sheet1";

/**
 * Read delimited text into a one-sheet workbook.
 *
 * The quoting and escaping are the `csv` module's (RFC 4180). With `typed`, a
 * field that reads as a boolean (`true`/`false`, any case), an error code
 * such as `#N/A`, a number or an ISO 8601 date becomes one; a number with a
 * leading zero (`007`) stays text either way. Pass `typed` as false to keep
 * every field as text. An empty field is an empty cell in both modes.
 *
 * @param body {string} the delimited text
 * @param typed {bool} whether to infer numbers, booleans and dates
 * @return {Workbook} a workbook with one sheet
 * @throws {Error} kind "sheets" when the text is not well-formed CSV
 * @example
 *   def wb as Workbook init readCsv(fs.readString("data.csv"), true);
 */
export func readCsv(body as string, typed as bool) {
    return readDelimited($body, ",", $typed);
}

/**
 * Read delimited text with a chosen separator.
 *
 * @param body {string} the delimited text
 * @param delimiter {string} the field separator, one character
 * @param typed {bool} whether to infer numbers, booleans and dates
 * @return {Workbook} a workbook with one sheet
 * @throws {Error} kind "sheets" when the text is not well-formed, or the delimiter is not
 *   one character
 * @example
 *   def wb as Workbook init readDelimited($text, "\t", true);
 */
export func readDelimited(body as string, delimiter as string, typed as bool) {
    if (len($delimiter) != 1) {
        fail("a delimiter is one character, not " + quoted($delimiter));
    }
    def rows as list of list of string init [];
    try {
        $rows = csv.parseWith($body, $delimiter);
    } catch (e) {
        fail("the text is not well-formed delimited data: " + $e.message);
    }
    # Collected into one list and placed once: assigning the sheet per row
    # would deep-copy its cell map every time, which is quadratic.
    def placed as list of Placed init [];
    for (def r in 0..len($rows)) {
        def fields as list of string init $rows[$r];
        for (def c in 0..len($fields)) {
            def v as Value init csvValue($fields[$c], $typed);
            if (not isEmpty($v)) {
                $placed[] = Placed{at: Ref{row: $r, col: $c}, value: $v};
            }
        }
    }
    def wb as Workbook init newWorkbook();
    return addSheet($wb, sheetFrom(CSV_SHEET_NAME, $placed));
}

/**
 * One field as a value, typed or not.
 *
 * The order of the tests matters: boolean, error code, number, then date
 * last because `parseIsoDate` is the most permissive. A field that is only
 * whitespace stays text.
 *
 * @param field {string} the field as read
 * @param typed {bool} whether to infer a type
 * @return {Value} the value
 */
func csvValue(field as string, typed as bool) {
    if ($field == "") {
        return Value.Empty;
    }
    if (not $typed) {
        return Value.Text{body: $field};
    }
    def trimmed as string init strings.trim($field);
    if ($trimmed == "") {
        return Value.Text{body: $field};
    }
    def word as string init strings.lower($trimmed);
    if ($word == "true" or $word == "false") {
        return Value.Bool{flag: $word == "true"};
    }
    if (looksLikeErrorCode($trimmed)) {
        return Value.Err{code: $trimmed};
    }
    if (looksNumeric($trimmed)) {
        def amount as float init 0.0;
        def ok as bool init true;
        try {
            $amount = convert.toFloat($trimmed);
        } catch (e) {
            $ok = false;
        }
        if ($ok) {
            return Value.Number{amount: $amount};
        }
    }
    if (looksLikeIsoDate($trimmed)) {
        def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
        def ok2 as bool init true;
        try {
            $at = parseIsoDate($trimmed);
        } catch (e) {
            $ok2 = false;
        }
        if ($ok2) {
            return Value.Stamp{at: $at, dateOnly: not strings.contains($trimmed, "T")};
        }
    }
    return Value.Text{body: $field};
}

/**
 * Whether a field should be tried as a number.
 *
 * A cheap shape test before `convert.toFloat`, and the place a leading zero is
 * protected: `007` and `0123` are identifiers in every real data set, so they
 * stay text rather than silently losing their zeros. A plain `0` is still a
 * number.
 *
 * @param field {string} the trimmed field
 * @return {bool} whether to read it as a number
 */
func looksNumeric(field as string) {
    def body as string init $field;
    if (strings.startsWith($body, "-") or strings.startsWith($body, "+")) {
        $body = strings.substring($body, 1, len($body));
    }
    if ($body == "") {
        return false;
    }
    if (len($body) > 1 and strings.startsWith($body, "0") and
        not strings.startsWith($body, "0.")) {
        return false;
    }
    def digits as int init 0;
    def dots as int init 0;
    for (def ch in strings.chars($body)) {
        if (strings.indexOf("0123456789", $ch) >= 0) {
            $digits = $digits + 1;
        } elseif ($ch == ".") {
            $dots = $dots + 1;
        } elseif ($ch == "e" or $ch == "E" or $ch == "-" or $ch == "+") {
            # An exponent; convert.toFloat is the judge of whether it parses.
        } else {
            return false;
        }
    }
    return $digits > 0 and $dots <= 1;
}

/**
 * Whether a field has the shape of an ISO 8601 date.
 *
 * Four digits, a dash, and at least ten characters. Without the shape test
 * every short string would go through a throwing parse.
 *
 * @param field {string} the trimmed field
 * @return {bool} whether to read it as a date
 */
func looksLikeIsoDate(field as string) {
    if (len($field) < 10) {
        return false;
    }
    for (def i in 0..4) {
        if (strings.indexOf("0123456789", strings.substring($field, $i, $i + 1)) < 0) {
            return false;
        }
    }
    return strings.substring($field, 4, 5) == "-";
}

/**
 * Write one sheet of a workbook as delimited text.
 *
 * Only one sheet, because the format holds one. Which sheet is the caller's
 * choice rather than a guess.
 *
 * @param wb {Workbook} the workbook
 * @param sheetName {string} the sheet to write; `""` takes the first
 * @return {string} the delimited text
 * @throws {Error} kind "sheets" when the named sheet is not there
 * @example
 *   fs.writeString("out.csv", writeCsv($wb, ""));
 */
export func writeCsv(wb as Workbook, sheetName as string) {
    return writeDelimited($wb, $sheetName, ",");
}

/**
 * Write one sheet as delimited text with a chosen separator.
 *
 * @param wb {Workbook} the workbook
 * @param sheetName {string} the sheet to write; `""` takes the first
 * @param delimiter {string} the field separator, one character
 * @return {string} the delimited text
 * @throws {Error} kind "sheets" when the sheet is not there or the delimiter is not one
 *   character
 * @example
 *   writeDelimited($wb, "Q3", "\t");
 */
export func writeDelimited(wb as Workbook, sheetName as string, delimiter as string) {
    if (len($delimiter) != 1) {
        fail("a delimiter is one character, not " + quoted($delimiter));
    }
    def s as Sheet init firstOrNamedSheet($wb, $sheetName);
    def rows as list of list of string init [];
    for (def r in 0..$s.rowCount) {
        def fields as list of string init [];
        for (def v in row($s, $r)) {
            $fields[] = asString($v);
        }
        $rows[] = $fields;
    }
    return csv.formatDialect($rows, csv.dialect($delimiter));
}

/**
 * The named sheet, or the first one when no name is given.
 *
 * @param wb {Workbook} the workbook
 * @param sheetName {string} the sheet name, or `""`
 * @return {Sheet} the sheet
 * @throws {Error} kind "sheets" when the workbook has no sheets, or no sheet by that name
 */
func firstOrNamedSheet(wb as Workbook, sheetName as string) {
    if (len($wb.sheets) == 0) {
        fail("the workbook has no sheets");
    }
    if ($sheetName == "") {
        return $wb.sheets[0];
    }
    return sheetByName($wb, $sheetName);
}

/**
 * Write one sheet as delimited text, neutralising formula injection.
 *
 * A field a spreadsheet application would read as a formula is prefixed so it
 * cannot execute on open (CWE-1236). Use this whenever the text leaves the
 * program for someone else to open, which is most of the time. The `csv`
 * module does the neutralising; this picks the sheet and renders the cells.
 *
 * @param wb {Workbook} the workbook
 * @param sheetName {string} the sheet to write; `""` takes the first
 * @return {string} the delimited text, safe to hand to a spreadsheet
 * @throws {Error} kind "sheets" when the named sheet is not there
 * @example
 *   fs.writeString("export.csv", writeCsvSafe($wb, ""));
 */
export func writeCsvSafe(wb as Workbook, sheetName as string) {
    def s as Sheet init firstOrNamedSheet($wb, $sheetName);
    def rows as list of list of string init [];
    for (def r in 0..$s.rowCount) {
        def fields as list of string init [];
        for (def v in row($s, $r)) {
            $fields[] = asString($v);
        }
        $rows[] = $fields;
    }
    return csv.formatSafe($rows);
}
