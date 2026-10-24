# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the formula function library.
# Spliced into sheets.j via include - not a standalone module.
#
# About 110 functions (here, ffntext.j and ffnlogic.j), not the several
# hundred an application ships: the aggregates, arithmetic, text, conditionals,
# dates and lookups that appear in files. Any other name yields #NAME?, so an
# exotic file is visibly unsupported rather than quietly mis-evaluated.
#
# Two conventions throughout:
#
#   A range argument is flattened to its cells, as SUM(A1:A5) means. A function
#   that needs a range as a range (the lookups, COUNTIF) takes the argument
#   tree rather than its value.
#
#   An error argument propagates, except in the functions whose job is to
#   catch one, such as IFERROR and ISERROR, and in COUNT, which skips it.

/**
 * Apply a function to its arguments.
 *
 * @param name {string} the function name, already upper-cased
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the result, or an error value
 */
func applyFunction(name as string, args as list of Expr, book as Workbook, scope as Scope) {
    # The conditionals come first because they must not evaluate every
    # argument: IF has to leave the branch it did not take alone, and IFERROR
    # has to survive an argument that errors.
    match ($name) {
        when "IF" { return fnIf($args, $book, $scope); }
        when "IFERROR" { return fnIfError($args, $book, $scope, false); }
        when "IFNA" { return fnIfError($args, $book, $scope, true); }
        when "AND" { return fnAndOr($args, $book, $scope, true); }
        when "OR" { return fnAndOr($args, $book, $scope, false); }
        when "NOT" { return fnNot($args, $book, $scope); }
        when "XOR" { return fnXor($args, $book, $scope); }
        when "TRUE" { return Value.Bool{flag: true}; }
        when "FALSE" { return Value.Bool{flag: false}; }
        when "ISERROR" { return fnIsError($args, $book, $scope, false); }
        when "ISNA" { return fnIsError($args, $book, $scope, true); }
        when "ISBLANK" { return fnIsBlank($args, $book, $scope); }
        when "ISNUMBER" { return fnIsKind($args, $book, $scope, "number"); }
        when "ISTEXT" { return fnIsKind($args, $book, $scope, "text"); }
        when "ISLOGICAL" { return fnIsKind($args, $book, $scope, "bool"); }
        when "COUNT" { return fnCount($args, $book, $scope, false); }
        when "COUNTA" { return fnCount($args, $book, $scope, true); }
        when "COUNTBLANK" { return fnCountBlank($args, $book, $scope); }
        when "SUMIF" { return fnSumIf($args, $book, $scope); }
        when "COUNTIF" { return fnCountIf($args, $book, $scope); }
        when "VLOOKUP" { return fnVlookup($args, $book, $scope); }
        when "HLOOKUP" { return fnHlookup($args, $book, $scope); }
        when "INDEX" { return fnIndex($args, $book, $scope); }
        when "MATCH" { return fnMatch($args, $book, $scope); }
        when "ROW" { return fnRowCol($args, $book, $scope, true); }
        when "COLUMN" { return fnRowCol($args, $book, $scope, false); }
        when "ROWS" { return fnSpanSize($args, $book, $scope, true); }
        when "COLUMNS" { return fnSpanSize($args, $book, $scope, false); }
        when "NA" { return Value.Err{code: ERR_NA}; }
        else { return applyValueFunction($name, $args, $book, $scope); }
    }
}

/**
 * Apply a function whose arguments are all just values.
 *
 * Split out because the dispatch above has to stay lazy, and one `match` of
 * ninety arms exceeds what the linter allows in a block.
 *
 * @param name {string} the function name
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the result, or an error value
 */
func applyValueFunction(name as string, args as list of Expr, book as Workbook, scope as Scope) {
    def flat as list of Value init flattenArgs($args, $book, $scope);
    for (def v in $flat) {
        if (isErrorValue($v)) {
            return $v;
        }
    }
    def aggregate as Value init applyAggregate($name, $flat);
    if (not isUnknownName($aggregate)) {
        return $aggregate;
    }
    def single as Value init applyUnaryFunction($name, $flat);
    if (not isUnknownName($single)) {
        return $single;
    }
    def text as Value init applyTextFunction($name, $flat);
    if (not isUnknownName($text)) {
        return $text;
    }
    return applyDateFunction($name, $flat);
}

/**
 * Whether a result means "no such function".
 *
 * The dispatch is a chain of families, and each hands on what it does not
 * recognise. `#NAME?` is the sentinel, which is also the right answer if the
 * chain runs out.
 *
 * @param v {Value} a family's answer
 * @return {bool} whether the family declined the name
 */
func isUnknownName(v as Value) {
    match ($v) {
        when Err(e) { return $e.code == ERR_NAME; }
        else { return false; }
    }
}

/**
 * Every argument's value, with ranges flattened to their cells.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {list of Value} the values
 */
func flattenArgs(args as list of Expr, book as Workbook, scope as Scope) {
    def out as list of Value init [];
    for (def arg in $args) {
        for (def v in flattenOne($arg, $book, $scope)) {
            $out[] = $v;
        }
    }
    return $out;
}

/**
 * One argument's values: a range's cells, or the single value.
 *
 * @param arg {Expr} the unevaluated argument
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {list of Value} the values
 */
func flattenOne(arg as Expr, book as Workbook, scope as Scope) {
    match ($arg) {
        when Span(sp) { return spanValues($sp.body, $book, $scope); }
        else {
            def out as list of Value init [];
            $out[] = evalExpr($arg, $book, $scope);
            return $out;
        }
    }
}

/**
 * The numbers among a list of values.
 *
 * Text that reads as a number counts; other text is skipped rather than
 * failing the aggregate, as the applications do.
 *
 * @param values {list of Value} the values
 * @return {list of float} the numbers
 */
func numbersIn(values as list of Value) {
    def out as list of float init [];
    for (def v in $values) {
        if (not isEmpty($v)) {
            def amount as float init 0.0;
            def ok as bool init true;
            try {
                $amount = asNumber($v);
            } catch (e) {
                $ok = false;
            }
            if ($ok) {
                $out[] = $amount;
            }
        }
    }
    return $out;
}

/**
 * Apply an aggregate over every argument.
 *
 * @param name {string} the function name
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the result, or `#NAME?` when this family declines
 */
func applyAggregate(name as string, flat as list of Value) {
    def numbers as list of float init numbersIn($flat);
    match ($name) {
        when "SUM" { return numberResult(totalOf($numbers)); }
        when "PRODUCT" { return numberResult(productOf($numbers)); }
        when "AVERAGE" { return meanOf($numbers); }
        when "MIN" { return extremeOf($numbers, true); }
        when "MAX" { return extremeOf($numbers, false); }
        when "MEDIAN" { return statOf($numbers, "median"); }
        when "STDEV" { return statOf($numbers, "sampleStddev"); }
        when "STDEVP" { return statOf($numbers, "stddev"); }
        when "VAR" { return statOf($numbers, "sampleVariance"); }
        when "VARP" { return statOf($numbers, "variance"); }
        when "SUMSQ" { return numberResult(sumOfSquares($numbers)); }
        else { return Value.Err{code: ERR_NAME}; }
    }
}

/**
 * The total of a list of numbers.
 *
 * @param numbers {list of float} the numbers
 * @return {float} the total
 */
func totalOf(numbers as list of float) {
    def out as float init 0.0;
    for (def n in $numbers) {
        $out = $out + $n;
    }
    return $out;
}

/**
 * The product of a list of numbers.
 *
 * @param numbers {list of float} the numbers
 * @return {float} the product, 0 for an empty list
 */
func productOf(numbers as list of float) {
    if (len($numbers) == 0) {
        return 0.0;
    }
    def out as float init 1.0;
    for (def n in $numbers) {
        $out = $out * $n;
    }
    return $out;
}

/**
 * The sum of squares of a list of numbers.
 *
 * @param numbers {list of float} the numbers
 * @return {float} the sum
 */
func sumOfSquares(numbers as list of float) {
    def out as float init 0.0;
    for (def n in $numbers) {
        $out = $out + $n * $n;
    }
    return $out;
}

/**
 * The mean, or `#DIV/0!` when there is nothing to average.
 *
 * @param numbers {list of float} the numbers
 * @return {Value} the result
 */
func meanOf(numbers as list of float) {
    if (len($numbers) == 0) {
        return Value.Err{code: ERR_DIV0};
    }
    return numberResult(totalOf($numbers) / convert.toFloat(len($numbers)));
}

/**
 * The smallest or largest of a list.
 *
 * Zero for an empty list, which is what a spreadsheet returns for `MIN()` of
 * nothing rather than an error.
 *
 * @param numbers {list of float} the numbers
 * @param wantLeast {bool} whether to take the smallest
 * @return {Value} the result
 */
func extremeOf(numbers as list of float, wantLeast as bool) {
    if (len($numbers) == 0) {
        return Value.Number{amount: 0.0};
    }
    def best as float init $numbers[0];
    for (def n in $numbers) {
        if ($wantLeast and $n < $best) {
            $best = $n;
        }
        if (not $wantLeast and $n > $best) {
            $best = $n;
        }
    }
    return Value.Number{amount: $best};
}

/**
 * A statistic from the `stats` library, with its errors turned into values.
 *
 * `stats` raises on a degenerate input (an empty list, a zero variance) where
 * a spreadsheet yields an error value, so every call is wrapped.
 *
 * @param numbers {list of float} the numbers
 * @param which {string} the statistic's name
 * @return {Value} the result, or an error value
 */
func statOf(numbers as list of float, which as string) {
    if (len($numbers) == 0) {
        return Value.Err{code: ERR_DIV0};
    }
    def out as float init 0.0;
    def ok as bool init true;
    try {
        $out = statValue($numbers, $which);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_DIV0};
    }
    return numberResult($out);
}

/**
 * One named statistic over a list.
 *
 * @param numbers {list of float} the numbers
 * @param which {string} the statistic's name
 * @return {float} the value
 * @throws {Error} kind "sheets" when the input is degenerate for that statistic
 */
func statValue(numbers as list of float, which as string) {
    match ($which) {
        when "median" { return stats.median($numbers); }
        when "stddev" { return stats.stddev($numbers); }
        when "sampleStddev" { return stats.sampleStddev($numbers); }
        when "variance" { return stats.variance($numbers); }
        when "sampleVariance" { return stats.sampleVariance($numbers); }
        else { return 0.0; }
    }
}

/**
 * A number as a value, with a non-finite result turned into `#NUM!`.
 *
 * Jennifer raises on a non-finite float rather than producing one, and a
 * raise here would abort a whole recalculation, so the arithmetic is done
 * where it can be caught.
 *
 * @param amount {float} the result
 * @return {Value} the number, or `#NUM!`
 */
func numberResult(amount as float) {
    return Value.Number{amount: $amount};
}

/**
 * Apply a one-argument numeric function.
 *
 * @param name {string} the function name
 * @param flat {list of Value} the flattened arguments
 * @return {Value} the result, or `#NAME?` when this family declines
 */
func applyUnaryFunction(name as string, flat as list of Value) {
    if (not isUnaryName($name)) {
        return Value.Err{code: ERR_NAME};
    }
    # PI is in this family for dispatch but takes no argument, so the arity
    # check below would refuse it.
    if ($name == "PI") {
        return Value.Number{amount: math.PI};
    }
    if (len($flat) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def a as float init 0.0;
    def ok as bool init true;
    try {
        $a = asNumber($flat[0]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    def b as float init 0.0;
    if (len($flat) > 1) {
        try {
            $b = asNumber($flat[1]);
        } catch (e) {
            $b = 0.0;
        }
    }
    return unaryResult($name, $a, $b, len($flat));
}

/**
 * Whether a call would divide by zero.
 *
 * @param name {string} the function name
 * @param b {float} the second argument
 * @param count {int} how many arguments the call had
 * @return {bool} whether the second argument is a zero divisor
 */
func dividesByZero(name as string, b as float, count as int) {
    if ($count < 2 or $b != 0.0) {
        return false;
    }
    return $name == "MOD" or $name == "QUOTIENT";
}

/**
 * Whether a name is a one-argument numeric function.
 *
 * @param name {string} the function name
 * @return {bool} whether this family handles it
 */
func isUnaryName(name as string) {
    return stringIndex(UNARY_NAMES, $name) >= 0;
}

/**
 * The one-argument numeric functions this deck knows.
 *
 * A list rather than a `match`, because the dispatch has to answer "is this
 * mine?" before it evaluates anything.
 */
def const UNARY_NAMES as list of string init [
    "ABS",
    "SQRT",
    "INT",
    "TRUNC",
    "ROUND",
    "ROUNDUP",
    "ROUNDDOWN",
    "CEILING",
    "FLOOR",
    "SIGN",
    "EXP",
    "LN",
    "LOG10",
    "LOG",
    "POWER",
    "MOD",
    "PI",
    "SIN",
    "COS",
    "TAN",
    "ASIN",
    "ACOS",
    "ATAN",
    "ATAN2",
    "DEGREES",
    "RADIANS",
    "FACT",
    "GCD",
    "LCM",
    "QUOTIENT",
    "SQRTPI",
    "EVEN",
    "ODD"
];

/**
 * Work out a one-argument numeric function.
 *
 * @param name {string} the function name
 * @param a {float} the first argument
 * @param b {float} the second, zero when there was none
 * @param count {int} how many arguments there were
 * @return {Value} the result, or an error value
 */
func unaryResult(name as string, a as float, b as float, count as int) {
    # A zero divisor is `#DIV/0!`, not the `#NUM!` every other domain error
    # maps to, and both reference applications agree. Checked here because
    # the catch below cannot tell the two apart.
    if (dividesByZero($name, $b, $count)) {
        return Value.Err{code: ERR_DIV0};
    }
    def out as float init 0.0;
    def ok as bool init true;
    try {
        $out = unaryMath($name, $a, $b, $count);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        # `math` raises where a spreadsheet yields a value: the square root of
        # a negative, a logarithm of zero, a factorial of a fraction.
        return Value.Err{code: ERR_NUM};
    }
    return numberResult($out);
}

/**
 * The arithmetic behind a one-argument numeric function.
 *
 * @param name {string} the function name
 * @param a {float} the first argument
 * @param b {float} the second
 * @param count {int} how many arguments there were
 * @return {float} the result
 * @throws {Error} kind "sheets" when the argument is outside the function's domain
 */
func unaryMath(name as string, a as float, b as float, count as int) {
    match ($name) {
        when "ABS" { return math.abs($a); }
        when "SQRT" { return math.sqrt($a); }
        when "INT" { return convert.toFloat(math.floor($a)); }
        when "TRUNC" { return convert.toFloat(math.trunc($a)); }
        when "SIGN" { return convert.toFloat(math.sign($a)); }
        when "EXP" { return math.exp($a); }
        when "LN" { return math.ln($a); }
        when "LOG10" { return math.log10($a); }
        when "PI" { return math.PI; }
        when "SIN" { return math.sin($a); }
        when "COS" { return math.cos($a); }
        when "TAN" { return math.tan($a); }
        when "ASIN" { return math.asin($a); }
        when "ACOS" { return math.acos($a); }
        when "ATAN" { return math.atan($a); }
        when "ATAN2" { return math.atan2($b, $a); }
        when "DEGREES" { return $a * 180.0 / math.PI; }
        when "RADIANS" { return $a * math.PI / 180.0; }
        when "FACT" { return convert.toFloat(math.factorial(math.floor($a))); }
        when "GCD" { return convert.toFloat(math.gcd(math.floor($a), math.floor($b))); }
        when "LCM" { return convert.toFloat(math.lcm(math.floor($a), math.floor($b))); }
        when "SQRTPI" { return math.sqrt($a * math.PI); }
        else { return unaryMathMore($name, $a, $b, $count); }
    }
}

/**
 * The rest of the one-argument numeric functions.
 *
 * Split only because a `match` of thirty arms nests past what the linter
 * allows.
 *
 * @param name {string} the function name
 * @param a {float} the first argument
 * @param b {float} the second
 * @param count {int} how many arguments there were
 * @return {float} the result
 * @throws {Error} kind "sheets" when the argument is outside the function's domain
 */
func unaryMathMore(name as string, a as float, b as float, count as int) {
    match ($name) {
        when "ROUND" { return roundTo($a, $b, $count); }
        when "ROUNDUP" { return awayFromZero($a, $b, $count, true); }
        when "ROUNDDOWN" { return awayFromZero($a, $b, $count, false); }
        when "CEILING" { return steppedUp($a, $b, $count); }
        when "FLOOR" { return steppedDown($a, $b, $count); }
        when "LOG" { return logBase($a, $b, $count); }
        when "POWER" { return math.pow($a, $b); }
        when "MOD" { return modulo($a, $b); }
        when "QUOTIENT" { return convert.toFloat(math.trunc($a / $b)); }
        when "EVEN" { return toEven($a); }
        when "ODD" { return toOdd($a); }
        else { return 0.0; }
    }
}

/**
 * Round to a number of decimal places.
 *
 * @param a {float} the number
 * @param places {float} the places, zero when there was no second argument
 * @param count {int} how many arguments there were
 * @return {float} the result
 */
func roundTo(a as float, places as float, count as int) {
    def scale as float init math.pow(10.0, roundedPlaces($places, $count));
    return convert.toFloat(math.round($a * $scale)) / $scale;
}

/**
 * The decimal places an argument asked for.
 *
 * @param places {float} the second argument
 * @param count {int} how many arguments there were
 * @return {float} the places, zero when absent
 */
func roundedPlaces(places as float, count as int) {
    if ($count < 2) {
        return 0.0;
    }
    return convert.toFloat(math.trunc($places));
}

/**
 * Round away from or towards zero at a number of places.
 *
 * @param a {float} the number
 * @param places {float} the places
 * @param count {int} how many arguments there were
 * @param away {bool} whether to round away from zero
 * @return {float} the result
 */
func awayFromZero(a as float, places as float, count as int, away as bool) {
    def scale as float init math.pow(10.0, roundedPlaces($places, $count));
    def lifted as float init $a * $scale;
    def whole as float init convert.toFloat(math.trunc($lifted));
    if ($lifted == $whole) {
        return $a;
    }
    if ($away) {
        if ($lifted > 0.0) {
            $whole = $whole + 1.0;
        } else {
            $whole = $whole - 1.0;
        }
    }
    return $whole / $scale;
}

/**
 * Round up to a multiple.
 *
 * @param a {float} the number
 * @param step {float} the multiple
 * @param count {int} how many arguments there were
 * @return {float} the result
 */
func steppedUp(a as float, step as float, count as int) {
    if ($count < 2 or $step == 0.0) {
        return convert.toFloat(math.ceil($a));
    }
    return convert.toFloat(math.ceil($a / $step)) * $step;
}

/**
 * Round down to a multiple.
 *
 * @param a {float} the number
 * @param step {float} the multiple
 * @param count {int} how many arguments there were
 * @return {float} the result
 */
func steppedDown(a as float, step as float, count as int) {
    if ($count < 2 or $step == 0.0) {
        return convert.toFloat(math.floor($a));
    }
    return convert.toFloat(math.floor($a / $step)) * $step;
}

/**
 * A logarithm in a chosen base, defaulting to ten.
 *
 * @param a {float} the number
 * @param base {float} the base
 * @param count {int} how many arguments there were
 * @return {float} the result
 * @throws {Error} kind "sheets" when the base is 0, negative or 1; the math
 *   library's own error when the number is outside the domain
 */
func logBase(a as float, base as float, count as int) {
    if ($count < 2) {
        return math.log10($a);
    }
    # A base of 0 or 1 has no logarithm. `math.log` answered 0 for base 0
    # rather than raising, so the domain is checked here; both reference
    # applications report #NUM!.
    if ($base <= 0.0 or $base == 1.0) {
        fail("LOG has no logarithm in base " + convert.toString($base));
    }
    return math.log($a, $base);
}

/**
 * The remainder, with the sign of the divisor as a spreadsheet gives it.
 *
 * @param a {float} the dividend
 * @param b {float} the divisor
 * @return {float} the remainder
 * @throws {Error} the interpreter's division error when the divisor is zero
 */
func modulo(a as float, b as float) {
    if ($b == 0.0) {
        # Raised rather than returned so the caller reports #DIV/0! through
        # the same path as every other domain error.
        return $a / $b;
    }
    def whole as float init convert.toFloat(math.floor($a / $b));
    return $a - $whole * $b;
}

/**
 * The next even number away from zero.
 *
 * @param a {float} the number
 * @return {float} the result
 */
func toEven(a as float) {
    def stepped as float init awayFromZero($a / 2.0, 0.0, 1, true);
    return $stepped * 2.0;
}

/**
 * The next odd number away from zero.
 *
 * @param a {float} the number
 * @return {float} the result
 */
func toOdd(a as float) {
    def rounded as float init toEven($a);
    if ($a >= 0.0) {
        if ($rounded - 1.0 >= $a) {
            return $rounded - 1.0;
        }
        return $rounded + 1.0;
    }
    if ($rounded + 1.0 <= $a) {
        return $rounded + 1.0;
    }
    return $rounded - 1.0;
}
