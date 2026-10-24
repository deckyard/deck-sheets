# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - applying a number format code to a value.
#
# A cell holds a value and, separately, a format code saying how to show it.
# Everywhere else in this deck those two stay apart: `asString` renders the
# value plainly, which is what a program wants. This file is the other
# direction - what a person would see in the application - and it is a
# separate topic because the format code is a small language of its own.
#
# The language, as both formats and every application have it:
#
#   up to four sections separated by `;`, for positive, negative, zero and
#   text, or guarded by conditions such as `[>=100]`;
#   `0` `#` `?` digit placeholders around a `.`, with `,` meaning grouping
#   between them and scaling by a thousand after them;
#   `%` scaling by a hundred, `E+00` scientific, `?/?` fractions;
#   the date and time tokens, where `m` means month or minute depending on
#   what sits next to it;
#   `"..."` literals, `\x` escapes, `_x` a blank the width of `x`, `*x` a fill,
#   `@` the text itself, and `[Red]`-style modifiers that say nothing about
#   the text.
#
# Every expected rendering in the tests was taken from LibreOffice and
# Gnumeric, through `tools/format-oracle.sh` and through `tools/formula-oracle.sh`
# by way of `TEXT`. Several of the rules below read as arbitrary and are not:
# they are what those two do.

/**
 * The widest number this engine will place digit by digit.
 *
 * Above it the rounding arithmetic would overflow an int64 on the way to a
 * digit string (`amount * 10^places`), so the value is rendered plainly
 * instead. 10^15 keeps a format with four decimal places inside the range.
 */
export def const MAX_FORMATTED as float init 1000000000000000.0;

/**
 * How a rendering spells the things that differ between regions.
 *
 * A format *code* is locale-independent - a German LibreOffice writes
 * `#,##0.00` and `dd/mm/yyyy` exactly as an English one does, and a file
 * always stores a number with a dot - but what an application *shows* for
 * one is not. The same `#,##0.00` is `1,234.50` in Chicago and `1.234,50` in
 * Cologne, and `dddd` is `Monday` or `Montag`.
 *
 * So the separators and the names are a parameter. This is a mechanism, not
 * a locale database: the deck ships the English spellings, because
 * `time.format` gives those and nothing else, and a caller who wants another
 * language supplies the names.
 *
 * @field decimal {string} what separates a whole number from its fraction
 * @field grouping {string} what separates thousands
 * @field months {list of string} the twelve month names, January first
 * @field monthAbbrevs {list of string} their short forms, `[]` to cut the full ones
 * @field days {list of string} the seven weekday names, Sunday first
 * @field dayAbbrevs {list of string} their short forms, `[]` to cut the full ones
 */
export def struct Locale {
    decimal as string,
    grouping as string,
    months as list of string,
    monthAbbrevs as list of string,
    days as list of string,
    dayAbbrevs as list of string
};

/**
 * The spellings this deck renders with unless told otherwise.
 *
 * A dot and a comma, and the month and weekday names `time.format` gives -
 * which are English whatever the process locale says, so they are what the
 * tests and the oracle both assume.
 *
 * @return {Locale} the default
 * @example
 *   applyFormatIn($v, "#,##0.00", defaultLocale());
 */
export func defaultLocale() {
    return Locale{
        decimal: ".",
        grouping: ",",
        months: [],
        monthAbbrevs: [],
        days: [],
        dayAbbrevs: []
    };
}

/**
 * The same locale with different separators.
 *
 * The whole of what most regions differ by. German is `withSeparators(
 * defaultLocale(), ",", ".")`.
 *
 * @param it {Locale} the locale
 * @param decimal {string} what separates a whole number from its fraction
 * @param grouping {string} what separates thousands
 * @return {Locale} a fresh locale
 * @example
 *   def german as Locale init withSeparators(defaultLocale(), ",", ".");
 *   applyFormatIn(number(1234.5), "#,##0.00", $german);   # "1.234,50"
 */
export func withSeparators(it as Locale, decimal as string, grouping as string) {
    def out as Locale init $it;
    $out.decimal = $decimal;
    $out.grouping = $grouping;
    return $out;
}

/**
 * The same locale with its own month names.
 *
 * @param it {Locale} the locale
 * @param full {list of string} the twelve names, January first
 * @param short {list of string} the twelve short forms, or `[]` to cut `full`
 * @return {Locale} a fresh locale
 * @throws {Error} kind "sheets" when a list is given and does not hold twelve names
 */
export func withMonthNames(it as Locale, full as list of string, short as list of string) {
    checkNameCount($full, 12, "month");
    checkNameCount($short, 12, "month");
    def out as Locale init $it;
    $out.months = $full;
    $out.monthAbbrevs = $short;
    return $out;
}

/**
 * The same locale with its own weekday names.
 *
 * @param it {Locale} the locale
 * @param full {list of string} the seven names, Sunday first
 * @param short {list of string} the seven short forms, or `[]` to cut `full`
 * @return {Locale} a fresh locale
 * @throws {Error} kind "sheets" when a list is given and does not hold seven names
 */
export func withDayNames(it as Locale, full as list of string, short as list of string) {
    checkNameCount($full, 7, "weekday");
    checkNameCount($short, 7, "weekday");
    def out as Locale init $it;
    $out.days = $full;
    $out.dayAbbrevs = $short;
    return $out;
}

/**
 * Refuse a list of names that is the wrong length.
 *
 * An empty list means "this deck's own", so only a wrong non-empty one is an
 * error - and it has to be one, because a short list would silently render
 * some months and not others.
 *
 * @param names {list of string} the names
 * @param wanted {int} how many there should be
 * @param what {string} the kind of name, for the message
 * @throws {Error} kind "sheets" when the list is neither empty nor the right length
 */
func checkNameCount(names as list of string, wanted as int, what as string) {
    if (len($names) == 0 or len($names) == $wanted) {
        return;
    }
    fail("a locale needs " + convert.toString($wanted) + " " + $what +
        " names or none, not " + convert.toString(len($names)));
}

/**
 * One of a locale's names, or `""` when it supplies none.
 *
 * @param names {list of string} the locale's list
 * @param at {int} the zero-based index
 * @return {string} the name, or `""`
 */
func localeName(names as list of string, at as int) {
    if ($at < 0 or $at >= len($names)) {
        return "";
    }
    return $names[$at];
}

/**
 * The longest format code this engine will read.
 *
 * Excel's own limit for a format code, and far past any real one: the
 * longest in the built-in table is 30 characters. The cap is here because a
 * code comes from a *file*, so it is untrusted input, and two of the scans
 * over it are quadratic in its length - a code of 10 000 unclosed brackets
 * measured 49 s, and one of 100 000 commas did not finish.
 */
export def const MAX_FORMAT_CODE as int init 255;

/**
 * Apply a number format code to a value, as an application would show it.
 *
 * `""` and `"General"` mean no format, which renders the value plainly. A
 * code that cannot be read renders plainly too rather than failing: a format
 * is a presentation detail, and a file full of exotic codes should still be
 * readable.
 *
 * @param v {Value} the cell's value
 * @param code {string} the number format code
 * @return {string} the value as the format shows it
 * @example
 *   applyFormat(number(1234.5), "#,##0.00");       # "1,234.50"
 *   applyFormat(number(-12.0), "0.00;(0.00)");     # "(12.00)"
 *   applyFormat(number(0.075), "0.0%");            # "7.5%"
 *   applyFormat(date(time.fromIso("2026-10-02T00:00:00Z")), "d mmm yyyy");
 *   # "2 Oct 2026"
 */
export func applyFormat(v as Value, code as string) {
    return applyFormatIn($v, $code, defaultLocale());
}

/**
 * Apply a number format code, spelling the separators and names a region's way.
 *
 * `applyFormat` is this with `defaultLocale()`. See `Locale` for why a format
 * code is locale-independent and a rendering of one is not.
 *
 * @param v {Value} the cell's value
 * @param code {string} the number format code
 * @param locale {Locale} how to spell the separators and the names
 * @return {string} the value as the format shows it
 * @example
 *   def german as Locale init withSeparators(defaultLocale(), ",", ".");
 *   applyFormatIn(number(1234.5), "#,##0.00", $german);   # "1.234,50"
 */
export func applyFormatIn(v as Value, code as string, locale as Locale) {
    if (isGeneralFormat($code)) {
        return asString($v);
    }
    def sections as list of string init formatSections($code);
    match ($v) {
        when Empty { return ""; }
        when Err(e) { return $e.code; }
        when Text(t) { return renderTextSection($t.body, textSectionOf($sections)); }
        when Bool(b) { return asString($v); }
        else {
        }
    }
    def amount as float init 0.0;
    def numeric as bool init true;
    try {
        $amount = asNumber($v);
    } catch (e) {
        $numeric = false;
    }
    if (not $numeric) {
        return asString($v);
    }
    def section as string init numberSectionOf($sections, $amount);
    if ($section == "") {
        return "";
    }
    return renderValueSection($v, $amount, $section, len($sections), $locale);
}

/**
 * Render one chosen section, as a date or as a number.
 *
 * @param v {Value} the value, for the date path which wants the instant
 * @param amount {float} the value as a number
 * @param section {string} the section to render through
 * @param count {int} how many sections the code had
 * @param locale {Locale} how to spell the separators and the names
 * @return {string} the rendering
 */
func renderValueSection(
    v as Value,
    amount as float,
    section as string,
    count as int,
    locale as Locale) {
    def visible as string init visibleSection($section);
    if (isDateSection($visible)) {
        return renderDateSection($v, $amount, $visible, $locale);
    }
    # With two or more sections the negative one renders the magnitude: the
    # sign is whatever that section spells out, which is the point of being
    # able to write `0.00;(0.00)`.
    def shown as float init $amount;
    if ($count > 1 and $shown < 0.0) {
        $shown = -$shown;
    }
    return renderNumberSection($shown, $visible, $locale);
}

/**
 * Whether a code means "no format".
 *
 * @param code {string} the number format code
 * @return {bool} whether it is empty or the general format
 */
func isGeneralFormat(code as string) {
    def trimmed as string init strings.trim($code);
    if ($trimmed == "") {
        return true;
    }
    if (len($trimmed) > MAX_FORMAT_CODE) {
        # Too long to be a real code, and long enough to be an attack. The
        # value renders plainly, which is what every other unreadable code
        # does.
        return true;
    }
    return strings.lower($trimmed) == "general";
}

/**
 * Split a format code into its sections.
 *
 * On unquoted, unbracketed semicolons only, so a literal `;` inside a
 * quoted run stays where it is.
 *
 * @param code {string} the number format code
 * @return {list of string} the sections, in order
 */
func formatSections(code as string) {
    def out as list of string init [];
    def current as list of string init [];
    def inQuote as bool init false;
    def inBracket as bool init false;
    def chars as list of string init strings.chars($code);
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if ($ch == "\\" and $i + 1 < len($chars)) {
            $current[] = $ch;
            $current[] = $chars[$i + 1];
            $i = $i + 2;
            continue;
        }
        if ($ch == "\"") {
            $inQuote = not $inQuote;
        } elseif ($ch == "[" and not $inQuote) {
            $inBracket = true;
        } elseif ($ch == "]" and not $inQuote) {
            $inBracket = false;
        } elseif ($ch == ";" and not $inQuote and not $inBracket) {
            $out[] = strings.join($current, "");
            $current = [];
            $i = $i + 1;
            continue;
        }
        $current[] = $ch;
        $i = $i + 1;
    }
    $out[] = strings.join($current, "");
    return $out;
}

/**
 * The section a text value is shown through.
 *
 * A fourth section is the text section. With fewer than four, text is shown
 * as itself, which both applications do.
 *
 * @param sections {list of string} the code's sections
 * @return {string} the section, or `"@"` when there is none
 */
func textSectionOf(sections as list of string) {
    if (len($sections) >= 4) {
        return visibleSection($sections[3]);
    }
    # With fewer than four sections, text is shown as itself - unless the
    # code is a text format already, which is what a code holding `@` and no
    # digit placeholder is. `"["@"]"` has one section and does apply.
    def first as string init visibleSection($sections[0]);
    if (strings.contains($first, "@") and not scanNumShape($first).anySlot) {
        return $first;
    }
    return "@";
}

/**
 * The section a number is shown through.
 *
 * Conditions first, in order, because a code that states them says nothing
 * about sign. Otherwise the positions mean positive, negative and zero, and
 * a code with two sections uses the first for zero as well.
 *
 * @param sections {list of string} the code's sections
 * @param amount {float} the number
 * @return {string} the section to render through
 */
func numberSectionOf(sections as list of string, amount as float) {
    def guarded as bool init false;
    for (def i in 0..len($sections)) {
        def test as FormatGuard init guardOf($sections[$i]);
        if (not $test.has) {
            continue;
        }
        $guarded = true;
        if (guardAccepts($test, $amount)) {
            return $test.rest;
        }
    }
    if ($guarded) {
        # Every condition declined. Both applications fall back to the last
        # unguarded section, and show `###` when there is not one.
        for (def i in 0..len($sections)) {
            def test as FormatGuard init guardOf($sections[$i]);
            if (not $test.has) {
                return $sections[$i];
            }
        }
        return "\"###\"";
    }
    if ($amount < 0.0 and len($sections) > 1) {
        return $sections[1];
    }
    if ($amount == 0.0 and len($sections) > 2) {
        return $sections[2];
    }
    return $sections[0];
}

/**
 * A condition on a section, such as `[>=100]`.
 *
 * @field has {bool} whether the section carries one
 * @field op {string} the comparison, such as `">="`
 * @field value {float} the number compared against
 * @field rest {string} the section with the condition removed
 */
def struct FormatGuard {
    has as bool,
    op as string,
    value as float,
    rest as string
};

/**
 * Read a section's leading condition, if it has one.
 *
 * @param section {string} the section
 * @return {FormatGuard} the condition, with `has` false when there is none
 */
func guardOf(section as string) {
    def none as FormatGuard init FormatGuard{has: false, op: "", value: 0.0, rest: $section};
    if (not strings.startsWith($section, "[")) {
        return $none;
    }
    def close as int init strings.indexOf($section, "]");
    if ($close < 0) {
        return $none;
    }
    def inside as string init strings.substring($section, 1, $close);
    def op as string init "";
    for (def candidate in ["<=", ">=", "<>", "<", ">", "="]) {
        if (strings.startsWith($inside, $candidate)) {
            $op = $candidate;
            break;
        }
    }
    if ($op == "") {
        return $none;
    }
    def amount as float init 0.0;
    try {
        $amount = convert.toFloat(strings.trim(strings.substring($inside, len($op), len($inside))));
    } catch (e) {
        return $none;
    }
    return FormatGuard{
        has: true,
        op: $op,
        value: $amount,
        rest: strings.substring($section, $close + 1, len($section))
    };
}

/**
 * Whether a number satisfies a section's condition.
 *
 * @param guard {FormatGuard} the condition
 * @param amount {float} the number
 * @return {bool} whether the section applies
 */
func guardAccepts(guard as FormatGuard, amount as float) {
    match ($guard.op) {
        when "<" { return $amount < $guard.value; }
        when ">" { return $amount > $guard.value; }
        when "<=" { return $amount <= $guard.value; }
        when ">=" { return $amount >= $guard.value; }
        when "=" { return $amount == $guard.value; }
        when "<>" { return $amount != $guard.value; }
        else { return false; }
    }
}

/**
 * A section with the modifiers that say nothing about the text removed.
 *
 * `[Red]`, `[$-409]` and a condition are all dropped. `[h]`, `[m]` and `[s]`
 * are kept, because those are elapsed-time tokens and do say something.
 *
 * @param section {string} the section
 * @return {string} the section with only meaningful brackets left
 */
func visibleSection(section as string) {
    def out as list of string init [];
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    def inQuote as bool init false;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if ($ch == "\\" and $i + 1 < len($chars)) {
            $out[] = $ch;
            $out[] = $chars[$i + 1];
            $i = $i + 2;
            continue;
        }
        if ($ch == "\"") {
            $inQuote = not $inQuote;
        }
        if ($ch == "[" and not $inQuote) {
            def close as int init charIndexFrom($chars, "]", $i);
            if ($close < 0) {
                $i = $i + 1;
                continue;
            }
            def inside as string init joinChars($chars, $i + 1, $close);
            if (isElapsedToken($inside)) {
                $out[] = "[";
                $out[] = $inside;
                $out[] = "]";
            }
            $i = $close + 1;
            continue;
        }
        $out[] = $ch;
        $i = $i + 1;
    }
    return strings.join($out, "");
}

/**
 * Whether a bracketed token is an elapsed-time token.
 *
 * @param inside {string} what the brackets hold
 * @return {bool} whether it is `h`, `m` or `s`, repeated
 */
func isElapsedToken(inside as string) {
    if (len($inside) == 0) {
        return false;
    }
    def first as string init strings.lower(strings.substring($inside, 0, 1));
    if ($first != "h" and $first != "m" and $first != "s") {
        return false;
    }
    for (def ch in strings.chars(strings.lower($inside))) {
        if ($ch != $first) {
            return false;
        }
    }
    return true;
}

/**
 * The shape of a numeric section, scanned once before anything is rendered.
 *
 * @field intSlots {int} how many digit placeholders sit before the point
 * @field fracSlots {int} how many sit after it
 * @field expSlots {int} how many sit after an `E`, 0 when there is none
 * @field grouped {bool} whether a comma between placeholders asked for grouping
 * @field thousands {int} how many trailing commas scale the value down
 * @field percents {int} how many `%` scale it up
 * @field fraction {bool} whether the section is a `?/?` fraction form
 * @field anySlot {bool} whether it holds any digit placeholder at all
 */
def struct NumShape {
    intSlots as int,
    fracSlots as int,
    expSlots as int,
    grouped as bool,
    thousands as int,
    percents as int,
    fraction as bool,
    anySlot as bool
};

/**
 * Scan a numeric section for its shape.
 *
 * @param section {string} the section, with modifiers already removed
 * @return {NumShape} what the section asks for
 */
func scanNumShape(section as string) {
    def out as NumShape init NumShape{
        intSlots: 0,
        fracSlots: 0,
        expSlots: 0,
        grouped: false,
        thousands: 0,
        percents: 0,
        fraction: false,
        anySlot: false
    };
    def chars as list of string init strings.chars($section);
    def where as string init "int";
    def i as int init 0;
    def trailing as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if ($ch == "\\" or $ch == "_" or $ch == "*") {
            $i = $i + 2;
            continue;
        }
        if ($ch == "\"") {
            $i = skipQuoted($chars, $i);
            continue;
        }
        if (isSlotChar($ch)) {
            $out.anySlot = true;
            if ($where == "int") {
                $out.intSlots = $out.intSlots + 1;
            } elseif ($where == "frac") {
                $out.fracSlots = $out.fracSlots + 1;
            } else {
                $out.expSlots = $out.expSlots + 1;
            }
            $trailing = 0;
        } elseif ($ch == ".") {
            $where = "frac";
            $trailing = 0;
        } elseif ($ch == ",") {
            $trailing = $trailing + 1;
            if (followsSlot($chars, $i) and precedesSlot($chars, $i)) {
                $out.grouped = true;
            }
        } elseif ($ch == "%") {
            $out.percents = $out.percents + 1;
            $trailing = 0;
        } elseif (strings.lower($ch) == "e" and isExponentStart($chars, $i)) {
            $where = "exp";
            $i = $i + 2;
            continue;
        } elseif ($ch == "/" and $out.anySlot) {
            $out.fraction = true;
            $trailing = 0;
        } else {
            $trailing = 0;
        }
        $i = $i + 1;
    }
    # Only commas at the very end of the digit skeleton scale the value.
    $out.thousands = $trailing;
    return $out;
}

/**
 * Whether a character is a digit placeholder.
 *
 * @param ch {string} the character
 * @return {bool} whether it is `0`, `#` or `?`
 */
func isSlotChar(ch as string) {
    return $ch == "0" or $ch == "#" or $ch == "?";
}

/**
 * Where a quoted run ends.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} the index of the opening quote
 * @return {int} the index just past the closing quote
 */
func skipQuoted(chars as list of string, at as int) {
    def close as int init charIndexFrom($chars, "\"", $at + 1);
    if ($close < 0) {
        return len($chars);
    }
    return $close + 1;
}

/**
 * Whether a digit placeholder sits before an index.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} the index to look back from
 * @return {bool} whether the character before it is a placeholder
 */
func followsSlot(chars as list of string, at as int) {
    if ($at == 0) {
        return false;
    }
    return isSlotChar($chars[$at - 1]);
}

/**
 * Whether a digit placeholder sits after an index.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} the index to look forward from
 * @return {bool} whether the character after it is a placeholder
 */
func precedesSlot(chars as list of string, at as int) {
    if ($at + 1 >= len($chars)) {
        return false;
    }
    return isSlotChar($chars[$at + 1]);
}

/**
 * Whether an `E` at an index introduces an exponent.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} the index of the `E`
 * @return {bool} whether a sign follows it
 */
func isExponentStart(chars as list of string, at as int) {
    if ($at + 1 >= len($chars)) {
        return false;
    }
    return $chars[$at + 1] == "+" or $chars[$at + 1] == "-";
}

/**
 * Render a number through a numeric section.
 *
 * @param amount {float} the number
 * @param section {string} the section, with modifiers already removed
 * @param locale {Locale} the locale whose separators the output uses
 * @return {string} the rendering
 */
func renderNumberSection(amount as float, section as string, locale as Locale) {
    def shape as NumShape init scanNumShape($section);
    if (not $shape.anySlot) {
        if (strings.contains($section, "@")) {
            # A section with no digit placeholders but a text one shows the
            # number as text, which is what both applications do for `@` -
            # and the text still spells its decimal point the region's way,
            # which the German pass of the format oracle caught.
            return renderTextSection(plainNumberIn($amount, $locale), $section);
        }
        # A section of pure literals, such as `"n/a"` or `-`, shows itself.
        return emitLiterals($section);
    }
    def scaled as float init scaleForShape($amount, $shape);
    if (math.abs($scaled) >= MAX_FORMATTED) {
        return plainNumberIn($amount, $locale);
    }
    if ($shape.expSlots > 0) {
        return emitScientific($scaled, $section, $shape, $locale);
    }
    if ($shape.fraction) {
        return emitFraction($scaled, $section, $shape);
    }
    return emitPlain($scaled, $section, $shape, $locale);
}

/**
 * A number rendered plainly, with the region's decimal separator.
 *
 * The fallback wherever a format cannot be applied - a value too wide for
 * the digit arithmetic, a date code over something that is not a date, or
 * the `@` of a text format. `numberText` always writes a dot, and it never
 * groups, so swapping the one separator is the whole of it.
 *
 * @param amount {float} the number
 * @param locale {Locale} how to spell the separator
 * @return {string} the rendering
 */
func plainNumberIn(amount as float, locale as Locale) {
    def body as string init numberText($amount);
    if ($locale.decimal == ".") {
        return $body;
    }
    return strings.replace($body, ".", $locale.decimal);
}

/**
 * Apply the scaling a section asks for.
 *
 * @param amount {float} the number
 * @param shape {NumShape} the section's shape
 * @return {float} the number as the digits will show it
 */
func scaleForShape(amount as float, shape as NumShape) {
    def out as float init $amount;
    for (def i in 0..$shape.percents) {
        $out = $out * 100.0;
    }
    for (def i in 0..$shape.thousands) {
        $out = $out / 1000.0;
    }
    return $out;
}

/**
 * The digits of a number, split at the point and rounded to a width.
 *
 * @field whole {string} the integer digits, with no sign
 * @field decimals {string} the fraction digits, padded to the width asked for
 * @field negative {bool} whether the number was below zero
 */
def struct NumDigits {
    whole as string,
    decimals as string,
    negative as bool
};

/**
 * Split a number into digit strings, rounded to a number of places.
 *
 * Rounded through integers rather than through text, so the result is the
 * digits the format asked for and not whatever a float prints as.
 *
 * @param amount {float} the number
 * @param places {int} how many fraction digits to keep
 * @return {NumDigits} the digits
 */
func digitsOf(amount as float, places as int) {
    def negative as bool init $amount < 0.0;
    def size as float init math.abs($amount);
    def kept as int init roundablePlaces($size, $places);
    def scale as int init 1;
    for (def i in 0..$kept) {
        $scale = $scale * 10;
    }
    def lifted as int init math.round($size * convert.toFloat($scale));
    def whole as int init $lifted // $scale;
    def rest as int init $lifted - $whole * $scale;
    def decimals as string init "";
    if ($kept > 0) {
        $decimals = convert.toString($rest);
        while (len($decimals) < $kept) {
            $decimals = "0" + $decimals;
        }
    }
    return NumDigits{whole: convert.toString($whole), decimals: $decimals, negative: $negative};
}

/**
 * How many decimal places can be rounded to without overflowing.
 *
 * The rounding lifts the value by `10^places` into an int, so a wide value
 * with a long format overflows an int64 and raises `kind: "runtime"` - which
 * this deck's error contract forbids and a file is free to ask for. Fifteen
 * is also about where a double runs out of significant digits, so nothing is
 * lost that was ever there; any further placeholders pad with zeros, which
 * is what they would have shown anyway.
 *
 * @param size {float} the value's magnitude
 * @param places {int} how many places the format asked for
 * @return {int} how many places to round to
 */
func roundablePlaces(size as float, places as int) {
    def kept as int init $places;
    if ($kept > 15) {
        $kept = 15;
    }
    def room as float init 1.0e18;
    while ($kept > 0) {
        def lifted as float init $size;
        for (def i in 0..$kept) {
            $lifted = $lifted * 10.0;
        }
        if ($lifted < $room) {
            return $kept;
        }
        $kept = $kept - 1;
    }
    return 0;
}

/**
 * Insert grouping separators into a run of digits.
 *
 * @param digits {string} the integer digits
 * @param separator {string} the grouping separator to insert
 * @return {string} the digits in groups of three
 */
func groupedDigits(digits as string, separator as string) {
    def chars as list of string init strings.chars($digits);
    def out as list of string init [];
    def counted as int init 0;
    for (def i in 0..len($chars)) {
        def at as int init len($chars) - 1 - $i;
        if ($counted == 3) {
            $out[] = $separator;
            $counted = 0;
        }
        $out[] = $chars[$at];
        $counted = $counted + 1;
    }
    def reversed as list of string init [];
    for (def i in 0..len($out)) {
        $reversed[] = $out[len($out) - 1 - $i];
    }
    return strings.join($reversed, "");
}

/**
 * A section laid out as alternating literal text and digit slots.
 *
 * The template is built left to right, because that is the only direction a
 * format code can be read: a quoted literal cannot be recognised backwards.
 * The integer slots are then filled right to left, which is the only
 * direction digits can be placed. Keeping those two passes apart is what
 * makes a pattern like `000-0000` come out right.
 *
 * @field pieces {list of string} one entry per literal chunk or slot
 * @field slots {list of string} the placeholder kind at each entry, `""` for a literal
 * @field parts {list of string} which part of the number each slot belongs to
 */
def struct NumTemplate {
    pieces as list of string,
    slots as list of string,
    parts as list of string
};

/**
 * Lay a numeric section out as literals and slots.
 *
 * @param section {string} the section, with modifiers already removed
 * @param shape {NumShape} the section's shape
 * @param locale {Locale} the locale whose separators the output uses
 * @return {NumTemplate} the layout
 */
func layOutNumber(section as string, shape as NumShape, locale as Locale) {
    def pieces as list of string init [];
    def slots as list of string init [];
    def parts as list of string init [];
    def chars as list of string init strings.chars($section);
    def where as string init "int";
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if (isSlotChar($ch)) {
            $pieces[] = "";
            $slots[] = $ch;
            $parts[] = $where;
            $i = $i + 1;
            continue;
        }
        if ($ch == ".") {
            # A point with no fraction placeholders after it is not shown,
            # which is what `#,##0.` means.
            $where = "frac";
            if ($shape.fracSlots > 0) {
                $pieces[] = $locale.decimal;
                $slots[] = "";
                $parts[] = "lit";
            }
            $i = $i + 1;
            continue;
        }
        if ($ch == "," and isSkeletonComma($chars, $i)) {
            # A comma among the digit placeholders is a flag, not a literal:
            # it either asked for grouping, in which case the separators are
            # already in the digit string, or for scaling, which has already
            # been applied to the value.
            $i = $i + 1;
            continue;
        }
        def step as LiteralStep init literalAt($chars, $i);
        if ($step.text != "") {
            $pieces[] = $step.text;
            $slots[] = "";
            $parts[] = "lit";
        }
        $i = $step.next;
    }
    return NumTemplate{pieces: $pieces, slots: $slots, parts: $parts};
}

/**
 * Whether a comma belongs to the digit skeleton rather than being literal.
 *
 * True when the run of commas it sits in follows a digit placeholder, which
 * covers both the grouping comma of `#,##0` and the scaling commas of
 * `0.0,,`. A comma anywhere else - `"a,b"`, or one trailing a date - is text.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} the comma's index
 * @return {bool} whether to drop it rather than show it
 */
func isSkeletonComma(chars as list of string, at as int) {
    def i as int init $at - 1;
    while ($i >= 0 and $chars[$i] == ",") {
        $i = $i - 1;
    }
    if ($i < 0) {
        return false;
    }
    return isSlotChar($chars[$i]);
}

/**
 * One literal chunk read from a format code.
 *
 * @field text {string} what it contributes to the output
 * @field next {int} the index to carry on from
 */
def struct LiteralStep {
    text as string,
    next as int
};

/**
 * Read whatever literal sits at an index.
 *
 * Handles the five spellings a format code has for "show this as it is":
 * a quoted run, a backslash escape, `_x` for a blank, `*x` for a fill, and
 * a bare character.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} where to read from
 * @return {LiteralStep} the text and where to carry on
 */
func literalAt(chars as list of string, at as int) {
    def ch as string init $chars[$at];
    if ($ch == "\"") {
        def close as int init charIndexFrom($chars, "\"", $at + 1);
        if ($close < 0) {
            return LiteralStep{text: joinChars($chars, $at + 1, len($chars)), next: len($chars)};
        }
        return LiteralStep{text: joinChars($chars, $at + 1, $close), next: $close + 1};
    }
    if ($ch == "\\" and $at + 1 < len($chars)) {
        return LiteralStep{text: $chars[$at + 1], next: $at + 2};
    }
    if ($ch == "_") {
        # The width of the character that follows, which without column
        # widths to align to is one blank.
        return LiteralStep{text: " ", next: $at + 2};
    }
    if ($ch == "*") {
        # A fill repeats to the column width. There is no column here, so it
        # contributes nothing rather than guessing.
        return LiteralStep{text: "", next: $at + 2};
    }
    return LiteralStep{text: $ch, next: $at + 1};
}

/**
 * Render a number through a plain numeric section.
 *
 * @param amount {float} the number, already scaled
 * @param section {string} the section
 * @param shape {NumShape} the section's shape
 * @param locale {Locale} the locale whose separators the output uses
 * @return {string} the rendering
 */
func emitPlain(amount as float, section as string, shape as NumShape, locale as Locale) {
    def digits as NumDigits init digitsOf($amount, $shape.fracSlots);
    def whole as string init $digits.whole;
    if ($shape.grouped) {
        $whole = groupedDigits($whole, $locale.grouping);
    }
    if ($whole == "0" and leadingSlotsOptional($section, $shape)) {
        # `#.##` shows .5 rather than 0.5, where `0.##` shows the zero.
        $whole = "";
    }
    def template as NumTemplate init layOutNumber($section, $shape, $locale);
    def filled as list of string init fillTemplate($template, $whole, $digits.decimals);
    def body as string init strings.join($filled, "");
    if ($digits.negative and not isZeroRendering($body)) {
        return "-" + $body;
    }
    return $body;
}

/**
 * Whether the integer placeholders are all optional.
 *
 * @param section {string} the section
 * @param shape {NumShape} the section's shape
 * @return {bool} whether a lone zero should be dropped
 */
func leadingSlotsOptional(section as string, shape as NumShape) {
    if ($shape.intSlots == 0) {
        return true;
    }
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if ($ch == "\"") {
            $i = skipQuoted($chars, $i);
            continue;
        }
        if ($ch == ".") {
            return true;
        }
        if ($ch == "0") {
            return false;
        }
        $i = $i + 1;
    }
    return true;
}

/**
 * Whether a rendering holds no significant digit.
 *
 * A negative number that rounds to nothing must not come out as `-0.00`,
 * which is what both applications avoid.
 *
 * @param body {string} the rendering, without a sign
 * @return {bool} whether every digit in it is a zero
 */
func isZeroRendering(body as string) {
    for (def ch in strings.chars($body)) {
        if ($ch >= "1" and $ch <= "9") {
            return false;
        }
    }
    return true;
}

/**
 * Put the digits into a laid-out section.
 *
 * The integer slots fill right to left so that the least significant digit
 * lands in the rightmost slot and any surplus piles up in the leftmost one;
 * the fraction slots fill left to right for the same reason in reverse.
 *
 * @param template {NumTemplate} the layout
 * @param whole {string} the integer digits, grouped if the section asked
 * @param decimals {string} the fraction digits
 * @return {list of string} the pieces, in order, ready to join
 */
func fillTemplate(template as NumTemplate, whole as string, decimals as string) {
    def out as list of string init [];
    for (def i in 0..len($template.pieces)) {
        $out[] = $template.pieces[$i];
    }
    def left as int init countParts($template, "int");
    def wholeChars as list of string init strings.chars($whole);
    def taken as int init len($wholeChars);
    def seen as int init 0;
    for (def i in 0..len($out)) {
        def at as int init len($out) - 1 - $i;
        if ($template.slots[$at] == "" or $template.parts[$at] != "int") {
            continue;
        }
        $seen = $seen + 1;
        def last as bool init $seen == $left;
        $out[$at] = integerSlotText($template.slots[$at], $wholeChars, $taken, $last);
        if ($last) {
            $taken = 0;
        } elseif ($taken > 0) {
            $taken = $taken - 1;
        }
    }
    def fracChars as list of string init strings.chars($decimals);
    def used as int init 0;
    for (def at in 0..len($out)) {
        if ($template.slots[$at] == "" or $template.parts[$at] != "frac") {
            continue;
        }
        $out[$at] = fractionSlotText($template.slots[$at], $fracChars, $used);
        $used = $used + 1;
    }
    return $out;
}

/**
 * How many slots of a template belong to one part of the number.
 *
 * @param template {NumTemplate} the layout
 * @param part {string} the part, `"int"` or `"frac"`
 * @return {int} the count
 */
func countParts(template as NumTemplate, part as string) {
    def total as int init 0;
    for (def i in 0..len($template.slots)) {
        if ($template.slots[$i] != "" and $template.parts[$i] == $part) {
            $total = $total + 1;
        }
    }
    return $total;
}

/**
 * What one integer slot shows.
 *
 * @param kind {string} the placeholder, `0`, `#` or `?`
 * @param digits {list of string} the integer digits
 * @param taken {int} how many digits are still unplaced
 * @param last {bool} whether this is the leftmost slot
 * @return {string} the text for the slot
 */
func integerSlotText(kind as string, digits as list of string, taken as int, last as bool) {
    if ($taken <= 0) {
        if ($kind == "0") {
            return "0";
        }
        if ($kind == "?") {
            return " ";
        }
        return "";
    }
    if ($last) {
        # Everything left over belongs here, or the high digits would be lost.
        return joinChars($digits, 0, $taken);
    }
    return $digits[$taken - 1];
}

/**
 * What one fraction slot shows.
 *
 * @param kind {string} the placeholder, `0`, `#` or `?`
 * @param digits {list of string} the fraction digits
 * @param used {int} how many have been placed already
 * @return {string} the text for the slot
 */
func fractionSlotText(kind as string, digits as list of string, used as int) {
    if ($used < len($digits)) {
        def digit as string init $digits[$used];
        if ($digit == "0" and $kind == "#" and trailingZeros($digits, $used)) {
            return "";
        }
        return $digit;
    }
    if ($kind == "0") {
        return "0";
    }
    if ($kind == "?") {
        return " ";
    }
    return "";
}

/**
 * Whether every fraction digit from an index on is a zero.
 *
 * `#` drops a trailing zero and keeps one that has a digit after it, so
 * `0.##` shows 1.05 in full and 1.5 without a second place.
 *
 * @param digits {list of string} the fraction digits
 * @param from {int} where to look from
 * @return {bool} whether the rest is all zeros
 */
func trailingZeros(digits as list of string, from as int) {
    for (def i in $from..len($digits)) {
        if ($digits[$i] != "0") {
            return false;
        }
    }
    return true;
}

/**
 * The literal text of a section that holds no digit placeholder.
 *
 * @param section {string} the section
 * @return {string} its literal text
 */
func emitLiterals(section as string) {
    def out as list of string init [];
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    while ($i < len($chars)) {
        def step as LiteralStep init literalAt($chars, $i);
        $out[] = $step.text;
        $i = $step.next;
    }
    return strings.join($out, "");
}

/**
 * Render text through the text section of a format.
 *
 * `@` stands for the text; everything else is literal.
 *
 * @param body {string} the text
 * @param section {string} the text section
 * @return {string} the rendering
 */
func renderTextSection(body as string, section as string) {
    def out as list of string init [];
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    while ($i < len($chars)) {
        if ($chars[$i] == "@") {
            $out[] = $body;
            $i = $i + 1;
            continue;
        }
        def step as LiteralStep init literalAt($chars, $i);
        $out[] = $step.text;
        $i = $step.next;
    }
    return strings.join($out, "");
}

/**
 * Render a number through a scientific section such as `0.00E+00`.
 *
 * @param amount {float} the number, already scaled
 * @param section {string} the section
 * @param shape {NumShape} the section's shape
 * @param locale {Locale} the locale whose separators the output uses
 * @return {string} the rendering
 */
func emitScientific(amount as float, section as string, shape as NumShape, locale as Locale) {
    def size as float init math.abs($amount);
    def exponent as int init 0;
    if ($size != 0.0) {
        $exponent = math.floor(math.log10($size));
    }
    # The mantissa carries as many integer digits as the section asked for,
    # which is how `##0.0E+0` comes out in engineering steps of three.
    def lead as int init $shape.intSlots;
    if ($lead < 1) {
        $lead = 1;
    }
    if ($lead > 1) {
        $exponent = ($exponent // $lead) * $lead;
    }
    def mantissa as float init $amount;
    for (def i in 0..abs($exponent)) {
        if ($exponent > 0) {
            $mantissa = $mantissa / 10.0;
        } else {
            $mantissa = $mantissa * 10.0;
        }
    }
    def head as string init emitPlain(
        $mantissa,
        mantissaPart($section),
        mantissaShape($shape),
        $locale);
    return $head + exponentText($section, $shape, $exponent);
}

/**
 * The absolute value of a whole number.
 *
 * @param n {int} the number
 * @return {int} its magnitude
 */
func abs(n as int) {
    if ($n < 0) {
        return -$n;
    }
    return $n;
}

/**
 * The part of a scientific section before the `E`.
 *
 * @param section {string} the section
 * @return {string} the mantissa's own format
 */
func mantissaPart(section as string) {
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    while ($i < len($chars)) {
        if ($chars[$i] == "\"") {
            $i = skipQuoted($chars, $i);
            continue;
        }
        if (strings.lower($chars[$i]) == "e" and isExponentStart($chars, $i)) {
            return joinChars($chars, 0, $i);
        }
        $i = $i + 1;
    }
    return $section;
}

/**
 * The shape of a scientific section's mantissa.
 *
 * @param shape {NumShape} the whole section's shape
 * @return {NumShape} the same shape with the exponent and scaling dropped
 */
func mantissaShape(shape as NumShape) {
    def out as NumShape init $shape;
    $out.expSlots = 0;
    $out.percents = 0;
    $out.thousands = 0;
    return $out;
}

/**
 * The `E+07` tail of a scientific rendering.
 *
 * @param section {string} the section
 * @param shape {NumShape} the section's shape
 * @param exponent {int} the power of ten
 * @return {string} the tail
 */
func exponentText(section as string, shape as NumShape, exponent as int) {
    def sign as string init "+";
    if ($exponent < 0) {
        $sign = "-";
    } elseif (strings.contains($section, "E-") or strings.contains($section, "e-")) {
        $sign = "";
    }
    def digits as string init convert.toString(abs($exponent));
    while (len($digits) < $shape.expSlots) {
        $digits = "0" + $digits;
    }
    return "E" + $sign + $digits;
}

/**
 * Render a number through a fraction section such as `# ?/?`.
 *
 * @param amount {float} the number, already scaled
 * @param section {string} the section
 * @param shape {NumShape} the section's shape
 * @return {string} the rendering
 */
func emitFraction(amount as float, section as string, shape as NumShape) {
    def halves as list of string init splitOnSlash($section);
    def wholePart as string init wholeOfFraction($halves[0]);
    def hasWhole as bool init $wholePart != "";
    def size as float init math.abs($amount);
    def whole as int init 0;
    if ($hasWhole) {
        $whole = math.floor($size);
        $size = $size - convert.toFloat($whole);
    }
    def fixed as int init fixedDenominator($halves[1]);
    def found as Rational init bestRational($size, $fixed, slotCount($halves[1]));
    if ($hasWhole and $found.numerator == $found.denominator) {
        # The remainder rounded up to a whole one, so it belongs in the
        # whole part rather than showing as `3 3/3`.
        $whole = $whole + 1;
        $found = Rational{numerator: 0, denominator: $found.denominator};
    }
    return fractionText($amount, $whole, $found, $hasWhole, $halves);
}

/**
 * A fraction, in lowest terms unless the denominator was fixed.
 *
 * @field numerator {int} the top
 * @field denominator {int} the bottom
 */
def struct Rational {
    numerator as int,
    denominator as int
};

/**
 * Assemble a fraction rendering.
 *
 * @param amount {float} the original number, for its sign
 * @param whole {int} the whole part
 * @param found {Rational} the fractional part
 * @param hasWhole {bool} whether the section asked for a whole part
 * @param halves {list of string} the section either side of the slash
 * @return {string} the rendering
 */
func fractionText(
    amount as float,
    whole as int,
    found as Rational,
    hasWhole as bool,
    halves as list of string) {
    def sign as string init "";
    if ($amount < 0.0) {
        $sign = "-";
    }
    if ($found.numerator == 0 and $hasWhole) {
        return $sign + convert.toString($whole);
    }
    def body as string init convert.toString($found.numerator) + "/" +
        convert.toString($found.denominator);
    if (not $hasWhole) {
        return $sign + $body;
    }
    if ($whole == 0) {
        return $sign + $body;
    }
    return $sign + convert.toString($whole) + " " + $body;
}

/**
 * Split a fraction section at its slash.
 *
 * @param section {string} the section
 * @return {list of string} the part before the slash and the part after
 */
func splitOnSlash(section as string) {
    def at as int init strings.indexOf($section, "/");
    def out as list of string init [];
    $out[] = strings.substring($section, 0, $at);
    $out[] = strings.substring($section, $at + 1, len($section));
    return $out;
}

/**
 * The whole-number part of a fraction section, if it has one.
 *
 * `# ?/?` has one and `?/?` does not: the difference is a run of
 * placeholders separated from the numerator by a space.
 *
 * @param before {string} the section up to the slash
 * @return {string} the whole part's format, or `""`
 */
func wholeOfFraction(before as string) {
    def chars as list of string init strings.chars($before);
    def gap as int init -1;
    for (def i in 0..len($chars)) {
        if ($chars[$i] == " ") {
            $gap = $i;
        }
    }
    if ($gap < 0) {
        return "";
    }
    return strings.trim(joinChars($chars, 0, $gap));
}

/**
 * A fixed denominator written into the section, such as the 8 of `?/8`.
 *
 * @param after {string} the section past the slash
 * @return {int} the denominator, or 0 when the section asks for a best fit
 */
func fixedDenominator(after as string) {
    def digits as list of string init [];
    for (def ch in strings.chars(strings.trim($after))) {
        if ($ch >= "0" and $ch <= "9") {
            $digits[] = $ch;
        } else {
            return 0;
        }
    }
    if (len($digits) == 0) {
        return 0;
    }
    def out as int init 0;
    try {
        $out = convert.toInt(strings.join($digits, ""));
    } catch (e) {
        return 0;
    }
    return $out;
}

/**
 * How many digit placeholders a run holds.
 *
 * @param part {string} a piece of a format section
 * @return {int} the count
 */
func slotCount(part as string) {
    def total as int init 0;
    for (def ch in strings.chars($part)) {
        if (isSlotChar($ch)) {
            $total = $total + 1;
        }
    }
    return $total;
}

/**
 * The most denominator digits a fraction format can ask for.
 *
 * `10^places` is the search bound, so without this a code of many `?`
 * placeholders overflows an int64 on the way to computing it. Nine digits is
 * a denominator up to 999 999 999, past any fraction a person would read.
 */
def const MAX_FRACTION_DIGITS as int init 9;

/**
 * The closest fraction to a value, within a bound on the denominator.
 *
 * A Stern-Brocot search rather than trying every denominator: the bound is
 * 10^places, which is 999 for `?/???`, too many to walk per cell.
 *
 * @param size {float} the value, between 0 and 1
 * @param fixed {int} a denominator the section insisted on, or 0
 * @param places {int} how many digits the denominator may have
 * @return {Rational} the fraction
 */
func bestRational(size as float, fixed as int, places as int) {
    if ($fixed > 0) {
        return Rational{
            numerator: math.round($size * convert.toFloat($fixed)),
            denominator: $fixed
        };
    }
    def digits as int init $places;
    if ($digits > MAX_FRACTION_DIGITS) {
        $digits = MAX_FRACTION_DIGITS;
    }
    def limit as int init 1;
    for (def i in 0..$digits) {
        $limit = $limit * 10;
    }
    $limit = $limit - 1;
    if ($limit < 1) {
        $limit = 1;
    }
    def lowNum as int init 0;
    def lowDen as int init 1;
    def highNum as int init 1;
    def highDen as int init 1;
    while (true) {
        def midNum as int init $lowNum + $highNum;
        def midDen as int init $lowDen + $highDen;
        if ($midDen > $limit) {
            break;
        }
        if (convert.toFloat($midNum) < $size * convert.toFloat($midDen)) {
            $lowNum = $midNum;
            $lowDen = $midDen;
        } else {
            $highNum = $midNum;
            $highDen = $midDen;
        }
    }
    return closerOf(
        $size,
        Rational{numerator: $lowNum, denominator: $lowDen},
        Rational{numerator: $highNum, denominator: $highDen});
}

/**
 * Whichever of two fractions is nearer a value.
 *
 * @param size {float} the value
 * @param low {Rational} the lower bound
 * @param high {Rational} the upper bound
 * @return {Rational} the nearer one
 */
func closerOf(size as float, low as Rational, high as Rational) {
    def lowGap as float init math.abs($size -
        convert.toFloat($low.numerator) / convert.toFloat($low.denominator));
    def highGap as float init math.abs($size -
        convert.toFloat($high.numerator) / convert.toFloat($high.denominator));
    if ($lowGap <= $highGap) {
        return $low;
    }
    return $high;
}

/**
 * Whether a section is a date or time format rather than a numeric one.
 *
 * @param section {string} the section, with modifiers already removed
 * @return {bool} whether it should be rendered as a date
 */
func isDateSection(section as string) {
    if (looksLikeDateFormat($section)) {
        return true;
    }
    # `looksLikeDateFormat` skips what brackets hold, so a section that is
    # nothing but an elapsed token - `[h]` on its own - would read as a
    # numeric one and render as its own text.
    return hasElapsedToken($section);
}

/**
 * Whether a section carries an elapsed-time token.
 *
 * @param section {string} the section
 * @return {bool} whether a `[h]`, `[mm]` or `[ss]` is in it
 */
func hasElapsedToken(section as string) {
    def chars as list of string init strings.chars($section);
    for (def i in 0..len($chars)) {
        if (elapsedAt($chars, $i) != "") {
            return true;
        }
    }
    return false;
}

/**
 * What marks a token as literal text rather than a date field.
 *
 * No date field starts with it, so a literal can never be read as a token.
 */
def const LITERAL_MARK as string init "=";

/**
 * Render a value through a date or time section.
 *
 * @param v {Value} the value, whose instant is used when it has one
 * @param amount {float} the value as a serial, for the elapsed-time tokens
 * @param section {string} the section
 * @param locale {Locale} how to spell the separators and the names
 * @return {string} the rendering
 */
func renderDateSection(v as Value, amount as float, section as string, locale as Locale) {
    def at as time.Time init time.fromIso("1970-01-01T00:00:00Z");
    def ok as bool init true;
    try {
        $at = asTime($v);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return plainNumberIn($amount, $locale);
    }
    def tokens as list of string init dateTokens($section);
    def twelveHour as bool init hasMeridiem($tokens);
    def out as list of string init [];
    for (def i in 0..len($tokens)) {
        $out[] = dateTokenText($tokens, $i, $at, $amount, $twelveHour, $locale);
    }
    return strings.join($out, "");
}

/**
 * Split a date section into tokens.
 *
 * Longest match first, because `mmmm` and `mm` mean different things and a
 * character-at-a-time scan would read the first as two of the second. A
 * literal becomes one token carrying its own text, so the month-or-minute
 * rule can look past it at the real tokens on either side.
 *
 * @param section {string} the section
 * @return {list of string} the tokens, literals prefixed with `LITERAL_MARK`
 */
func dateTokens(section as string) {
    def out as list of string init [];
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    while ($i < len($chars)) {
        def run as string init runOfToken($chars, $i);
        if ($run != "") {
            $out[] = $run;
            $i = $i + len(strings.chars($run));
            continue;
        }
        def bracket as string init elapsedAt($chars, $i);
        if ($bracket != "") {
            $out[] = $bracket;
            $i = $i + len(strings.chars($bracket));
            continue;
        }
        def meridiem as string init meridiemAt($chars, $i);
        if ($meridiem != "") {
            $out[] = $meridiem;
            $i = $i + len(strings.chars($meridiem));
            continue;
        }
        def step as LiteralStep init literalAt($chars, $i);
        $out[] = LITERAL_MARK + $step.text;
        $i = $step.next;
    }
    return $out;
}

/**
 * The run of one repeated date letter at an index.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} where to look
 * @return {string} the run, or `""` when no date letter is there
 */
func runOfToken(chars as list of string, at as int) {
    def first as string init strings.lower($chars[$at]);
    if (not isDateLetter($first)) {
        return "";
    }
    def run as list of string init [];
    def i as int init $at;
    while ($i < len($chars) and strings.lower($chars[$i]) == $first) {
        $run[] = $first;
        $i = $i + 1;
    }
    return strings.join($run, "");
}

/**
 * Whether a character is one of the date field letters.
 *
 * @param lower {string} the character, lowercased
 * @return {bool} whether it names a date field
 */
func isDateLetter(lower as string) {
    return $lower == "y" or $lower == "m" or $lower == "d" or $lower == "h" or
        $lower == "s";
}

/**
 * An elapsed-time token such as `[mm]`, if one sits at an index.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} where to look
 * @return {string} the token with its brackets, or `""`
 */
func elapsedAt(chars as list of string, at as int) {
    if ($chars[$at] != "[") {
        return "";
    }
    def close as int init charIndexFrom($chars, "]", $at);
    if ($close < 0) {
        return "";
    }
    def inside as string init joinChars($chars, $at + 1, $close);
    if (not isElapsedToken($inside)) {
        return "";
    }
    return "[" + $inside + "]";
}

/**
 * An `AM/PM` or `A/P` token, if one sits at an index.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} where to look
 * @return {string} the token as written, or `""`
 */
func meridiemAt(chars as list of string, at as int) {
    for (def candidate in ["AM/PM", "am/pm", "A/P", "a/p"]) {
        if (matchesRun($chars, $at, $candidate)) {
            return $candidate;
        }
    }
    return "";
}

/**
 * Whether a run of characters sits at an index.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} where to look
 * @param probe {string} the run to match
 * @return {bool} whether it is there
 */
func matchesRun(chars as list of string, at as int, probe as string) {
    def wanted as list of string init strings.chars($probe);
    if ($at + len($wanted) > len($chars)) {
        return false;
    }
    for (def i in 0..len($wanted)) {
        if ($chars[$at + $i] != $wanted[$i]) {
            return false;
        }
    }
    return true;
}

/**
 * Whether a token list asks for a 12-hour clock.
 *
 * @param tokens {list of string} the section's tokens
 * @return {bool} whether an AM/PM token is among them
 */
func hasMeridiem(tokens as list of string) {
    for (def token in $tokens) {
        def lower as string init strings.lower($token);
        if ($lower == "am/pm" or $lower == "a/p") {
            return true;
        }
    }
    return false;
}

/**
 * What one date token shows.
 *
 * @param tokens {list of string} the section's tokens
 * @param at {int} which token
 * @param moment {time.Time} the instant
 * @param serial {float} the value as a serial, for elapsed tokens
 * @param twelveHour {bool} whether the section asked for a 12-hour clock
 * @param locale {Locale} the names to spell it with
 * @return {string} the token's text
 */
func dateTokenText(
    tokens as list of string,
    at as int,
    moment as time.Time,
    serial as float,
    twelveHour as bool,
    locale as Locale) {
    def token as string init $tokens[$at];
    if (strings.startsWith($token, LITERAL_MARK)) {
        return strings.substring($token, 1, len($token));
    }
    if (strings.startsWith($token, "[")) {
        return elapsedText($token, $serial);
    }
    def lower as string init strings.lower($token);
    if ($lower == "am/pm" or $lower == "a/p") {
        return meridiemText($token, time.hour($moment));
    }
    if (strings.startsWith($lower, "y")) {
        return yearText($moment, len($token));
    }
    if (strings.startsWith($lower, "d")) {
        return dayText($moment, len($token), $locale);
    }
    if (strings.startsWith($lower, "h")) {
        return hourText($moment, len($token), $twelveHour);
    }
    if (strings.startsWith($lower, "s")) {
        return padded(time.second($moment), len($token));
    }
    if (isMinuteToken($tokens, $at)) {
        return padded(time.minute($moment), len($token));
    }
    return monthText($moment, len($token), $locale);
}

/**
 * Whether an `m` token means minutes rather than months.
 *
 * The rule both applications use: an `m` is minutes when an hour token
 * precedes it or a seconds token follows it, ignoring any literal in
 * between. Without it `hh:mm` would show the month.
 *
 * @param tokens {list of string} the section's tokens
 * @param at {int} which token
 * @return {bool} whether it means minutes
 */
func isMinuteToken(tokens as list of string, at as int) {
    def before as string init neighbourToken($tokens, $at, -1);
    if (strings.startsWith($before, "h") or $before == "[h]") {
        return true;
    }
    def after as string init neighbourToken($tokens, $at, 1);
    return strings.startsWith($after, "s");
}

/**
 * The nearest token in a direction that is not a literal.
 *
 * @param tokens {list of string} the section's tokens
 * @param at {int} where to start
 * @param step {int} which way to walk
 * @return {string} the token, lowercased, or `""`
 */
func neighbourToken(tokens as list of string, at as int, step as int) {
    def i as int init $at + $step;
    while ($i >= 0 and $i < len($tokens)) {
        if (not strings.startsWith($tokens[$i], LITERAL_MARK)) {
            return strings.lower($tokens[$i]);
        }
        $i = $i + $step;
    }
    return "";
}

/**
 * The year, to the width the token asked for.
 *
 * @param at {time.Time} the instant
 * @param width {int} how many letters the token had
 * @return {string} the year
 */
func yearText(at as time.Time, width as int) {
    def year as int init time.year($at);
    if ($width <= 2) {
        return padded($year % 100, 2);
    }
    return convert.toString($year);
}

/**
 * The month, as a number or a name according to the token's width.
 *
 * @param at {time.Time} the instant
 * @param width {int} how many letters the token had
 * @param locale {Locale} the names to spell it with
 * @return {string} the month
 */
func monthText(at as time.Time, width as int, locale as Locale) {
    if ($width < 3) {
        return padded(time.month($at), $width);
    }
    def full as string init localeName($locale.months, time.month($at) - 1);
    if ($full == "") {
        $full = time.format($at, "%B");
    }
    if ($width >= 5) {
        # `mmmmm` is the first letter, which is how a narrow column shows it.
        return strings.substring($full, 0, 1);
    }
    if ($width == 4) {
        return $full;
    }
    def short as string init localeName($locale.monthAbbrevs, time.month($at) - 1);
    if ($short != "") {
        return $short;
    }
    if (len($locale.months) > 0) {
        # The locale gave full names and no short ones, so cut them.
        return strings.substring($full, 0, 3);
    }
    return time.format($at, "%b");
}

/**
 * The day, as a number or a weekday name according to the token's width.
 *
 * @param at {time.Time} the instant
 * @param width {int} how many letters the token had
 * @param locale {Locale} the names to spell it with
 * @return {string} the day
 */
func dayText(at as time.Time, width as int, locale as Locale) {
    if ($width < 3) {
        return padded(time.day($at), $width);
    }
    def full as string init localeName($locale.days, time.weekday($at));
    if ($full == "") {
        $full = time.format($at, "%A");
    }
    if ($width >= 4) {
        return $full;
    }
    def short as string init localeName($locale.dayAbbrevs, time.weekday($at));
    if ($short != "") {
        return $short;
    }
    if (len($locale.days) > 0) {
        return strings.substring($full, 0, 3);
    }
    return time.format($at, "%a");
}

/**
 * The hour, on whichever clock the section asked for.
 *
 * @param at {time.Time} the instant
 * @param width {int} how many letters the token had
 * @param twelveHour {bool} whether an AM/PM token is present
 * @return {string} the hour
 */
func hourText(at as time.Time, width as int, twelveHour as bool) {
    def hour as int init time.hour($at);
    if ($twelveHour) {
        $hour = $hour % 12;
        if ($hour == 0) {
            $hour = 12;
        }
    }
    return padded($hour, $width);
}

/**
 * The AM or PM marker, matching the case the token was written in.
 *
 * @param token {string} the token as written
 * @param hour {int} the hour of the day
 * @return {string} the marker
 */
func meridiemText(token as string, hour as int) {
    def morning as bool init $hour < 12;
    if ($token == "A/P" or $token == "a/p") {
        def short as string init "P";
        if ($morning) {
            $short = "A";
        }
        if ($token == "a/p") {
            return strings.lower($short);
        }
        return $short;
    }
    def long as string init "PM";
    if ($morning) {
        $long = "AM";
    }
    if ($token == "am/pm") {
        return strings.lower($long);
    }
    return $long;
}

/**
 * An elapsed-time token's text.
 *
 * `[h]` is the whole span in hours rather than the hour of a day, which is
 * how a timesheet adds up to more than 24.
 *
 * @param token {string} the token, with its brackets
 * @param serial {float} the value as a serial
 * @return {string} the elapsed count
 */
func elapsedText(token as string, serial as float) {
    def inside as string init strings.substring($token, 1, len($token) - 1);
    def kind as string init strings.lower(strings.substring($inside, 0, 1));
    def width as int init len($inside);
    def seconds as int init math.round(math.abs($serial) * 86400.0);
    if ($kind == "h") {
        return padded($seconds // 3600, $width);
    }
    if ($kind == "m") {
        return padded($seconds // 60, $width);
    }
    return padded($seconds, $width);
}

/**
 * A whole number, zero-padded to a width.
 *
 * @param n {int} the number
 * @param width {int} the least number of digits
 * @return {string} the padded number
 */
func padded(n as int, width as int) {
    def out as string init convert.toString($n);
    while (len($out) < $width) {
        $out = "0" + $out;
    }
    return $out;
}

/**
 * A cell's value as its own style would show it.
 *
 * The format comes from the cell's style. Where `asString` gives `0.075`,
 * this gives `7.5%` if the cell's format is `0.0%`.
 *
 * @param s {Sheet} the sheet
 * @param at {string} the cell, in A1 notation
 * @return {string} the cell as its format shows it
 * @throws {Error} kind "sheets" when the reference is not readable
 * @example
 *   displayAt($s, "B7");
 */
export func displayAt(s as Sheet, at as string) {
    return displayAtRef($s, parseRef($at));
}

/**
 * A cell's value as its own style would show it, spelled a region's way.
 *
 * @param s {Sheet} the sheet
 * @param at {string} the cell, in A1 notation
 * @param locale {Locale} how to spell the separators and the names
 * @return {string} the cell as its format shows it
 * @throws {Error} kind "sheets" when the reference is not readable
 */
export func displayAtIn(s as Sheet, at as string, locale as Locale) {
    def where as Ref init parseRef($at);
    return applyFormatIn(cellAt($s, $where), styleAtRef($s, $where).format, $locale);
}

/**
 * A cell's value as its own style would show it, by position.
 *
 * @param s {Sheet} the sheet
 * @param at {Ref} the cell
 * @return {string} the cell as its format shows it
 */
export func displayAtRef(s as Sheet, at as Ref) {
    return applyFormat(cellAt($s, $at), styleAtRef($s, $at).format);
}

/**
 * One row, every cell as its own format shows it.
 *
 * Use this rather than `displayAt` per cell: reading a cell across the
 * module boundary is 155x more expensive than taking a row, and the format
 * engine does not change that arithmetic.
 *
 * @param s {Sheet} the sheet
 * @param row {int} the zero-based row
 * @return {list of string} the row, as shown
 * @example
 *   displayRow($s, 0);
 */
export func displayRow(s as Sheet, row as int) {
    def out as list of string init [];
    def line as list of Value init row($s, $row);
    for (def c in 0..len($line)) {
        def at as Ref init Ref{row: $row, col: $c};
        $out[] = applyFormat($line[$c], styleAtRef($s, $at).format);
    }
    return $out;
}

/**
 * Every row, every cell as its own format shows it.
 *
 * @param s {Sheet} the sheet
 * @return {list of list of string} the sheet, as shown
 */
export func displayRows(s as Sheet) {
    return displayRowsIn($s, defaultLocale());
}

/**
 * Every row, every cell as shown, spelled a region's way.
 *
 * @param s {Sheet} the sheet
 * @param locale {Locale} how to spell the separators and the names
 * @return {list of list of string} the sheet, as shown
 * @example
 *   displayRowsIn($s, withSeparators(defaultLocale(), ",", "."));
 */
export func displayRowsIn(s as Sheet, locale as Locale) {
    def out as list of list of string init [];
    def lines as list of list of Value init rows($s);
    for (def r in 0..len($lines)) {
        def shown as list of string init [];
        for (def c in 0..len($lines[$r])) {
            def at as Ref init Ref{row: $r, col: $c};
            $shown[] = applyFormatIn($lines[$r][$c], styleAtRef($s, $at).format, $locale);
        }
        $out[] = $shown;
    }
    return $out;
}

/**
 * The format code a built-in number format id stands for.
 *
 * XLSX leaves the first fifty format codes implicit: a cell can say
 * `numFmtId="14"` with no `numFmt` element anywhere in the file, and the
 * application is expected to know that means a short date. Without this
 * table those cells arrive with no format at all, so a file written by Excel
 * loses every format it did not spell out - which is most of them.
 *
 * The ids with no fixed meaning (the gaps, and 5 to 8 which are locale
 * currency formats) return `""`, which reads as the general format.
 *
 * @param id {int} the built-in `numFmtId`
 * @return {string} the format code, or `""` when the id has no fixed meaning
 * @example
 *   builtinFormat(14);   # "mm/dd/yyyy"
 *   builtinFormat(9);    # "0%"
 */
export func builtinFormat(id as int) {
    match ($id) {
        when 1 { return "0"; }
        when 2 { return "0.00"; }
        when 3 { return "#,##0"; }
        when 4 { return "#,##0.00"; }
        when 9 { return "0%"; }
        when 10 { return "0.00%"; }
        when 11 { return "0.00E+00"; }
        when 12 { return "# ?/?"; }
        when 13 { return "# ??/??"; }
        when 14 { return "mm/dd/yyyy"; }
        when 15 { return "d-mmm-yy"; }
        when 16 { return "d-mmm"; }
        when 17 { return "mmm-yy"; }
        when 18 { return "h:mm AM/PM"; }
        when 19 { return "h:mm:ss AM/PM"; }
        when 20 { return "h:mm"; }
        when 21 { return "h:mm:ss"; }
        when 22 { return "m/d/yyyy h:mm"; }
        else { return builtinFormatMore($id); }
    }
}

/**
 * The rest of the built-in format table.
 *
 * Split only because one `match` of fifty arms is past the statement limit.
 *
 * @param id {int} the built-in `numFmtId`
 * @return {string} the format code, or `""` when the id has no fixed meaning
 */
func builtinFormatMore(id as int) {
    match ($id) {
        when 37 { return "#,##0 ;(#,##0)"; }
        when 38 { return "#,##0 ;[Red](#,##0)"; }
        when 39 { return "#,##0.00;(#,##0.00)"; }
        when 40 { return "#,##0.00;[Red](#,##0.00)"; }
        when 45 { return "mm:ss"; }
        when 46 { return "[h]:mm:ss"; }
        when 47 { return "mmss.0"; }
        when 48 { return "##0.0E+0"; }
        when 49 { return "@"; }
        else { return ""; }
    }
}
