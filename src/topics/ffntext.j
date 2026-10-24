# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the text and date halves of the formula function library.
# Spliced into sheets.j via include - not a standalone module.

/**
 * Apply a text function.
 *
 * Positions are one-based, the spreadsheet convention.
 *
 * @param name {string} the function name
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the result, or `#NAME?` when this family declines
 */
func applyTextFunction(name as string, flat as list of Value) {
    match ($name) {
        when "CONCATENATE", "CONCAT" { return fnConcat($flat); }
        when "LEN" { return textLength($flat); }
        when "UPPER" { return mappedText($flat, "upper"); }
        when "LOWER" { return mappedText($flat, "lower"); }
        when "TRIM" { return mappedText($flat, "trim"); }
        when "PROPER" { return mappedText($flat, "proper"); }
        when "LEFT" { return fnLeft($flat); }
        when "RIGHT" { return fnRight($flat); }
        when "MID" { return fnMid($flat); }
        when "FIND" { return fnFind($flat, true); }
        when "SEARCH" { return fnFind($flat, false); }
        when "SUBSTITUTE" { return fnSubstitute($flat); }
        when "REPLACE" { return fnReplace($flat); }
        when "REPT" { return fnRept($flat); }
        when "TEXT" { return fnText($flat); }
        when "VALUE" { return fnValue($flat); }
        when "EXACT" { return fnExact($flat); }
        when "CHAR" { return fnChar($flat); }
        when "CODE" { return fnCode($flat); }
        when "T" { return fnT($flat); }
        when "N" { return fnN($flat); }
        else { return Value.Err{code: ERR_NAME}; }
    }
}

/**
 * Join every argument's text.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the joined text
 */
func fnConcat(flat as list of Value) {
    def parts as list of string init [];
    for (def v in $flat) {
        $parts[] = asString($v);
    }
    return grownText(strings.join($parts, ""));
}

/**
 * The length of the first argument's text.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the length, or an error value
 */
func textLength(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Number{amount: convert.toFloat(len(asString($flat[0])))};
}

/**
 * A text transformation over the first argument.
 *
 * @param flat {list of Value} the flattened arguments
 * @param how {string} the transformation's name
 * @return {Value} the transformed text, or an error value
 */
func mappedText(flat as list of Value, how as string) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def body as string init asString($flat[0]);
    match ($how) {
        when "upper" { return Value.Text{body: strings.upper($body)}; }
        when "lower" { return Value.Text{body: strings.lower($body)}; }
        when "trim" { return Value.Text{body: collapseSpaces($body)}; }
        when "proper" { return Value.Text{body: titleCase($body)}; }
        else { return Value.Err{code: ERR_NAME}; }
    }
}

/**
 * Text with leading, trailing and repeated inner spaces collapsed.
 *
 * A spreadsheet's `TRIM` also squeezes runs of inner spaces to one.
 *
 * @param body {string} the text
 * @return {string} the collapsed text
 */
func collapseSpaces(body as string) {
    def words as list of string init [];
    for (def word in strings.split($body, " ")) {
        if ($word != "") {
            $words[] = $word;
        }
    }
    return strings.join($words, " ");
}

/**
 * Text with the first letter of each word in upper case.
 *
 * @param body {string} the text
 * @return {string} the title-cased text
 */
func titleCase(body as string) {
    def out as list of string init [];
    def atStart as bool init true;
    for (def ch in strings.chars($body)) {
        if ($atStart) {
            $out[] = strings.upper($ch);
        } else {
            $out[] = strings.lower($ch);
        }
        $atStart = not isLetter($ch) and not isDigit($ch);
    }
    return strings.join($out, "");
}

/**
 * The leftmost characters of the first argument.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or an error value
 */
func fnLeft(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def chars as list of string init strings.chars(asString($flat[0]));
    def want as int init countArg($flat, 1, 1);
    if ($want < 0) {
        return Value.Err{code: ERR_VALUE};
    }
    if ($want > len($chars)) {
        $want = len($chars);
    }
    return Value.Text{body: strings.join($chars[0..$want], "")};
}

/**
 * The rightmost characters of the first argument.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or an error value
 */
func fnRight(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def chars as list of string init strings.chars(asString($flat[0]));
    def want as int init countArg($flat, 1, 1);
    if ($want < 0) {
        return Value.Err{code: ERR_VALUE};
    }
    if ($want > len($chars)) {
        $want = len($chars);
    }
    return Value.Text{body: strings.join($chars[(len($chars) - $want)..len($chars)], "")};
}

/**
 * A run of characters from the middle of the first argument.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or an error value
 */
func fnMid(flat as list of Value) {
    if (len($flat) < 3) {
        return Value.Err{code: ERR_VALUE};
    }
    def chars as list of string init strings.chars(asString($flat[0]));
    def start as int init countArg($flat, 1, 1);
    def want as int init countArg($flat, 2, 0);
    if ($start < 1 or $want < 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def from as int init $start - 1;
    if ($from >= len($chars)) {
        return Value.Text{body: ""};
    }
    def stop as int init $from + $want;
    if ($stop > len($chars)) {
        $stop = len($chars);
    }
    return Value.Text{body: strings.join($chars[$from..$stop], "")};
}

/**
 * An integer argument, or a default when it is absent.
 *
 * @param flat {list of Value} the flattened arguments
 * @param at {int} which argument
 * @param fallback {int} the value when it is absent
 * @return {int} the integer, or `-1` when it will not read as one
 */
func countArg(flat as list of Value, at as int, fallback as int) {
    if ($at >= len($flat)) {
        return $fallback;
    }
    def amount as float init 0.0;
    def ok as bool init true;
    try {
        $amount = asNumber($flat[$at]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return -1;
    }
    return math.trunc($amount);
}

/**
 * Where one piece of text sits inside another, one-based.
 *
 * `FIND` is case-sensitive and `SEARCH` is not; nothing else differs.
 *
 * @param flat {list of Value} the flattened arguments
 * @param caseSensitive {bool} whether case matters
 * @return {Value} the position, or `#VALUE!` when it is not there
 */
func fnFind(flat as list of Value, caseSensitive as bool) {
    if (len($flat) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def needle as string init asString($flat[0]);
    def haystack as string init asString($flat[1]);
    if (not $caseSensitive) {
        $needle = strings.lower($needle);
        $haystack = strings.lower($haystack);
    }
    def from as int init countArg($flat, 2, 1);
    if ($from < 1) {
        return Value.Err{code: ERR_VALUE};
    }
    def chars as list of string init strings.chars($haystack);
    if ($from - 1 > len($chars)) {
        return Value.Err{code: ERR_VALUE};
    }
    def tail as string init strings.join($chars[($from - 1)..len($chars)], "");
    def found as int init strings.indexOf($tail, $needle);
    if ($found < 0) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Number{amount: convert.toFloat($found + $from)};
}

/**
 * Replace every occurrence of one piece of text with another.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or an error value
 */
func fnSubstitute(flat as list of Value) {
    if (len($flat) < 3) {
        return Value.Err{code: ERR_VALUE};
    }
    def body as string init asString($flat[0]);
    def needle as string init asString($flat[1]);
    def replacement as string init asString($flat[2]);
    # Replacing an empty string would match everywhere; a spreadsheet hands
    # the text back untouched instead.
    if ($needle == "") {
        return Value.Text{body: $body};
    }
    def parts as list of string init strings.split($body, $needle);
    def hits as int init len($parts) - 1;
    def grown as int init len($body) + $hits * (len($replacement) - len($needle));
    if ($grown > MAX_TEXT_RESULT) {
        return Value.Err{code: ERR_VALUE};
    }
    if (len($flat) < 4) {
        return Value.Text{body: strings.join($parts, $replacement)};
    }
    # A fourth argument picks one occurrence, counting from 1. Rejoining
    # around that seam is how the one gets replaced without an indexOf that
    # takes a start offset, which `strings` does not have.
    def which as int init countArg($flat, 3, 0);
    if ($which < 1) {
        return Value.Err{code: ERR_VALUE};
    }
    if ($which > $hits) {
        return Value.Text{body: $body};
    }
    def before as string init strings.join(lists.slice($parts, 0, $which), $needle);
    def after as string init strings.join(lists.slice($parts, $which, len($parts)), $needle);
    return Value.Text{body: $before + $replacement + $after};
}

/**
 * WEEKDAY: which day of the week a date falls on.
 *
 * The second argument chooses where the week starts, numbered as both
 * reference applications do: type 1 (the default) counts from Sunday as 1,
 * type 2 from Monday as 1, type 3 from Monday as 0, and types 11 to 17 from
 * Monday through Sunday as 1. The oracle caught an earlier version ignoring
 * the argument.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the day number, or an error
 */
func fnWeekday(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def ok as bool init true;
    try {
        $at = asTime($flat[0]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    def kind as int init 1;
    if (len($flat) > 1) {
        $kind = countArg($flat, 1, 1);
    }
    # `time.weekday` is zero-based from Sunday.
    def sunday as int init time.weekday($at);
    if ($kind == 1) {
        return Value.Number{amount: convert.toFloat($sunday + 1)};
    }
    if ($kind == 2) {
        return Value.Number{amount: convert.toFloat(($sunday + 6) % 7 + 1)};
    }
    if ($kind == 3) {
        return Value.Number{amount: convert.toFloat(($sunday + 6) % 7)};
    }
    if ($kind >= 11 and $kind <= 17) {
        def base as int init ($kind - 10) % 7;
        return Value.Number{amount: convert.toFloat(($sunday - $base + 7) % 7 + 1)};
    }
    return Value.Err{code: ERR_NUM};
}

/**
 * Replace a run of characters by position.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or an error value
 */
func fnReplace(flat as list of Value) {
    if (len($flat) < 4) {
        return Value.Err{code: ERR_VALUE};
    }
    def chars as list of string init strings.chars(asString($flat[0]));
    def start as int init countArg($flat, 1, 1);
    def want as int init countArg($flat, 2, 0);
    if ($start < 1 or $want < 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def from as int init $start - 1;
    if ($from > len($chars)) {
        $from = len($chars);
    }
    def stop as int init $from + $want;
    if ($stop > len($chars)) {
        $stop = len($chars);
    }
    return Value.Text{
        body: strings.join($chars[0..$from], "") + asString($flat[3]) +
            strings.join($chars[$stop..len($chars)], "")
    };
}

/**
 * Repeat text a number of times.
 *
 * Bounded by `MAX_TEXT_RESULT`: `REPT("x", 1000000000)` is a legal
 * expression and a denial of service.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or an error value
 */
func fnRept(flat as list of Value) {
    if (len($flat) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def body as string init asString($flat[0]);
    def times as int init countArg($flat, 1, 0);
    if ($times < 0) {
        return Value.Err{code: ERR_VALUE};
    }
    if ($times == 0 or $body == "") {
        return Value.Text{body: ""};
    }
    if (len($body) * $times > MAX_TEXT_RESULT) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Text{body: strings.repeat($body, $times)};
}

/**
 * The longest text a cell can hold, and so the longest `REPT` will build.
 *
 * Both formats cap a cell at this length. `REPT` and `SUBSTITUTE` are
 * bounded here because their result size is known before the string exists;
 * concatenation is bounded by `MAX_TEXT_GROWTH` instead.
 */
export def const MAX_TEXT_RESULT as int init 32767;

/**
 * Render a value through a number format code.
 *
 * Goes through `applyFormat`, the engine `displayAt` uses, so `TEXT` and a
 * cell's own format always agree on what a code means.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or an error value
 */
func fnText(flat as list of Value) {
    if (len($flat) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Text{body: applyFormat($flat[0], asString($flat[1]))};
}

/**
 * Read text as a number.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the number, or `#VALUE!`
 */
func fnValue(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def amount as float init 0.0;
    def ok as bool init true;
    try {
        $amount = asNumber($flat[0]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Number{amount: $amount};
}

/**
 * Whether two pieces of text are the same, case included.
 *
 * Case-sensitive, unlike `=`.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} whether they match
 */
func fnExact(flat as list of Value) {
    if (len($flat) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Bool{flag: asString($flat[0]) == asString($flat[1])};
}

/**
 * The character a code point names.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the character, or an error value
 */
func fnChar(flat as list of Value) {
    def point as int init countArg($flat, 0, -1);
    if ($point < 1 or $point > 1114111) {
        return Value.Err{code: ERR_VALUE};
    }
    def out as string init "";
    try {
        $out = convert.fromCodepoint($point);
    } catch (e) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Text{body: $out};
}

/**
 * The code point of the first character.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the code point, or an error value
 */
func fnCode(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def chars as list of string init strings.chars(asString($flat[0]));
    if (len($chars) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def point as int init 0;
    try {
        $point = convert.toCodepoint($chars[0]);
    } catch (e) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Number{amount: convert.toFloat($point)};
}

/**
 * The argument if it is text, otherwise nothing.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the text, or empty
 */
func fnT(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Text{body: ""};
    }
    def first as Value init $flat[0];
    match ($first) {
        when Text(t) { return Value.Text{body: $t.body}; }
        else { return Value.Text{body: ""}; }
    }
}

/**
 * The argument as a number, or zero when it is not one.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the number
 */
func fnN(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Number{amount: 0.0};
    }
    def amount as float init 0.0;
    try {
        $amount = asNumber($flat[0]);
    } catch (e) {
        return Value.Number{amount: 0.0};
    }
    return Value.Number{amount: $amount};
}

/**
 * Apply a date function.
 *
 * Results are date (`Stamp`) values. A numeric argument is read as a serial
 * in the 1900 system (see `asTime`), whatever the workbook's `date1904`.
 *
 * @param name {string} the function name
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the result, or `#NAME?` when this family declines
 */
func applyDateFunction(name as string, flat as list of Value) {
    match ($name) {
        when "TODAY" { return fnToday(); }
        when "NOW" { return fnNow(); }
        when "DATE" { return fnDate($flat); }
        when "YEAR" { return datePart($flat, "year"); }
        when "MONTH" { return datePart($flat, "month"); }
        when "DAY" { return datePart($flat, "day"); }
        when "HOUR" { return datePart($flat, "hour"); }
        when "MINUTE" { return datePart($flat, "minute"); }
        when "SECOND" { return datePart($flat, "second"); }
        when "WEEKDAY" { return fnWeekday($flat); }
        when "DATEVALUE" { return fnDateValue($flat); }
        when "DAYS" { return fnDays($flat); }
        when "EDATE" { return fnEdate($flat); }
        else { return Value.Err{code: ERR_NAME}; }
    }
}

/**
 * Today's date, as a date value.
 *
 * @return {Value} the date
 */
func fnToday() {
    def now as time.Time init time.now();
    def day as string init time.format($now, "%Y-%m-%d");
    def at as time.Time init time.fromIso($day + "T00:00:00Z");
    return Value.Stamp{at: $at, dateOnly: true};
}

/**
 * The current instant, as a date-and-time value.
 *
 * @return {Value} the instant
 */
func fnNow() {
    return Value.Stamp{at: time.now(), dateOnly: false};
}

/**
 * A date from a year, a month and a day.
 *
 * A month or day outside its range rolls over, as in a spreadsheet:
 * `DATE(2026, 13, 1)` is January 2027. A year outside 1900-9999 is `#NUM!`.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the date, or an error value
 */
func fnDate(flat as list of Value) {
    if (len($flat) < 3) {
        return Value.Err{code: ERR_VALUE};
    }
    def year as int init countArg($flat, 0, -1);
    def month as int init countArg($flat, 1, -1);
    def day as int init countArg($flat, 2, -1);
    if ($year < 0 or $month < -9999 or $day < -9999) {
        return Value.Err{code: ERR_VALUE};
    }
    if ($year < 1900 or $year > 9999) {
        return Value.Err{code: ERR_NUM};
    }
    # The rollover is done by starting at the first of the month and adding
    # days, rather than by validating: that is both simpler and what gives
    # the spreadsheet's answer for a month of 13.
    def wholeYears as int init ($month - 1) // 12;
    def normalMonth as int init ($month - 1) % 12 + 1;
    def baseYear as int init $year + $wholeYears;
    if ($baseYear < 1900 or $baseYear > 9999) {
        return Value.Err{code: ERR_NUM};
    }
    def iso as string init convert.toString($baseYear) + "-" +
        twoDigits($normalMonth) + "-01T00:00:00Z";
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def ok as bool init true;
    try {
        $at = time.fromIso($iso);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_NUM};
    }
    return Value.Stamp{at: time.add($at, time.fromSeconds(($day - 1) * 86400)), dateOnly: true};
}

/**
 * A number as two digits.
 *
 * @param n {int} the number
 * @return {string} the digits
 */
func twoDigits(n as int) {
    if ($n < 10) {
        return "0" + convert.toString($n);
    }
    return convert.toString($n);
}

/**
 * One component of a date.
 *
 * @param flat {list of Value} the flattened arguments
 * @param which {string} the component
 * @return {Value} the component, or an error value
 */
func datePart(flat as list of Value, which as string) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def ok as bool init true;
    try {
        $at = asTime($flat[0]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    match ($which) {
        when "year" { return Value.Number{amount: convert.toFloat(time.year($at))}; }
        when "month" { return Value.Number{amount: convert.toFloat(time.month($at))}; }
        when "day" { return Value.Number{amount: convert.toFloat(time.day($at))}; }
        when "hour" { return Value.Number{amount: convert.toFloat(time.hour($at))}; }
        when "minute" { return Value.Number{amount: convert.toFloat(time.minute($at))}; }
        when "second" { return Value.Number{amount: convert.toFloat(time.second($at))}; }
        when "weekday" {
            # One-based with Sunday first, which is the default a spreadsheet
            # uses and not what `time.weekday` gives.
            return Value.Number{amount: convert.toFloat(time.weekday($at) + 1)};
        }
        else { return Value.Err{code: ERR_NAME}; }
    }
}

/**
 * A date read from text.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the date, or an error value
 */
func fnDateValue(flat as list of Value) {
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def ok as bool init true;
    try {
        $at = parseIsoDate(asString($flat[0]));
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Stamp{at: $at, dateOnly: true};
}

/**
 * How many days lie between two dates.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the count, or an error value
 */
func fnDays(flat as list of Value) {
    if (len($flat) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def later as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def earlier as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def ok as bool init true;
    try {
        $later = asTime($flat[0]);
        $earlier = asTime($flat[1]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    def seconds as int init time.seconds(time.sub($later, $earlier));
    return Value.Number{amount: convert.toFloat($seconds // 86400)};
}

/**
 * A date a number of months away from another.
 *
 * The day is clamped to the target month's end, as both reference
 * applications do: one month after 31 January is 28 February.
 *
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the date, or an error value
 */
func fnEdate(flat as list of Value) {
    if (len($flat) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def ok as bool init true;
    try {
        $at = asTime($flat[0]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    def months as int init countArg($flat, 1, 0);
    # The day is clamped to the end of the target month, not rolled over:
    # one month after 31 January is 28 February, which is what both reference
    # applications give. Letting `fnDate` normalise the overflow produced
    # 3 March instead.
    def total as int init time.year($at) * 12 + time.month($at) - 1 + $months;
    def year as int init $total // 12;
    def month as int init $total % 12 + 1;
    def day as int init time.day($at);
    def last as int init daysInMonth($year, $month);
    if ($day > $last) {
        $day = $last;
    }
    def args as list of Value init [];
    $args[] = Value.Number{amount: convert.toFloat($year)};
    $args[] = Value.Number{amount: convert.toFloat($month)};
    $args[] = Value.Number{amount: convert.toFloat($day)};
    return fnDate($args);
}

/**
 * How many days a month has.
 *
 * @param year {int} the year, so February is right
 * @param month {int} the month, 1 to 12
 * @return {int} the number of days
 */
func daysInMonth(year as int, month as int) {
    def lengths as list of int init [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if ($month < 1 or $month > 12) {
        return 31;
    }
    if ($month == 2 and isLeapYear($year)) {
        return 29;
    }
    return $lengths[$month - 1];
}

/**
 * Whether a year is a leap year in the proleptic Gregorian calendar.
 *
 * @param year {int} the year
 * @return {bool} whether February has 29 days
 */
func isLeapYear(year as int) {
    if ($year % 400 == 0) {
        return true;
    }
    if ($year % 100 == 0) {
        return false;
    }
    return $year % 4 == 0;
}
