# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - number format codes as ODF's tree of components, and back.
#
# This is the one place the three formats disagree about what a
# number format *is*. XLSX and Gnumeric store the code: `#,##0.00` goes in as
# that string and comes back as it. ODF stores a tree instead -
#
#   <number:number-style style:name="N1">
#     <number:number number:decimal-places="2" number:min-integer-digits="1"
#                    number:grouping="true"/>
#   </number:number-style>
#
# - so a code has to be taken apart to write it and put back together to read
# it. Until this file existed the ODS writer wrote only the decimal places,
# which is why `$#,##0.00` came back as `0.00` and `d mmm yyyy` as
# `yyyy-mm-dd`.
#
# The shapes were read off files LibreOffice wrote, not from the ODF
# specification, and three of them are not what the specification alone would
# suggest:
#
#   a code of several sections becomes several styles. The main one carries
#   the *last* section and a `<style:map>` per earlier section pointing at a
#   sub-style, and the sub-styles are marked `style:volatile="true"`;
#   a four-section code's main style is a `number:text-style`, because the
#   fourth section is the text one;
#   `number:percentage-style` and `number:currency-style` are separate
#   element types rather than a plain number style with a literal in it.
#
# The parsing side is numfmt.j's: this file reuses `formatSections`,
# `scanNumShape`, `dateTokens` and the rest rather than reading a code twice
# in two ways.

/**
 * A format code as an ODF number style, with any sub-styles it needs.
 *
 * @param name {string} the style name to give it
 * @param code {string} the number format code
 * @return {string} one or more `number:*-style` elements
 * @example
 *   odfNumberStyle("N1", "#,##0.00");
 */
func odfNumberStyle(name as string, code as string) {
    if (len(strings.trim($code)) > MAX_FORMAT_CODE) {
        # Too long to be a real code. A plain number style keeps the cell's
        # reference to it valid, where returning nothing would leave a
        # `style:data-style-name` pointing at a style that is not there.
        return tagOpenWith("number:number-style", {"style:name": $name}) +
            tagEmpty("number:number", {"number:min-integer-digits": "1"}) +
            tagClose("number:number-style");
    }
    def sections as list of string init formatSections($code);
    if (len($sections) == 1) {
        return odfOneStyle($name, $sections[0], false);
    }
    # Several sections become several styles: the main one takes the last
    # section and maps the earlier ones onto volatile sub-styles.
    def parts as list of string init [];
    def maps as list of string init [];
    def count as int init len($sections);
    if ($count > MAX_FORMAT_SECTIONS) {
        $count = MAX_FORMAT_SECTIONS;
    }
    for (def i in 0..($count - 1)) {
        def subName as string init $name + "P" + convert.toString($i);
        $parts[] = odfOneStyle($subName, $sections[$i], true);
        $maps[] = tagEmpty(
            "style:map",
            {
                "style:condition": odfSectionCondition($sections[$i], $i, len($sections)),
                "style:apply-style-name": $subName
            });
    }
    $parts[] = odfMainStyle($name, $sections[$count - 1], strings.join($maps, ""));
    return strings.join($parts, "");
}

/**
 * The condition a section is selected by.
 *
 * A section may state its own - `[>=1000]` - in which case that is the
 * condition and position means nothing, which is the same rule the renderer
 * follows. Otherwise the position decides.
 *
 * @param section {string} the section, modifiers included
 * @param at {int} which section
 * @param count {int} how many sections the code has
 * @return {string} an ODF condition
 */
func odfSectionCondition(section as string, at as int, count as int) {
    def guard as FormatGuard init guardOf($section);
    if ($guard.has) {
        return "value()" + $guard.op + numberText($guard.value);
    }
    return odfCondition($at, $count);
}

/**
 * The condition that selects one section of a multi-section code.
 *
 * With two sections the first is everything from zero up; with three or four
 * the first is positive, the second negative and the third zero. The fourth
 * is text and is reached by being the main style rather than by a condition.
 *
 * @param at {int} which section
 * @param count {int} how many sections the code has
 * @return {string} an ODF condition
 */
func odfCondition(at as int, count as int) {
    if ($count == 2) {
        return "value()>=0";
    }
    match ($at) {
        when 0 { return "value()>0"; }
        when 1 { return "value()<0"; }
        else { return "value()=0"; }
    }
}

/**
 * The main style of a multi-section code, carrying its maps.
 *
 * @param name {string} the style name
 * @param section {string} the last section of the code
 * @param maps {string} the `style:map` elements
 * @return {string} the style element
 */
func odfMainStyle(name as string, section as string, maps as string) {
    def body as string init odfSectionBody($section);
    def kind as string init odfStyleKind($section);
    return tagOpenWith($kind, odfSectionAttrs($name, false, $section)) +
        $body + $maps + tagClose($kind);
}

/**
 * One section as a complete style element.
 *
 * @param name {string} the style name
 * @param section {string} the section
 * @param volatileStyle {bool} whether it is a sub-style of another
 * @return {string} the style element
 */
func odfOneStyle(name as string, section as string, volatileStyle as bool) {
    def kind as string init odfStyleKind($section);
    return tagOpenWith($kind, odfSectionAttrs($name, $volatileStyle, $section)) +
        odfSectionBody($section) + tagClose($kind);
}

/**
 * The attributes a style element carries.
 *
 * @param name {string} the style name
 * @param volatileStyle {bool} whether it is a sub-style of another
 * @return {map of string to string} the attributes
 */
func odfStyleAttrs(name as string, volatileStyle as bool) {
    def attrs as map of string to string init {"style:name": $name};
    if ($volatileStyle) {
        # A sub-style exists only to be mapped onto, so it is not offered to
        # the user as a format of its own.
        $attrs["style:volatile"] = "true";
    }
    return $attrs;
}

/**
 * The attributes a style element carries, including the elapsed-time flag.
 *
 * ODF says "this is a span rather than a time of day" on the style rather
 * than on the hours element, which is where `[h]` has to end up.
 *
 * @param name {string} the style name
 * @param volatileStyle {bool} whether it is a sub-style of another
 * @param section {string} the section, for the elapsed-time question
 * @return {map of string to string} the attributes
 */
func odfSectionAttrs(name as string, volatileStyle as bool, section as string) {
    def attrs as map of string to string init odfStyleAttrs($name, $volatileStyle);
    if (hasElapsedToken(visibleSection($section))) {
        $attrs["number:truncate-on-overflow"] = "false";
    }
    return $attrs;
}

/**
 * Which `number:*-style` element a section needs.
 *
 * @param section {string} the section
 * @return {string} the element name
 */
func odfStyleKind(section as string) {
    def visible as string init visibleSection($section);
    if (isDateSection($visible)) {
        if (odfHasDatePart($visible)) {
            return "number:date-style";
        }
        return "number:time-style";
    }
    def shape as NumShape init scanNumShape($visible);
    if ($shape.percents > 0) {
        return "number:percentage-style";
    }
    if (not $shape.anySlot and strings.contains($visible, "@")) {
        return "number:text-style";
    }
    return "number:number-style";
}

/**
 * Whether a date section names any part of a date rather than only a time.
 *
 * ODF splits what one format code covers into a date style and a time style,
 * so `hh:mm:ss` is the second kind and `yyyy-mm-dd hh:mm` the first.
 *
 * @param section {string} the section
 * @return {bool} whether a year, month or day token is in it
 */
func odfHasDatePart(section as string) {
    for (def token in dateTokens($section)) {
        if (strings.startsWith($token, LITERAL_MARK)) {
            continue;
        }
        def lower as string init strings.lower($token);
        if (strings.startsWith($lower, "y") or strings.startsWith($lower, "d")) {
            return true;
        }
        if (strings.startsWith($lower, "m") and not odfIsMinuteish($section, $token)) {
            return true;
        }
    }
    return false;
}

/**
 * Whether an `m` token in a section is a minute rather than a month.
 *
 * @param section {string} the section
 * @param token {string} the token
 * @return {bool} whether it means minutes
 */
func odfIsMinuteish(section as string, token as string) {
    def tokens as list of string init dateTokens($section);
    for (def i in 0..len($tokens)) {
        if ($tokens[$i] == $token and isMinuteToken($tokens, $i)) {
            return true;
        }
    }
    return false;
}

/**
 * A section's components, in order.
 *
 * @param section {string} the section
 * @return {string} the child elements of the style
 */
func odfSectionBody(section as string) {
    def visible as string init visibleSection($section);
    def colour as string init odfSectionColour($section);
    if (isDateSection($visible)) {
        return $colour + odfDateBody($visible);
    }
    def shape as NumShape init scanNumShape($visible);
    if (not $shape.anySlot and strings.contains($visible, "@")) {
        return $colour + odfTextBody($visible);
    }
    return $colour + odfNumberBody($visible, $shape);
}

/**
 * The text properties a `[Red]`-style modifier asks for.
 *
 * The only part of a bracketed modifier ODF has somewhere to put. A
 * condition or a locale is dropped, as it is everywhere else in this deck.
 *
 * @param section {string} the section, modifiers included
 * @return {string} a `style:text-properties` element, or `""`
 */
func odfSectionColour(section as string) {
    def rgb as string init "";
    for (def pair in ODF_COLOUR_NAMES) {
        if (strings.contains(strings.lower($section), "[" + $pair[0] + "]")) {
            $rgb = $pair[1];
        }
    }
    if ($rgb == "") {
        return "";
    }
    return tagEmpty("style:text-properties", {"fo:color": "#" + $rgb});
}

/**
 * The colours a format code can name, and what LibreOffice writes for them.
 */
def const ODF_COLOUR_NAMES as list of list of string init [
    ["black", "000000"],
    ["blue", "0000ff"],
    ["cyan", "00ffff"],
    ["green", "008000"],
    ["magenta", "ff00ff"],
    ["red", "ff0000"],
    ["white", "ffffff"],
    ["yellow", "ffff00"]
];

/**
 * A numeric section's components.
 *
 * The literals around the number are `number:text` elements, so `$#,##0.00`
 * is a text element then a number element. A percentage section's `%` is a
 * literal too; ODF puts it in the body and takes the scaling from the
 * element type being a percentage style.
 *
 * @param section {string} the section, with modifiers removed
 * @param shape {NumShape} the section's shape
 * @return {string} the child elements
 */
func odfNumberBody(section as string, shape as NumShape) {
    if (not $shape.anySlot) {
        # Pure literals, such as a section reading `"n/a"`.
        return odfTextRun(emitLiterals($section));
    }
    def parts as list of string init [];
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    def pending as list of string init [];
    def placed as bool init false;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if (isSlotChar($ch) or $ch == "." or $ch == "," or
            (strings.lower($ch) == "e" and isExponentStart($chars, $i))) {
            if (not $placed) {
                $parts[] = odfTextRun(strings.join($pending, ""));
                $pending = [];
                $parts[] = odfNumberElement($section, $shape);
                $placed = true;
            }
            $i = odfSkipSkeleton($chars, $i);
            continue;
        }
        if ($ch == "%") {
            # The scaling is the style's kind; the sign is a literal.
            $pending[] = "%";
            $i = $i + 1;
            continue;
        }
        if ($ch == "/") {
            $i = $i + 1;
            continue;
        }
        def step as LiteralStep init literalAt($chars, $i);
        $pending[] = $step.text;
        $i = $step.next;
    }
    $parts[] = odfTextRun(strings.join($pending, ""));
    return strings.join($parts, "");
}

/**
 * Step over a run of digit skeleton characters.
 *
 * The whole skeleton becomes one element, so once it has been written the
 * rest of it is skipped rather than written again.
 *
 * @param chars {list of string} the section's characters
 * @param at {int} where the skeleton starts
 * @return {int} the index just past it
 */
func odfSkipSkeleton(chars as list of string, at as int) {
    def i as int init $at;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if (isSlotChar($ch) or $ch == "." or $ch == ",") {
            $i = $i + 1;
            continue;
        }
        if (strings.lower($ch) == "e" and isExponentStart($chars, $i)) {
            $i = $i + 2;
            continue;
        }
        if ($ch == "/" or $ch == " ") {
            # A fraction's slash and the space before it belong to the
            # skeleton, not to the literals around it.
            $i = $i + 1;
            continue;
        }
        if ($ch >= "1" and $ch <= "9") {
            # A bare digit in the skeleton is a fixed denominator - the 8 of
            # `?/8` - which the fraction element already carries. Writing it
            # again as a literal put a stray 8 after the fraction.
            $i = $i + 1;
            continue;
        }
        return $i;
    }
    return $i;
}

/**
 * The element that stands for the digits themselves.
 *
 * @param section {string} the section
 * @param shape {NumShape} the section's shape
 * @return {string} a `number:number`, `number:scientific-number` or
 *   `number:fraction` element
 */
func odfNumberElement(section as string, shape as NumShape) {
    if ($shape.fraction) {
        return odfFractionElement($section, $shape);
    }
    def places as string init convert.toString($shape.fracSlots);
    def leastInt as string init convert.toString(odfLeastIntegerDigits($section));
    if ($shape.expSlots > 0) {
        return tagEmpty(
            "number:scientific-number",
            {
                "number:decimal-places": $places,
                "number:min-decimal-places": $places,
                "number:min-integer-digits": $leastInt,
                "number:min-exponent-digits": convert.toString($shape.expSlots),
                "number:forced-exponent-sign": odfForcedSign($section)
            });
    }
    def attrs as map of string to string init {
        "number:decimal-places": $places,
        "number:min-decimal-places": convert.toString(odfLeastDecimals($section)),
        "number:min-integer-digits": $leastInt
    };
    if ($shape.grouped) {
        $attrs["number:grouping"] = "true";
    }
    if ($shape.thousands > 0) {
        # A trailing comma scales by a thousand; ODF says so with a factor
        # rather than by writing the comma anywhere.
        $attrs["number:display-factor"] = odfDisplayFactor($shape.thousands);
    }
    return tagEmpty("number:number", $attrs);
}

/**
 * The scaling factor a run of trailing commas asks for.
 *
 * @param commas {int} how many there are
 * @return {string} the divisor, as text
 */
func odfDisplayFactor(commas as int) {
    # Six commas is a factor of 10^18, which is as far as an int64 reaches.
    # A code from a file can carry a hundred of them.
    def steps as int init $commas;
    if ($steps > 6) {
        $steps = 6;
    }
    def factor as int init 1;
    for (def i in 0..$steps) {
        $factor = $factor * 1000;
    }
    return convert.toString($factor);
}

/**
 * Whether a scientific section spells its exponent sign out.
 *
 * `0.00E+00` always shows the sign; `0.00E-00` shows it only when negative.
 *
 * @param section {string} the section
 * @return {string} `"true"` or `"false"`
 */
func odfForcedSign(section as string) {
    if (strings.contains($section, "E+") or strings.contains($section, "e+")) {
        return "true";
    }
    return "false";
}

/**
 * A fraction section's element.
 *
 * @param section {string} the section
 * @param shape {NumShape} the section's shape
 * @return {string} a `number:fraction` element
 */
func odfFractionElement(section as string, shape as NumShape) {
    def halves as list of string init splitOnSlash($section);
    def whole as string init wholeOfFraction($halves[0]);
    def numerator as int init slotCount($halves[0]) - slotCount($whole);
    if ($numerator < 1) {
        $numerator = 1;
    }
    def attrs as map of string to string init {
        "number:min-numerator-digits": convert.toString($numerator),
        "number:min-denominator-digits": convert.toString(odfDenominatorDigits($halves[1]))
    };
    # Whether the attribute is written at all is the difference between
    # `# ?/?` and `?/?`: absent means the value is entirely a fraction, and
    # a 0 means the whole part is optional. That is what LibreOffice writes
    # for each, and writing it unconditionally turned `?/?` into `# ?/?`.
    if ($whole != "") {
        $attrs["number:min-integer-digits"] = convert.toString(odfLeastIntegerDigits($whole));
    }
    def fixed as int init fixedDenominator($halves[1]);
    if ($fixed > 0) {
        $attrs["number:denominator-value"] = convert.toString($fixed);
    } else {
        $attrs["number:max-denominator-value"] = convert.toString(odfLargestDenominator($halves[1]));
    }
    return tagEmpty("number:fraction", $attrs);
}

/**
 * How many digits a fraction's denominator pattern asks for.
 *
 * @param after {string} the section past the slash
 * @return {int} the count, at least 1
 */
func odfDenominatorDigits(after as string) {
    def fixed as int init fixedDenominator($after);
    if ($fixed > 0) {
        return len(convert.toString($fixed));
    }
    def slots as int init slotCount($after);
    if ($slots < 1) {
        return 1;
    }
    if ($slots > MAX_FRACTION_DIGITS) {
        # `10^slots` is the search bound a fraction needs, and a thousand
        # placeholders overflow it. See MAX_FRACTION_DIGITS.
        return MAX_FRACTION_DIGITS;
    }
    return $slots;
}

/**
 * The largest denominator a pattern of placeholders allows.
 *
 * @param after {string} the section past the slash
 * @return {int} the bound, such as 9 for `?` and 99 for `??`
 */
func odfLargestDenominator(after as string) {
    def digits as int init odfDenominatorDigits($after);
    if ($digits > MAX_FRACTION_DIGITS) {
        $digits = MAX_FRACTION_DIGITS;
    }
    def bound as int init 1;
    for (def i in 0..$digits) {
        $bound = $bound * 10;
    }
    return $bound - 1;
}

/**
 * How many integer digits a section insists on.
 *
 * The count of `0` placeholders before the point: `000` insists on three
 * and `#,##0` on one.
 *
 * @param section {string} the section
 * @return {int} the count
 */
func odfLeastIntegerDigits(section as string) {
    def total as int init 0;
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    while ($i < len($chars)) {
        def ch as string init $chars[$i];
        if ($ch == "\"") {
            $i = skipQuoted($chars, $i);
            continue;
        }
        if ($ch == ".") {
            return $total;
        }
        if ($ch == "0") {
            $total = $total + 1;
        }
        $i = $i + 1;
    }
    return $total;
}

/**
 * How many decimal places a section insists on.
 *
 * The count of `0` placeholders after the point, where `#` and `?` are
 * optional: `0.0##` insists on one and allows three.
 *
 * @param section {string} the section
 * @return {int} the count
 */
func odfLeastDecimals(section as string) {
    def dot as int init strings.indexOf($section, ".");
    if ($dot < 0) {
        return 0;
    }
    def total as int init 0;
    for (def ch in strings.chars(strings.substring($section, $dot + 1, len($section)))) {
        if ($ch == "0") {
            $total = $total + 1;
        } elseif (not isSlotChar($ch)) {
            return $total;
        }
    }
    return $total;
}

/**
 * A text section's components.
 *
 * @param section {string} the section
 * @return {string} the child elements
 */
func odfTextBody(section as string) {
    def parts as list of string init [];
    def chars as list of string init strings.chars($section);
    def i as int init 0;
    def pending as list of string init [];
    while ($i < len($chars)) {
        if ($chars[$i] == "@") {
            $parts[] = odfTextRun(strings.join($pending, ""));
            $pending = [];
            $parts[] = tagEmpty("number:text-content", {});
            $i = $i + 1;
            continue;
        }
        def step as LiteralStep init literalAt($chars, $i);
        $pending[] = $step.text;
        $i = $step.next;
    }
    $parts[] = odfTextRun(strings.join($pending, ""));
    return strings.join($parts, "");
}

/**
 * A run of literal text as a `number:text` element.
 *
 * @param body {string} the text
 * @return {string} the element, or `""` when there is nothing to write
 */
func odfTextRun(body as string) {
    if ($body == "") {
        return "";
    }
    return tagText("number:text", $body);
}

/**
 * A date or time section's components.
 *
 * One element per token, with the separators between them as `number:text`.
 * The month-or-minute question is settled before this is called, by the same
 * `isMinuteToken` rule the renderer uses - ODF has separate elements for the
 * two, so getting it wrong here shows up as a month where a minute belongs.
 *
 * @param section {string} the section, with modifiers removed
 * @return {string} the child elements
 */
func odfDateBody(section as string) {
    def tokens as list of string init dateTokens($section);
    def parts as list of string init [];
    def pending as list of string init [];
    for (def i in 0..len($tokens)) {
        def token as string init $tokens[$i];
        if (strings.startsWith($token, LITERAL_MARK)) {
            $pending[] = strings.substring($token, 1, len($token));
            continue;
        }
        def element as string init odfDateElement($tokens, $i);
        if ($element == "") {
            continue;
        }
        $parts[] = odfTextRun(strings.join($pending, ""));
        $pending = [];
        $parts[] = $element;
    }
    $parts[] = odfTextRun(strings.join($pending, ""));
    return strings.join($parts, "");
}

/**
 * One date token as its ODF element.
 *
 * @param tokens {list of string} the section's tokens
 * @param at {int} which token
 * @return {string} the element, or `""` when ODF has none for it
 */
func odfDateElement(tokens as list of string, at as int) {
    def token as string init $tokens[$at];
    def lower as string init strings.lower($token);
    def width as int init len($token);
    if ($lower == "am/pm" or $lower == "a/p") {
        return tagEmpty("number:am-pm", {});
    }
    if (strings.startsWith($token, "[")) {
        # An elapsed-time token. ODF says so with `number:truncate-on-overflow`
        # on the style rather than on the element, so the element is the plain
        # one and the attribute is added by `odfDateStyleAttrs`.
        return odfClockElement(strings.lower(strings.substring($token, 1, 2)), len($token) - 2);
    }
    if (strings.startsWith($lower, "y")) {
        return odfDatePart("number:year", $width >= 3);
    }
    if (strings.startsWith($lower, "d")) {
        if ($width >= 3) {
            return odfDatePart("number:day-of-week", $width >= 4);
        }
        return odfDatePart("number:day", $width >= 2);
    }
    if (strings.startsWith($lower, "h") or strings.startsWith($lower, "s")) {
        return odfClockElement($lower, $width);
    }
    if (isMinuteToken($tokens, $at)) {
        return odfDatePart("number:minutes", $width >= 2);
    }
    return odfMonthElement($width);
}

/**
 * The hours, minutes or seconds element for a clock token.
 *
 * @param letter {string} the token's letter
 * @param width {int} how many of it there were
 * @return {string} the element
 */
func odfClockElement(letter as string, width as int) {
    if (strings.startsWith($letter, "h")) {
        return odfDatePart("number:hours", $width >= 2);
    }
    if (strings.startsWith($letter, "s")) {
        return odfDatePart("number:seconds", $width >= 2);
    }
    return odfDatePart("number:minutes", $width >= 2);
}

/**
 * The month element for a token of a given width.
 *
 * Three letters is the abbreviated name, four the full one, and five the
 * initial - which ODF cannot say, so it writes the abbreviation.
 *
 * @param width {int} how many letters the token had
 * @return {string} the element
 */
func odfMonthElement(width as int) {
    if ($width >= 3) {
        def attrs as map of string to string init {"number:textual": "true"};
        if ($width >= 4) {
            $attrs["number:style"] = "long";
        }
        return tagEmpty("number:month", $attrs);
    }
    return odfDatePart("number:month", $width >= 2);
}

/**
 * One date component, padded or not.
 *
 * ODF spells "two digits" as `number:style="long"` and one digit as the
 * attribute being absent.
 *
 * @param element {string} the element name
 * @param padded {bool} whether the token asked for a padded form
 * @return {string} the element
 */
func odfDatePart(element as string, padded as bool) {
    if ($padded) {
        return tagEmpty($element, {"number:style": "long"});
    }
    return tagEmpty($element, {});
}

/**
 * An ODF number style as a format code.
 *
 * The other direction: walk the components in order and spell out what each
 * one asks for. A style with `style:map` children is several sections, and
 * the maps name the sub-styles holding the rest.
 *
 * @param src {bytes} the part the style is in
 * @param styleNode {Node} the `number:*-style` element
 * @param byName {map of string to Node} every style in the part, by name
 * @return {string} the format code
 */
func odfFormatCode(src as bytes, styleNode as Node, byName as map of string to Node) {
    def tail as string init odfSectionCode($src, $styleNode);
    def maps as list of string init odfMapTargets($src, $styleNode);
    if (len($maps) == 0) {
        return $tail;
    }
    # The main style carries the *last* section and maps the earlier ones, so
    # the code is the mapped sections in order and then this one.
    def parts as list of string init [];
    def conditions as list of string init odfMapConditions($src, $styleNode);
    for (def i in 0..len($maps)) {
        def guard as string init odfGuardOf($conditions, $i, len($maps) + 1);
        if (maps.has($byName, $maps[$i])) {
            $parts[] = $guard + odfSectionCode($src, $byName[$maps[$i]]);
        } else {
            $parts[] = $guard;
        }
    }
    $parts[] = $tail;
    return strings.join($parts, ";");
}

/**
 * The `[>=1000]`-style guard a map's condition stands for, if any.
 *
 * Only a condition the positions could not have implied is written back: a
 * two-section code's `value()>=0` is what the first position means anyway,
 * and spelling it out would turn `0.00;(0.00)` into `[>=0]0.00;(0.00)`.
 *
 * @param conditions {list of string} the conditions the maps state
 * @param at {int} which map
 * @param count {int} how many sections the code has
 * @return {string} the guard in brackets, or `""`
 */
func odfGuardOf(conditions as list of string, at as int, count as int) {
    if ($at >= len($conditions)) {
        return "";
    }
    def raw as string init $conditions[$at];
    if ($raw == odfCondition($at, $count)) {
        return "";
    }
    if (not strings.startsWith($raw, "value()")) {
        return "";
    }
    return "[" + strings.substring($raw, 7, len($raw)) + "]";
}

/**
 * The conditions a style's maps state, in order.
 *
 * @param src {bytes} the part the style is in
 * @param styleNode {Node} the style element
 * @return {list of string} the conditions
 */
func odfMapConditions(src as bytes, styleNode as Node) {
    def out as list of string init [];
    def child as Node init nextChild($src, $styleNode.openEnd, $styleNode.innerEnd);
    while (isNode($child) and len($out) < MAX_FORMAT_SECTIONS) {
        if (localName($child.name) == "map") {
            $out[] = strings.trim(nodeAttr($src, $child, "condition"));
        }
        $child = nextChild($src, $child.end, $styleNode.innerEnd);
    }
    return $out;
}

/**
 * The sub-styles a style maps onto, in the order the maps appear.
 *
 * @param src {bytes} the part the style is in
 * @param styleNode {Node} the style element
 * @return {list of string} the style names
 */
func odfMapTargets(src as bytes, styleNode as Node) {
    def out as list of string init [];
    def child as Node init nextChild($src, $styleNode.openEnd, $styleNode.innerEnd);
    while (isNode($child) and len($out) < MAX_FORMAT_SECTIONS) {
        if (localName($child.name) == "map") {
            def target as string init nodeAttr($src, $child, "apply-style-name");
            if ($target != "") {
                $out[] = $target;
            }
        }
        $child = nextChild($src, $child.end, $styleNode.innerEnd);
    }
    return $out;
}

/**
 * How many sections of a format code this deck will read.
 *
 * A format code has at most four - positive, negative, zero and text - so a
 * style carrying more maps than that is not describing a format. The cap is
 * here because each map means parsing another style: a document with 5 000
 * of them on one style took 2.7 s to read, for a format no application
 * would write.
 */
def const MAX_FORMAT_SECTIONS as int init 8;

/**
 * One style's components as a single section of a format code.
 *
 * @param src {bytes} the part the style is in
 * @param styleNode {Node} the style element
 * @return {string} the section
 */
func odfSectionCode(src as bytes, styleNode as Node) {
    def parts as list of string init [];
    def child as Node init nextChild($src, $styleNode.openEnd, $styleNode.innerEnd);
    while (isNode($child)) {
        $parts[] = odfComponentCode($src, $child);
        $child = nextChild($src, $child.end, $styleNode.innerEnd);
    }
    return strings.join($parts, "");
}

/**
 * One component element as its part of a format code.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the component element
 * @return {string} the code fragment, `""` for a component with no spelling
 */
func odfComponentCode(src as bytes, node as Node) {
    match (localName($node.name)) {
        when "text" { return odfQuotedLiteral(odfLiteralText($src, $node)); }
        when "text-content" { return "@"; }
        when "number" { return odfNumberCodeOf($src, $node); }
        when "scientific-number" { return odfScientificCodeOf($src, $node); }
        when "fraction" { return odfFractionCodeOf($src, $node); }
        when "year" { return odfRepeated($src, $node, "yyyy", "yy"); }
        when "month" { return odfMonthCodeOf($src, $node); }
        when "day" { return odfRepeated($src, $node, "dd", "d"); }
        when "day-of-week" { return odfRepeated($src, $node, "dddd", "ddd"); }
        when "hours" { return odfRepeated($src, $node, "hh", "h"); }
        when "minutes" { return odfRepeated($src, $node, "mm", "m"); }
        when "seconds" { return odfRepeated($src, $node, "ss", "s"); }
        when "am-pm" { return "AM/PM"; }
        else { return ""; }
    }
}

/**
 * A `number:text` element's content, whitespace and all.
 *
 * `nodeText` trims, which is right for every other reader in this deck -
 * element content is usually surrounded by insignificant whitespace - and
 * wrong here, where the whitespace *is* the content. Trimming it turned
 * `d mmm yyyy` into `dmmmyyyy`.
 *
 * @param src {bytes} the part the element is in
 * @param node {Node} the `number:text` element
 * @return {string} the text exactly as written, entities resolved
 */
func odfLiteralText(src as bytes, node as Node) {
    return xmlUnescape(byteText($src, $node.openEnd, $node.innerEnd));
}

/**
 * A literal run, quoted when a format code would otherwise read it as a token.
 *
 * @param body {string} the literal text
 * @return {string} the fragment
 */
func odfQuotedLiteral(body as string) {
    if ($body == "") {
        return "";
    }
    if (odfLiteralIsSafe($body)) {
        return $body;
    }
    return "\"" + $body + "\"";
}

/**
 * Whether a literal can go into a code without quotes.
 *
 * The punctuation a format code always reads as itself. A letter cannot:
 * an unquoted `d` would become the day of the month.
 *
 * @param body {string} the literal text
 * @return {bool} whether it is safe bare
 */
func odfLiteralIsSafe(body as string) {
    for (def ch in strings.chars($body)) {
        if (strings.indexOf(ODF_BARE_LITERALS, $ch) < 0) {
            return false;
        }
    }
    return true;
}

/**
 * The characters a format code reads as themselves.
 */
def const ODF_BARE_LITERALS as string init " $-+/():.,%";

/**
 * A `number:number` element as its part of a code.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the element
 * @return {string} the fragment
 */
func odfNumberCodeOf(src as bytes, node as Node) {
    def least as int init odfCountAttr($src, $node, "min-integer-digits", 1);
    def places as int init odfCountAttr($src, $node, "decimal-places", 0);
    def leastPlaces as int init odfCountAttr($src, $node, "min-decimal-places", $places);
    def grouped as bool init nodeAttr($src, $node, "grouping") == "true";
    def body as string init odfIntegerPattern($least, $grouped) +
        odfDecimalPattern($places, $leastPlaces);
    return $body + odfFactorCommas($src, $node);
}

/**
 * The integer half of a numeric pattern.
 *
 * @param least {int} how many digits are insisted on
 * @param grouped {bool} whether to ask for thousands separators
 * @return {string} the pattern
 */
func odfIntegerPattern(least as int, grouped as bool) {
    def zeros as int init $least;
    if ($zeros < 1) {
        $zeros = 1;
    }
    def body as string init strings.repeat("0", $zeros);
    if (not $grouped) {
        return $body;
    }
    # `#,##0` is how a code asks for grouping, and the three optional places
    # in front of the comma are part of that spelling.
    if ($zeros >= 4) {
        return $body;
    }
    return "#,##" + strings.repeat("0", $zeros);
}

/**
 * The decimal half of a numeric pattern.
 *
 * @param places {int} how many places are allowed
 * @param least {int} how many are insisted on
 * @return {string} the pattern, `""` when there are none
 */
func odfDecimalPattern(places as int, least as int) {
    if ($places <= 0) {
        return "";
    }
    def insisted as int init $least;
    if ($insisted > $places) {
        $insisted = $places;
    }
    return "." + strings.repeat("0", $insisted) +
        strings.repeat("#", $places - $insisted);
}

/**
 * The trailing commas a display factor stands for.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the element
 * @return {string} the commas
 */
func odfFactorCommas(src as bytes, node as Node) {
    def factor as int init odfCountAttr($src, $node, "display-factor", 1);
    def commas as int init 0;
    while ($factor >= 1000 and $commas < 8) {
        $factor = $factor // 1000;
        $commas = $commas + 1;
    }
    return strings.repeat(",", $commas);
}

/**
 * A `number:scientific-number` element as its part of a code.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the element
 * @return {string} the fragment
 */
func odfScientificCodeOf(src as bytes, node as Node) {
    def least as int init odfCountAttr($src, $node, "min-integer-digits", 1);
    def places as int init odfCountAttr($src, $node, "decimal-places", 0);
    def exponent as int init odfCountAttr($src, $node, "min-exponent-digits", 2);
    def sign as string init "+";
    if (nodeAttr($src, $node, "forced-exponent-sign") == "false") {
        $sign = "-";
    }
    return odfIntegerPattern($least, false) +
        odfDecimalPattern($places, $places) + "E" + $sign +
        strings.repeat("0", $exponent);
}

/**
 * A `number:fraction` element as its part of a code.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the element
 * @return {string} the fragment
 */
func odfFractionCodeOf(src as bytes, node as Node) {
    def numerator as int init odfCountAttr($src, $node, "min-numerator-digits", 1);
    def head as string init "";
    # Whether the attribute is there at all is the difference between
    # `# ?/?` and `?/?`: absent means the value is entirely a fraction, and
    # present-and-zero means the whole part is optional. Checked against
    # what LibreOffice writes for each.
    if (strings.trim(nodeAttr($src, $node, "min-integer-digits")) != "") {
        def whole as int init odfCountAttr($src, $node, "min-integer-digits", 0);
        $head = "# ";
        if ($whole > 0) {
            $head = strings.repeat("0", $whole) + " ";
        }
    }
    def fixed as int init odfCountAttr($src, $node, "denominator-value", 0);
    if ($fixed > 0) {
        return $head + strings.repeat("?", $numerator) + "/" +
            convert.toString($fixed);
    }
    def digits as int init odfCountAttr($src, $node, "min-denominator-digits", 1);
    return $head + strings.repeat("?", $numerator) + "/" +
        strings.repeat("?", $digits);
}

/**
 * A `number:month` element as its part of a code.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the element
 * @return {string} the fragment
 */
func odfMonthCodeOf(src as bytes, node as Node) {
    def long as bool init nodeAttr($src, $node, "style") == "long";
    if (nodeAttr($src, $node, "textual") == "true") {
        if ($long) {
            return "mmmm";
        }
        return "mmm";
    }
    if ($long) {
        return "mm";
    }
    return "m";
}

/**
 * A component that is padded or not, as its token.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the element
 * @param padded {string} the token for the padded form
 * @param plain {string} the token for the plain one
 * @return {string} the fragment
 */
func odfRepeated(src as bytes, node as Node, padded as string, plain as string) {
    if (nodeAttr($src, $node, "style") == "long") {
        return $padded;
    }
    return $plain;
}

/**
 * One of a style element's counting attributes.
 *
 * @param src {bytes} the part the style is in
 * @param node {Node} the element
 * @param name {string} the attribute
 * @param fallback {int} what an absent or unreadable attribute means
 * @return {int} the count
 */
func odfCountAttr(src as bytes, node as Node, name as string, fallback as int) {
    def raw as string init strings.trim(nodeAttr($src, $node, $name));
    if ($raw == "") {
        return $fallback;
    }
    def out as int init 0;
    try {
        $out = convert.toInt($raw);
    } catch (e) {
        return $fallback;
    }
    if ($out < 0) {
        return $fallback;
    }
    return $out;
}
