# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - what a cell holds, and the date serial codec.
# Spliced into sheets.j via include - not a standalone module.

/**
 * What one cell holds.
 *
 * A sum type rather than a struct of optional fields, so a reader cannot
 * leave a cell half-described and a `match` over it is exhaustive. The zero
 * value is `Empty`, which is what an absent cell reads as.
 *
 * `Formula` carries both halves: `source` is the expression as the file
 * spelled it, `cached` is the result the producing application last computed.
 * Reading never evaluates, so `cached` is what a reader gets and what a writer
 * puts back. Change a cell a formula depends on and `cached` goes stale until
 * `recalculate` or a spreadsheet application recomputes it.
 *
 * `Err` is spelled short because `Error` is the auto-provided error struct.
 *
 *   `Empty`    no content
 *   `Text`     a string, in `body`
 *   `Number`   a number, in `amount`
 *   `Bool`     a boolean, in `flag`
 *   `Stamp`    a date or date-time, in `at`; `dateOnly` is true when it
 *              carries no time of day
 *   `Formula`  the expression in `source`, the last computed result in
 *              `cached`
 *   `Err`      an error code such as `"#DIV/0!"`, in `code`
 */
export def enum Value {
    Empty,
    Text{body as string},
    Number{amount as float},
    Bool{flag as bool},
    Stamp{at as time.Time, dateOnly as bool},
    Formula{source as string, cached as string},
    Err{code as string}
};

/**
 * The origin the 1900 date system counts from, for serials past the phantom day.
 *
 * The 1900 system carries a deliberate bug: it treats 1900 as a leap year, so
 * serial 60 is 1900-02-29, a day that never existed. Every serial from 61 on
 * is therefore one greater than the true day count, and counting those from
 * 1899-12-30 rather than 1899-12-31 absorbs the extra day.
 *
 * Serials below 60 predate the phantom day and count from `EPOCH1900EARLY`
 * instead, so that serial 1 is 1900-01-01 as the format says. `fromSerial`
 * and `toSerial` pick between the two; see `PHANTOM_SERIAL`.
 */
def const EPOCH1900 as string init "1899-12-30T00:00:00Z";

/** The origin serials below `PHANTOM_SERIAL` count from: serial 1 is 1900-01-01. */
def const EPOCH1900EARLY as string init "1899-12-31T00:00:00Z";

/**
 * The serial of the day the 1900 system invented.
 *
 * Serial 60 is 1900-02-29, which did not occur. A file carrying it is not
 * describing a real date, so this deck reads it as 1900-02-28 (the day Excel
 * shows either side of it) rather than refusing the file.
 */
def const PHANTOM_SERIAL as float init 60.0;

/** The origin the 1904 date system counts from, used by old Mac workbooks. */
def const EPOCH1904 as string init "1904-01-01T00:00:00Z";

/** Seconds in a day, the unit a date serial counts. */
def const DAY_SECONDS as int init 86400;

/**
 * An empty cell.
 *
 * @return {Value} the `Empty` variant
 * @example
 *   empty();
 */
export func empty() {
    return Value.Empty;
}

/**
 * A text cell.
 *
 * @param body {string} the text
 * @return {Value} the `Text` variant
 * @example
 *   text("total");
 */
export func text(body as string) {
    return Value.Text{body: $body};
}

/**
 * A numeric cell.
 *
 * @param amount {float} the number
 * @return {Value} the `Number` variant
 * @example
 *   number(42.5);
 */
export func number(amount as float) {
    return Value.Number{amount: $amount};
}

/**
 * A numeric cell from an integer.
 *
 * Both formats store every number as a float, so this is sugar for the common
 * case rather than a separate kind of cell.
 *
 * @param amount {int} the number
 * @return {Value} the `Number` variant
 * @example
 *   integer(4);
 */
export func integer(amount as int) {
    return Value.Number{amount: convert.toFloat($amount)};
}

/**
 * A boolean cell.
 *
 * @param flag {bool} the value
 * @return {Value} the `Bool` variant
 * @example
 *   boolean(true);
 */
export func boolean(flag as bool) {
    return Value.Bool{flag: $flag};
}

/**
 * A date cell, with no time of day.
 *
 * @param at {time.Time} the day
 * @return {Value} the `Stamp` variant with `dateOnly` set
 * @example
 *   date(time.fromIso("2026-10-02T00:00:00Z"));
 */
export func date(at as time.Time) {
    return Value.Stamp{at: $at, dateOnly: true};
}

/**
 * A date-and-time cell.
 *
 * @param at {time.Time} the instant
 * @return {Value} the `Stamp` variant with `dateOnly` clear
 * @example
 *   stamp(time.now());
 */
export func stamp(at as time.Time) {
    return Value.Stamp{at: $at, dateOnly: false};
}

/**
 * A formula cell.
 *
 * @param source {string} the formula as written, without a leading `=`
 * @param cached {string} the last computed result, as text; `""` when unknown
 * @return {Value} the `Formula` variant
 * @example
 *   formula("B3*C2", "19.98");
 */
export func formula(source as string, cached as string) {
    return Value.Formula{source: $source, cached: $cached};
}

/**
 * An error cell.
 *
 * @param code {string} the error code, such as `"#DIV/0!"`
 * @return {Value} the `Err` variant
 * @example
 *   errorValue("#DIV/0!");
 */
export func errorValue(code as string) {
    return Value.Err{code: $code};
}

/**
 * Whether a cell holds nothing.
 *
 * @param v {Value} the cell value
 * @return {bool} whether it is `Empty`
 * @example
 *   isEmpty(empty());   # true
 */
export func isEmpty(v as Value) {
    match ($v) {
        when Empty { return true; }
        else { return false; }
    }
}

/**
 * The name of a value's variant.
 *
 * For a diagnostic or a dispatch table; use a `match` when the payload is
 * wanted too.
 *
 * @param v {Value} the cell value
 * @return {string} one of `empty` `text` `number` `bool` `stamp` `formula`
 *   `error`
 * @example
 *   kindOf(number(1.0));   # "number"
 */
export func kindOf(v as Value) {
    match ($v) {
        when Empty { return "empty"; }
        when Text(t) { return "text"; }
        when Number(n) { return "number"; }
        when Bool(b) { return "bool"; }
        when Stamp(s) { return "stamp"; }
        when Formula(f) { return "formula"; }
        when Err(e) { return "error"; }
    }
}

/**
 * A cell's value as text.
 *
 * The plain rendering, not a number-format application: a number keeps its
 * full precision, a date is ISO 8601, a formula gives its cached result. An
 * empty cell is the empty string, so a caller walking a row does not have to
 * special-case it.
 *
 * @param v {Value} the cell value
 * @return {string} the text
 * @example
 *   asString(number(9.99));          # "9.99"
 *   asString(formula("A1", "42"));   # "42"
 */
export func asString(v as Value) {
    match ($v) {
        when Empty { return ""; }
        when Text(t) { return $t.body; }
        when Number(n) { return numberText($n.amount); }
        when Bool(b) { return boolText($b.flag); }
        when Stamp(s) { return stampText($s.at, $s.dateOnly); }
        when Formula(f) { return $f.cached; }
        when Err(e) { return $e.code; }
    }
}

/**
 * Render a number the way a spreadsheet file writes one.
 *
 * A whole number loses its `.0`, because both formats write `4` rather than
 * `4.0` and a round trip should not grow a decimal point.
 *
 * @param amount {float} the number
 * @return {string} the text
 */
func numberText(amount as float) {
    # The magnitude is checked *first*: `math.floor` returns an int and
    # throws when the result will not fit in one, so testing it before the
    # bound made `asString(number(1e300))` raise `kind: "runtime"` - which a
    # file is free to contain and this deck's error contract forbids.
    if (math.abs($amount) < 1e15 and $amount == math.floor($amount)) {
        return convert.toString(convert.toInt($amount));
    }
    return convert.toString($amount);
}

/**
 * Render a boolean the way both formats write one.
 *
 * @param flag {bool} the value
 * @return {string} `"TRUE"` or `"FALSE"`
 */
func boolText(flag as bool) {
    if ($flag) {
        return "TRUE";
    }
    return "FALSE";
}

/**
 * Render an instant as ODS writes one.
 *
 * @param at {time.Time} the instant
 * @param dateOnly {bool} whether to omit the time of day
 * @return {string} an ISO 8601 date or date-time
 */
func stampText(at as time.Time, dateOnly as bool) {
    if ($dateOnly) {
        return time.format($at, "%Y-%m-%d");
    }
    return time.format($at, "%Y-%m-%dT%H:%M:%S");
}

/**
 * A cell's value as a number.
 *
 * Text that looks like a number is converted, because a CSV import and a
 * text-typed export both produce numbers stored as text and a caller
 * summing a column should not have to care. A date gives its serial in the
 * 1900 system.
 *
 * @param v {Value} the cell value
 * @return {float} the number
 * @throws {Error} kind "sheets" when the value has no numeric reading
 * @example
 *   asNumber(number(9.99));   # 9.99
 *   asNumber(text("42"));     # 42.0
 */
export func asNumber(v as Value) {
    match ($v) {
        when Empty { return 0.0; }
        when Number(n) { return $n.amount; }
        when Bool(b) { return boolNumber($b.flag); }
        when Stamp(s) { return toSerial($s.at, false); }
        when Text(t) { return textNumber($t.body); }
        when Formula(f) { return textNumber($f.cached); }
        when Err(e) { return failNumber($e.code); }
    }
}

/**
 * The numeric reading of a boolean.
 *
 * @param flag {bool} the value
 * @return {float} 1.0 or 0.0
 */
func boolNumber(flag as bool) {
    if ($flag) {
        return 1.0;
    }
    return 0.0;
}

/**
 * The numeric reading of text.
 *
 * @param body {string} the text
 * @return {float} the number
 * @throws {Error} kind "sheets" when the text is not a number
 */
func textNumber(body as string) {
    def trimmed as string init strings.trim($body);
    if ($trimmed == "") {
        return 0.0;
    }
    def out as float init 0.0;
    try {
        $out = convert.toFloat($trimmed);
    } catch (e) {
        fail("cell text " + quoted($body) + " has no numeric value");
    }
    return $out;
}

/**
 * Refuse to give an error cell a numeric reading.
 *
 * @param code {string} the error code
 * @return {float} never returns
 * @throws {Error} kind "sheets" always
 */
func failNumber(code as string) {
    fail("cell holds the error " + quoted($code) + ", which has no numeric value");
    return 0.0;
}

/**
 * A cell's value as a boolean.
 *
 * @param v {Value} the cell value
 * @return {bool} the boolean
 * @throws {Error} kind "sheets" when the value has no boolean reading
 * @example
 *   asBool(boolean(true));   # true
 *   asBool(number(1.0));     # true
 */
export func asBool(v as Value) {
    match ($v) {
        when Bool(b) { return $b.flag; }
        when Empty { return false; }
        when Number(n) { return $n.amount != 0.0; }
        when Text(t) { return textBool($t.body); }
        when Formula(f) { return textBool($f.cached); }
        else { return failBool($v); }
    }
}

/**
 * The boolean reading of text.
 *
 * Accepts the spellings both formats and a CSV produce, in any case.
 *
 * @param body {string} the text
 * @return {bool} the boolean
 * @throws {Error} kind "sheets" when the text is not a boolean
 */
func textBool(body as string) {
    def word as string init strings.lower(strings.trim($body));
    if ($word == "true" or $word == "1") {
        return true;
    }
    if ($word == "false" or $word == "0" or $word == "") {
        return false;
    }
    fail("cell text " + quoted($body) + " has no boolean value");
    return false;
}

/**
 * Refuse to give a value a boolean reading.
 *
 * @param v {Value} the cell value
 * @return {bool} never returns
 * @throws {Error} kind "sheets" always
 */
func failBool(v as Value) {
    fail("a " + kindOf($v) + " cell has no boolean value");
    return false;
}

/**
 * A cell's value as an instant.
 *
 * A number is read as a date serial in the 1900 system, which is what an
 * XLSX date cell is before its style is consulted.
 *
 * @param v {Value} the cell value
 * @return {time.Time} the instant
 * @throws {Error} kind "sheets" when the value has no date reading
 * @example
 *   asTime(number(46297.0));   # 2026-10-02
 */
export func asTime(v as Value) {
    match ($v) {
        when Stamp(s) { return $s.at; }
        when Number(n) { return fromSerial($n.amount, false); }
        when Text(t) { return parseIsoDate($t.body); }
        when Formula(f) { return parseIsoDate($f.cached); }
        else { return failTime($v); }
    }
}

/**
 * Refuse to give a value a date reading.
 *
 * @param v {Value} the cell value
 * @return {time.Time} never returns
 * @throws {Error} kind "sheets" always
 */
func failTime(v as Value) {
    fail("a " + kindOf($v) + " cell has no date value");
    return time.fromIso(EPOCH1900);
}

/**
 * Read an ODS date or date-time attribute.
 *
 * ODS writes `office:date-value` as an ISO 8601 date (`2026-10-02`) or
 * date-time (`2026-10-02T14:30:00`), with no zone. The zone-less form is read
 * as UTC, which keeps a round trip exact; this deck does not guess a local
 * zone for a value the file did not carry one for.
 *
 * @param body {string} an ISO 8601 date or date-time
 * @return {time.Time} the instant
 * @throws {Error} kind "sheets" when the text is not an ISO 8601 date
 * @example
 *   parseIsoDate("2026-10-02");
 */
export func parseIsoDate(body as string) {
    def trimmed as string init strings.trim($body);
    if ($trimmed == "") {
        fail("an empty value is not a date");
    }
    def candidate as string init $trimmed;
    if (len($candidate) == 10) {
        $candidate = $candidate + "T00:00:00Z";
    } elseif (not strings.endsWith($candidate, "Z") and
        strings.indexOf($candidate, "+") < 0) {
        $candidate = $candidate + "Z";
    }
    def out as time.Time init time.fromIso(EPOCH1900);
    try {
        $out = time.fromIso($candidate);
    } catch (e) {
        fail("value " + quoted($body) + " is not an ISO 8601 date");
    }
    return $out;
}

/**
 * The origin a serial counts from.
 *
 * The 1900 system needs two: see `EPOCH1900` for why serials either side of
 * the phantom 1900-02-29 count from different days.
 *
 * @param date1904 {bool} whether the workbook uses the 1904 system
 * @param early {bool} whether the serial is below `PHANTOM_SERIAL`
 * @return {time.Time} the origin
 */
func dateOrigin(date1904 as bool, early as bool) {
    if ($date1904) {
        return time.fromIso(EPOCH1904);
    }
    if ($early) {
        return time.fromIso(EPOCH1900EARLY);
    }
    return time.fromIso(EPOCH1900);
}

/**
 * The date serial for an instant.
 *
 * The fractional part is the time of day, so noon is `.5`. Sub-second
 * precision is not representable in a serial and is dropped.
 *
 * @param at {time.Time} the instant
 * @param date1904 {bool} whether the workbook uses the 1904 system
 * @return {float} the serial
 * @throws {Error} kind "sheets" when the instant is before the origin
 * @example
 *   toSerial(time.fromIso("2026-10-02T00:00:00Z"), false);   # 46297.0
 */
export func toSerial(at as time.Time, date1904 as bool) {
    # Try the late origin first, then redo the arithmetic from the early one
    # when the result lands below the phantom day.
    def seconds as int init time.seconds(time.sub($at, dateOrigin($date1904, false)));
    def serial as float init convert.toFloat($seconds) / convert.toFloat(DAY_SECONDS);
    # From the late origin 1900-02-28 lands on exactly PHANTOM_SERIAL, so the
    # test is inclusive: every date before 1900-03-01 counts from the early one.
    if (not $date1904 and $serial <= PHANTOM_SERIAL) {
        $seconds = time.seconds(time.sub($at, dateOrigin($date1904, true)));
        $serial = convert.toFloat($seconds) / convert.toFloat(DAY_SECONDS);
    }
    if ($serial < 0.0) {
        fail("date " + quoted(time.iso($at)) + " is before the spreadsheet epoch " +
            "and has no serial");
    }
    return $serial;
}

/**
 * The instant a date serial names.
 *
 * @param serial {float} the serial, whole days with a fractional time of day
 * @param date1904 {bool} whether the workbook uses the 1904 system
 * @return {time.Time} the instant
 * @throws {Error} kind "sheets" when the serial is negative
 * @example
 *   fromSerial(46297.0, false);   # 2026-10-02
 */
export func fromSerial(serial as float, date1904 as bool) {
    if ($serial < 0.0) {
        fail("date serial " + convert.toString($serial) + " is negative");
    }
    def effective as float init $serial;
    def early as bool init not $date1904 and $serial < PHANTOM_SERIAL;
    if (not $date1904 and $serial >= PHANTOM_SERIAL and $serial < PHANTOM_SERIAL + 1.0) {
        # Serial 60 is the day that never happened; read it as 1900-02-28.
        $effective = PHANTOM_SERIAL - 1.0;
        $early = true;
    }
    def seconds as int init math.round($effective * convert.toFloat(DAY_SECONDS));
    return time.add(dateOrigin($date1904, $early), time.fromSeconds($seconds));
}
