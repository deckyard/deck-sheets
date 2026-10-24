# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the conditionals and lookups.
# Spliced into sheets.j via include - not a standalone module.
#
# These take their arguments *unevaluated*, unlike the rest of the library,
# for correctness:
#
#   IF must not evaluate the branch it does not take: `IF(A1=0, 0, 1/A1)` has
#   to work when A1 is zero. The same goes for IFERROR.
#
#   A lookup needs its range's shape, not a flat list of cells: a table's
#   second column means nothing without knowing where the rows end.

/**
 * Choose between two values on a condition.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the chosen branch, or an error value
 */
func fnIf(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def test as Value init evalExpr($args[0], $book, $scope);
    if (isErrorValue($test)) {
        return $test;
    }
    def taken as bool init false;
    def ok as bool init true;
    try {
        $taken = asBool($test);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    if ($taken) {
        return evalExpr($args[1], $book, $scope);
    }
    if (len($args) < 3) {
        return Value.Bool{flag: false};
    }
    return evalExpr($args[2], $book, $scope);
}

/**
 * The first argument, unless it errors.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @param onlyNa {bool} whether to catch only `#N/A`
 * @return {Value} the first argument or the fallback
 */
func fnIfError(args as list of Expr, book as Workbook, scope as Scope, onlyNa as bool) {
    if (len($args) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def tried as Value init evalExpr($args[0], $book, $scope);
    if (not isErrorValue($tried)) {
        return $tried;
    }
    if ($onlyNa and not isNaValue($tried)) {
        return $tried;
    }
    return evalExpr($args[1], $book, $scope);
}

/**
 * The negation of a condition.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the negation, or an error value
 */
func fnNot(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def v as Value init evalExpr($args[0], $book, $scope);
    if (isErrorValue($v)) {
        return $v;
    }
    def flag as bool init false;
    def ok as bool init true;
    try {
        $flag = asBool($v);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Bool{flag: not $flag};
}

/**
 * Whether an odd number of arguments are true.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the result, or an error value
 */
func fnXor(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def trues as int init 0;
    def seen as int init 0;
    for (def arg in $args) {
        for (def v in flattenOne($arg, $book, $scope)) {
            if (isErrorValue($v)) {
                return $v;
            }
            if (isEmpty($v)) {
                continue;
            }
            def flag as bool init false;
            def ok as bool init true;
            try {
                $flag = asBool($v);
            } catch (e) {
                $ok = false;
            }
            if (not $ok) {
                return Value.Err{code: ERR_VALUE};
            }
            $seen = $seen + 1;
            if ($flag) {
                $trues = $trues + 1;
            }
        }
    }
    if ($seen == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Bool{flag: $trues % 2 == 1};
}

/**
 * Whether a value is specifically `#N/A`.
 *
 * @param v {Value} the value
 * @return {bool} whether it is
 */
func isNaValue(v as Value) {
    match ($v) {
        when Err(e) { return $e.code == ERR_NA; }
        else { return false; }
    }
}

/**
 * Whether every or any argument is true.
 *
 * Short-circuits: `AND(A1<>0, 1/A1 > 2)` is safe when A1 is zero.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @param wantAll {bool} whether every argument must be true
 * @return {Value} the result, or an error value
 */
func fnAndOr(args as list of Expr, book as Workbook, scope as Scope, wantAll as bool) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def seen as int init 0;
    for (def arg in $args) {
        for (def v in flattenOne($arg, $book, $scope)) {
            if (isErrorValue($v)) {
                return $v;
            }
            if (isEmpty($v)) {
                continue;
            }
            def flag as bool init false;
            def ok as bool init true;
            try {
                $flag = asBool($v);
            } catch (e) {
                $ok = false;
            }
            if (not $ok) {
                return Value.Err{code: ERR_VALUE};
            }
            $seen = $seen + 1;
            if ($wantAll and not $flag) {
                return Value.Bool{flag: false};
            }
            if (not $wantAll and $flag) {
                return Value.Bool{flag: true};
            }
        }
    }
    if ($seen == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Bool{flag: $wantAll};
}

/**
 * Whether an argument errors.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @param onlyNa {bool} whether to report only `#N/A`
 * @return {Value} whether it does
 */
func fnIsError(args as list of Expr, book as Workbook, scope as Scope, onlyNa as bool) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def tried as Value init evalExpr($args[0], $book, $scope);
    if ($onlyNa) {
        return Value.Bool{flag: isNaValue($tried)};
    }
    return Value.Bool{flag: isErrorValue($tried)};
}

/**
 * Whether an argument is an empty cell.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} whether it is
 */
func fnIsBlank(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Bool{flag: isEmpty(evalExpr($args[0], $book, $scope))};
}

/**
 * Whether an argument is of a given kind.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @param wanted {string} the kind name from `kindOf`
 * @return {Value} whether it is
 */
func fnIsKind(args as list of Expr, book as Workbook, scope as Scope, wanted as string) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def v as Value init evalExpr($args[0], $book, $scope);
    if (isErrorValue($v)) {
        return Value.Bool{flag: false};
    }
    return Value.Bool{flag: kindOf($v) == $wanted};
}

/**
 * How many arguments are numbers, or are not blank.
 *
 * `COUNT` counts numbers and `COUNTA` anything present. Neither propagates
 * an error, so a range with a broken cell can still be counted.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @param anything {bool} whether to count non-numbers too
 * @return {Value} the count
 */
func fnCount(args as list of Expr, book as Workbook, scope as Scope, anything as bool) {
    def total as int init 0;
    for (def arg in $args) {
        # Where the value came from decides whether a boolean counts: COUNT
        # skips booleans held in cells and counts one written into the call.
        # Both Gnumeric and Excel draw the line there.
        def fromSpan as bool init isSpanExpr($arg);
        for (def v in flattenOne($arg, $book, $scope)) {
            if (isEmpty($v)) {
                continue;
            }
            if ($anything) {
                $total = $total + 1;
                continue;
            }
            if (countsAsNumber($v, $fromSpan)) {
                $total = $total + 1;
            }
        }
    }
    return Value.Number{amount: convert.toFloat($total)};
}

/**
 * Whether COUNT should count a value.
 *
 * @param v {Value} the value
 * @param fromSpan {bool} whether it was read out of a range
 * @return {bool} true when it counts as a number
 */
func countsAsNumber(v as Value, fromSpan as bool) {
    if (isErrorValue($v)) {
        return false;
    }
    def kind as string init kindOf($v);
    if ($kind == "text" or $kind == "empty") {
        return false;
    }
    if ($kind == "bool") {
        return not $fromSpan;
    }
    def ok as bool init true;
    try {
        asNumber($v);
    } catch (e) {
        $ok = false;
    }
    return $ok;
}

/**
 * Whether an argument is a range rather than a single value.
 *
 * @param arg {Expr} the argument expression
 * @return {bool} true when it is a span
 */
func isSpanExpr(arg as Expr) {
    match ($arg) {
        when Span(sp) { return true; }
        else { return false; }
    }
}

/**
 * How many cells of a range are empty.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the count
 */
func fnCountBlank(args as list of Expr, book as Workbook, scope as Scope) {
    def total as int init 0;
    for (def arg in $args) {
        for (def v in flattenOne($arg, $book, $scope)) {
            if (isEmpty($v)) {
                $total = $total + 1;
            }
        }
    }
    return Value.Number{amount: convert.toFloat($total)};
}

/**
 * Whether a value satisfies a criterion.
 *
 * A bare value means equality; a string starting with a comparison operator
 * means that comparison (`">10"`, `"<>x"`), parsed out of the text.
 *
 * @param candidate {Value} the value to test
 * @param criterion {Value} the criterion
 * @return {bool} whether it matches
 */
func matchesCriterion(candidate as Value, criterion as Value) {
    def text as string init asString($criterion);
    def symbol as string init criterionOperator($text);
    def rest as string init strings.substring($text, len($symbol), len($text));
    def wanted as Value init criterionValue($rest);
    if ($symbol == "" or $symbol == "=") {
        return criterionEqual($candidate, $wanted);
    }
    if ($symbol == "<>") {
        return not criterionEqual($candidate, $wanted);
    }
    # An ordering criterion compares only within one class: `">1"` counts
    # numbers above 1 and skips text and blanks entirely, while `">a"` counts
    # text. Both reference applications agree, and a type-blind comparison
    # here over-counted by including every text cell.
    if (not sameCriterionClass($candidate, $wanted)) {
        return false;
    }
    def outcome as Value init compareValues($symbol, $candidate, $wanted);
    match ($outcome) {
        when Bool(b) { return $b.flag; }
        else { return false; }
    }
}

/**
 * Test a candidate against a criterion value for equality.
 *
 * An empty criterion (`COUNTIF(range, "")`) matches blank cells and nothing
 * else; conversely a blank cell matches no stated value, so `COUNTIF(r, 0)`
 * skips blanks even though `A1=0` is TRUE for a blank `A1`.
 *
 * @param candidate {Value} the cell being tested
 * @param wanted {Value} the criterion's value
 * @return {bool} true when they are equal under criterion rules
 */
func criterionEqual(candidate as Value, wanted as Value) {
    def blankWanted as bool init false;
    match ($wanted) {
        when Text(t) { $blankWanted = $t.body == ""; }
        when Empty { $blankWanted = true; }
        else { $blankWanted = false; }
    }
    def blankCandidate as bool init false;
    match ($candidate) {
        when Empty { $blankCandidate = true; }
        else { $blankCandidate = false; }
    }
    if ($blankWanted or $blankCandidate) {
        return $blankWanted and $blankCandidate;
    }
    return compareOrder($candidate, $wanted) == 0;
}

/**
 * Whether two values are in the same class for criterion ordering.
 *
 * Numbers, text and booleans form three classes; a blank cell is in none of
 * them, so it never satisfies an ordering criterion.
 *
 * @param candidate {Value} the cell being tested
 * @param wanted {Value} the criterion's value
 * @return {bool} true when both sit in the same comparable class
 */
func sameCriterionClass(candidate as Value, wanted as Value) {
    match ($candidate) {
        when Empty { return false; }
        else {
        }
    }
    return compareRank($candidate) == compareRank($wanted);
}

/**
 * The comparison a criterion's text begins with.
 *
 * @param text {string} the criterion
 * @return {string} the operator, or `""` for a plain equality
 */
func criterionOperator(text as string) {
    for (def symbol in ["<>", "<=", ">=", "<", ">", "="]) {
        if (strings.startsWith($text, $symbol)) {
            return $symbol;
        }
    }
    return "";
}

/**
 * A criterion's right-hand side as a value.
 *
 * @param rest {string} the text after the operator
 * @return {Value} a number when it reads as one, text otherwise
 */
func criterionValue(rest as string) {
    def amount as float init 0.0;
    def numeric as bool init true;
    try {
        $amount = convert.toFloat(strings.trim($rest));
    } catch (e) {
        $numeric = false;
    }
    if ($numeric) {
        return Value.Number{amount: $amount};
    }
    return Value.Text{body: $rest};
}

/**
 * The total of the cells whose matching cell satisfies a criterion.
 *
 * `SUMIF(range, criterion)` totals the range itself; with a third argument it
 * totals that range instead, cell for cell.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the total, or an error value
 */
func fnSumIf(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def tested as list of Value init flattenOne($args[0], $book, $scope);
    def criterion as Value init evalExpr($args[1], $book, $scope);
    if (isErrorValue($criterion)) {
        return $criterion;
    }
    def totalled as list of Value init $tested;
    if (len($args) > 2) {
        $totalled = flattenOne($args[2], $book, $scope);
    }
    def total as float init 0.0;
    for (def i in 0..len($tested)) {
        if (not matchesCriterion($tested[$i], $criterion)) {
            continue;
        }
        if ($i >= len($totalled)) {
            continue;
        }
        def amount as float init 0.0;
        def ok as bool init true;
        try {
            $amount = asNumber($totalled[$i]);
        } catch (e) {
            $ok = false;
        }
        if ($ok) {
            $total = $total + $amount;
        }
    }
    return Value.Number{amount: $total};
}

/**
 * How many cells of a range satisfy a criterion.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the count, or an error value
 */
func fnCountIf(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def criterion as Value init evalExpr($args[1], $book, $scope);
    if (isErrorValue($criterion)) {
        return $criterion;
    }
    def total as int init 0;
    for (def v in flattenOne($args[0], $book, $scope)) {
        if (matchesCriterion($v, $criterion)) {
            $total = $total + 1;
        }
    }
    return Value.Number{amount: convert.toFloat($total)};
}

/**
 * A rectangular block of values and its shape.
 *
 * @field cells {list of Value} the values, row by row
 * @field rows {int} how many rows
 * @field cols {int} how many columns
 */
def struct Block {
    cells as list of Value,
    rows as int,
    cols as int
};

/**
 * One argument as a rectangular block.
 *
 * @param arg {Expr} the unevaluated argument
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Block} the block, zero-sized when the argument is not a range
 */
func blockOf(arg as Expr, book as Workbook, scope as Scope) {
    match ($arg) {
        when Span(sp) { return spanBlock($sp.body, $book, $scope); }
        else {
            def cells as list of Value init [];
            $cells[] = evalExpr($arg, $book, $scope);
            return Block{cells: $cells, rows: 1, cols: 1};
        }
    }
}

/**
 * A range as a rectangular block.
 *
 * @param body {string} the range as written
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Block} the block, zero-sized when the range is unreadable
 */
func spanBlock(body as string, book as Workbook, scope as Scope) {
    def shape as Area init spanArea($body, $book, $scope);
    def cells as list of Value init spanValues($body, $book, $scope);
    def rows as int init $shape.to2.row - $shape.from.row + 1;
    def cols as int init $shape.to2.col - $shape.from.col + 1;
    if (len($cells) != $rows * $cols) {
        return Block{cells: $cells, rows: 0, cols: 0};
    }
    return Block{cells: $cells, rows: $rows, cols: $cols};
}

/**
 * One value of a block, by row and column.
 *
 * @param block {Block} the block
 * @param row {int} the zero-based row
 * @param col {int} the zero-based column
 * @return {Value} the value, or `#REF!` when it is outside the block
 */
func blockAt(block as Block, row as int, col as int) {
    if ($row < 0 or $col < 0 or $row >= $block.rows or $col >= $block.cols) {
        return Value.Err{code: ERR_REF};
    }
    return $block.cells[$row * $block.cols + $col];
}

/**
 * Look a value up in the first column of a table and read across.
 *
 * Exact match only: the approximate form needs a sorted table, and a wrong
 * answer from an unsorted one is worse than `#N/A`. A fourth argument asking
 * for the approximate form is accepted and ignored.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the value found, or `#N/A`
 */
func fnVlookup(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) < 3) {
        return Value.Err{code: ERR_VALUE};
    }
    def needle as Value init evalExpr($args[0], $book, $scope);
    if (isErrorValue($needle)) {
        return $needle;
    }
    def table as Block init blockOf($args[1], $book, $scope);
    def column as int init indexArg($args[2], $book, $scope);
    if ($column < 1 or $table.rows == 0) {
        return Value.Err{code: ERR_REF};
    }
    if ($column > $table.cols) {
        return Value.Err{code: ERR_REF};
    }
    for (def r in 0..$table.rows) {
        if (compareOrder(blockAt($table, $r, 0), $needle) == 0) {
            return blockAt($table, $r, $column - 1);
        }
    }
    return Value.Err{code: ERR_NA};
}

/**
 * Look a value up in the first row of a table and read down.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the value found, or `#N/A`
 */
func fnHlookup(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) < 3) {
        return Value.Err{code: ERR_VALUE};
    }
    def needle as Value init evalExpr($args[0], $book, $scope);
    if (isErrorValue($needle)) {
        return $needle;
    }
    def table as Block init blockOf($args[1], $book, $scope);
    def row as int init indexArg($args[2], $book, $scope);
    if ($row < 1 or $table.cols == 0) {
        return Value.Err{code: ERR_REF};
    }
    if ($row > $table.rows) {
        return Value.Err{code: ERR_REF};
    }
    for (def c in 0..$table.cols) {
        if (compareOrder(blockAt($table, 0, $c), $needle) == 0) {
            return blockAt($table, $row - 1, $c);
        }
    }
    return Value.Err{code: ERR_NA};
}

/**
 * One cell of a range by position.
 *
 * With one index over a single row or column it reads along it, the form
 * that pairs with `MATCH`.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the value, or `#REF!`
 */
func fnIndex(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def table as Block init blockOf($args[0], $book, $scope);
    if ($table.rows == 0) {
        return Value.Err{code: ERR_REF};
    }
    def first as int init indexArg($args[1], $book, $scope);
    if (len($args) < 3) {
        if ($table.rows == 1) {
            return blockAt($table, 0, $first - 1);
        }
        if ($table.cols == 1) {
            return blockAt($table, $first - 1, 0);
        }
        return Value.Err{code: ERR_REF};
    }
    def second as int init indexArg($args[2], $book, $scope);
    return blockAt($table, $first - 1, $second - 1);
}

/**
 * Where a value sits in a single row or column, one-based.
 *
 * The third argument is the match type, as in the applications: 0 is an
 * exact match; 1 (the default) and -1 search sorted data, see
 * `orderedMatch`.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Value} the position, or `#N/A`
 */
func fnMatch(args as list of Expr, book as Workbook, scope as Scope) {
    if (len($args) < 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def needle as Value init evalExpr($args[0], $book, $scope);
    if (isErrorValue($needle)) {
        return $needle;
    }
    def haystack as list of Value init flattenOne($args[1], $book, $scope);
    def how as int init 1;
    if (len($args) > 2) {
        def given as Value init evalExpr($args[2], $book, $scope);
        if (isErrorValue($given)) {
            return $given;
        }
        $how = numberOrZeroInt($given);
    }
    if ($how == 0) {
        for (def i in 0..len($haystack)) {
            if (compareOrder($haystack[$i], $needle) == 0) {
                return Value.Number{amount: convert.toFloat($i + 1)};
            }
        }
        return Value.Err{code: ERR_NA};
    }
    return orderedMatch($haystack, $needle, $how);
}

/**
 * MATCH over data assumed to be sorted.
 *
 * Type 1 wants ascending data and answers the last position holding a value
 * no greater than the target; type -1 wants descending data and answers the
 * last position holding a value no less than it. Taking the last is what
 * makes a target past the end of the data answer with the end of the data
 * instead of `#N/A`, as both reference applications do.
 *
 * @param haystack {list of Value} the values, in the order the type assumes
 * @param needle {Value} the value being looked for
 * @param how {int} 1 for ascending, anything else for descending
 * @return {Value} the one-based position, or `#N/A`
 */
func orderedMatch(haystack as list of Value, needle as Value, how as int) {
    def found as int init 0;
    for (def i in 0..len($haystack)) {
        def order as int init compareOrder($haystack[$i], $needle);
        def fits as bool init $order >= 0;
        if ($how == 1) {
            $fits = $order <= 0;
        }
        if ($fits) {
            $found = $i + 1;
        }
    }
    if ($found == 0) {
        return Value.Err{code: ERR_NA};
    }
    return Value.Number{amount: convert.toFloat($found)};
}

/**
 * A value as a whole number, treating anything uncountable as 0.
 *
 * @param v {Value} the value
 * @return {int} the number it holds, truncated
 */
func numberOrZeroInt(v as Value) {
    def out as int init 0;
    try {
        $out = math.trunc(asNumber($v));
    } catch (e) {
        $out = 0;
    }
    return $out;
}

/**
 * An argument as a one-based index.
 *
 * @param arg {Expr} the unevaluated argument
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {int} the index, or `-1` when it will not read as one
 */
func indexArg(arg as Expr, book as Workbook, scope as Scope) {
    def v as Value init evalExpr($arg, $book, $scope);
    def amount as float init 0.0;
    def ok as bool init true;
    try {
        $amount = asNumber($v);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return -1;
    }
    return math.trunc($amount);
}

/**
 * The row or column number of a reference.
 *
 * With no argument it means the formula's own cell, which evaluation does
 * not track, so that form yields `#VALUE!` rather than a wrong number.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @param wantRow {bool} whether to give the row
 * @return {Value} the number, or an error value
 */
func fnRowCol(args as list of Expr, book as Workbook, scope as Scope, wantRow as bool) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def shape as Area init argArea($args[0], $book, $scope);
    if ($shape.to2.row < $shape.from.row) {
        return Value.Err{code: ERR_REF};
    }
    if ($wantRow) {
        return Value.Number{amount: convert.toFloat($shape.from.row + 1)};
    }
    return Value.Number{amount: convert.toFloat($shape.from.col + 1)};
}

/**
 * How many rows or columns a range covers.
 *
 * @param args {list of Expr} the unevaluated arguments
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @param wantRows {bool} whether to count rows
 * @return {Value} the count, or an error value
 */
func fnSpanSize(args as list of Expr, book as Workbook, scope as Scope, wantRows as bool) {
    if (len($args) == 0) {
        return Value.Err{code: ERR_VALUE};
    }
    def shape as Area init argArea($args[0], $book, $scope);
    if ($shape.to2.row < $shape.from.row) {
        return Value.Err{code: ERR_REF};
    }
    if ($wantRows) {
        return Value.Number{amount: convert.toFloat($shape.to2.row - $shape.from.row + 1)};
    }
    return Value.Number{amount: convert.toFloat($shape.to2.col - $shape.from.col + 1)};
}

/**
 * The area an argument denotes.
 *
 * @param arg {Expr} the unevaluated argument
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Area} the area, inverted when the argument is not a reference
 */
func argArea(arg as Expr, book as Workbook, scope as Scope) {
    match ($arg) {
        when Span(sp) { return spanArea($sp.body, $book, $scope); }
        when Cell(c) { return cellArea($c.body); }
        else { return invertedArea(); }
    }
}

/**
 * One reference as a one-cell area.
 *
 * @param body {string} the reference as written
 * @return {Area} the area, inverted when it will not parse
 */
func cellArea(body as string) {
    def at as Ref init Ref{row: 0, col: 0};
    def ok as bool init true;
    try {
        $at = parseRef(splitSheetRef($body)[1]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return invertedArea();
    }
    return Area{from: $at, to2: $at};
}

/**
 * The area a range covers.
 *
 * @param body {string} the range as written
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what the call can see
 * @return {Area} the area, inverted when it will not parse
 */
func spanArea(body as string, book as Workbook, scope as Scope) {
    def colon as int init rangeColonAt($body);
    if ($colon < 0) {
        return cellArea($body);
    }
    def leftHalf as string init strings.substring($body, 0, $colon);
    def rightHalf as string init strings.substring($body, $colon + 1, len($body));
    def box as Area init invertedArea();
    def ok as bool init true;
    try {
        $box = area(parseRef(splitSheetRef($leftHalf)[1]), parseRef(splitSheetRef($rightHalf)[1]));
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return invertedArea();
    }
    return $box;
}

/**
 * An area that cannot be satisfied, used as "no area".
 *
 * `Area` has no empty value (every pair of corners is a rectangle), so an
 * inverted one is the sentinel.
 *
 * @return {Area} an area whose end is before its start
 */
func invertedArea() {
    return Area{from: Ref{row: 1, col: 1}, to2: Ref{row: 0, col: 0}};
}
