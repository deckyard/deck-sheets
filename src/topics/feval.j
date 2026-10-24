# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - the formula evaluator.
# Spliced into sheets.j via include - not a standalone module.
#
# Two things differ from a programming-language evaluator:
#
#   An error is a value. `1/0` yields #DIV/0!, which propagates through every
#   operation that touches it. The evaluator returns a `Value` and almost
#   never throws, since a throw would abort recalculating a whole sheet over
#   one bad cell.
#
#   A reference is lazy. Evaluating A1 means evaluating whatever A1 holds,
#   which may be another formula, so the dependency graph is implicit and
#   cycle detection is the evaluator's job.

/**
 * What `recalculate` returns: the sheet with every `Formula` cell's `cached`
 * result filled in.
 *
 * The expressions are untouched, so writing the sheet still writes formulas.
 *
 * @field sheet {Sheet} the sheet, with cached results filled in
 * @field evaluated {int} how many formula cells were worked out
 * @field failed {int} how many yielded an error value
 */
export def struct Recalculated {
    sheet as Sheet,
    evaluated as int,
    failed as int
};

/**
 * What an evaluation can see.
 *
 * The workbook is carried whole because a formula may reach another sheet,
 * and `visiting` is the cycle guard: a reference already on the stack is a
 * circular reference, which is an error value rather than an exception.
 *
 * @field sheetName {string} the sheet an unqualified reference means
 * @field visiting {map of string to bool} the cells currently being evaluated
 * @field depth {int} how deep the chain of formulas is
 */
def struct Scope {
    sheetName as string,
    visiting as map of string to bool,
    depth as int
};

/**
 * Work out one formula against a workbook.
 *
 * An error in the formula (a bad name, a division by zero, a circular
 * reference) comes back as an error `Value`, as a spreadsheet shows it, so
 * the result can go straight into a cell. Only a formula that does not parse,
 * or a sheet name the workbook lacks, throws.
 *
 * @param wb {Workbook} the workbook the formula refers into
 * @param sheetName {string} the sheet an unqualified reference means
 * @param source {string} the formula in A1; a leading `=` is dropped
 * @return {Value} the result
 * @throws {Error} kind "sheets" when the workbook has no such sheet, or the
 *   formula is not a well-formed expression or exceeds `MAX_FORMULA_DEPTH` or
 *   `MAX_FORMULA_TOKENS`
 * @example
 *   evaluate($wb, "Sheet1", "SUM(B2:B10)*1.2");
 */
export func evaluate(wb as Workbook, sheetName as string, source as string) {
    # A sheet name that is not in the workbook is a caller mistake, not a cell
    # error: every relative reference in the formula would quietly read as
    # blank and the answer would look fine.
    if (not hasSheet($wb, $sheetName)) {
        fail("the workbook has no sheet named " + quoted($sheetName));
    }
    def tree as Expr init parseFormula($source);
    # Resolve what the formula depends on first, so the walk below never
    # follows a reference into another formula. See `resolveFrom`.
    def work as Workbook init resolveFrom($wb, $sheetName, referencesOf($tree, $sheetName));
    return evalExpr($tree, $work, Scope{sheetName: $sheetName, visiting: {}, depth: 0});
}

/**
 * Fill in every formula's cached result on one sheet.
 *
 * One resolution pass covers the whole sheet (see `resolveFrom`), so a cell
 * many others depend on is computed once. A cycle caches `#REF!`. A formula
 * that will not parse caches `#NAME?` and counts as failed rather than
 * refusing the sheet. Formulas on other sheets are read through, not written
 * back.
 *
 * @param wb {Workbook} the workbook
 * @param sheetName {string} the sheet to work out
 * @return {Recalculated} the sheet and what happened
 * @throws {Error} kind "sheets" when the workbook has no sheet by that name
 * @example
 *   def done as Recalculated init recalculate($wb, "Sheet1");
 *   $wb = putSheet($wb, $done.sheet);
 */
export func recalculate(wb as Workbook, sheetName as string) {
    if (not hasSheet($wb, $sheetName)) {
        fail("the workbook has no sheet named " + quoted($sheetName));
    }
    # Three shapes are avoided here, each of which made this quadratic and
    # each measured at about 300x on 3 000 cells (see `cellInScope`):
    #
    #   reading a cell through `cellAt($s, $at)` passes the sheet, copying
    #   its whole cells map per cell, so the scan walks the map in place;
    #   writing each result through `setCellAt` copies the map per write, so
    #   the results go into one local map that is built once;
    #   and the sheet is found by index rather than by `sheetByName`, which
    #   would bind a `Sheet` to a local and copy it.
    #
    # Before: 4 000 formulas took 79 s. After: see docs/internal/memory.md.
    def which as int init sheetIndexOf($wb, $sheetName);
    # And one resolution pass for the whole sheet, so a cell that several
    # others depend on is computed once rather than once per dependent.
    def seeds as list of string init [];
    for (def key in maps.keys($wb.sheets[$which].cells)) {
        $seeds[] = cellKey($sheetName, parseRef($key));
    }
    def work as Workbook init resolveFrom($wb, $sheetName, $seeds);
    def cells as map of string to Value init {};
    def evaluated as int init 0;
    def failed as int init 0;
    for (def key in maps.keys($wb.sheets[$which].cells)) {
        def held as Value init $wb.sheets[$which].cells[$key];
        match ($held) {
            when Formula(f) {
                def result as Value init $work.sheets[$which].cells[$key];
                $cells[$key] = Value.Formula{source: $f.source, cached: asString($result)};
                $evaluated = $evaluated + 1;
                if (isErrorValue($result)) {
                    $failed = $failed + 1;
                }
            }
            else { $cells[$key] = $held; }
        }
    }
    def out as Sheet init Sheet{
        name: $wb.sheets[$which].name,
        cells: $cells,
        cellStyles: $wb.sheets[$which].cellStyles,
        styles: $wb.sheets[$which].styles,
        rowCount: $wb.sheets[$which].rowCount,
        colCount: $wb.sheets[$which].colCount
    };
    return Recalculated{sheet: $out, evaluated: $evaluated, failed: $failed};
}

/**
 * Where a sheet sits in a workbook.
 *
 * By index, so a caller can reach the sheet through the field chain instead
 * of binding a copy of it. See `cellInScope`.
 *
 * @param wb {Workbook} the workbook
 * @param name {string} the sheet name
 * @return {int} the index, or -1 when there is no such sheet
 */
func sheetIndexOf(wb as Workbook, name as string) {
    for (def i in 0..len($wb.sheets)) {
        if ($wb.sheets[$i].name == $name) {
            return $i;
        }
    }
    return -1;
}

/**
 * What recalculating one cell produced.
 *
 * @field value {Value} the cell's new value
 * @field changed {bool} whether the cell was a formula at all
 * @field errored {bool} whether the result is an error value
 */
def struct CellOutcome {
    value as Value,
    changed as bool,
    errored as bool
};

/**
 * Work out one cell, if it is a formula.
 *
 * @param wb {Workbook} the workbook
 * @param sheetName {string} the sheet the cell is on
 * @param at {Ref} where the cell is
 * @param v {Value} the cell's current value
 * @return {CellOutcome} the new value and what happened
 */
func recalculateCell(wb as Workbook, sheetName as string, at as Ref, v as Value) {
    match ($v) {
        when Formula(f) {
            def result as Value init evaluateAt($wb, $sheetName, $at, $f.source);
            return CellOutcome{
                value: Value.Formula{source: $f.source, cached: asString($result)},
                changed: true,
                errored: isErrorValue($result)
            };
        }
        else { return CellOutcome{value: $v, changed: false, errored: false}; }
    }
}

/**
 * Work out a formula that lives in a known cell.
 *
 * The cell is marked as being visited before its own expression runs, so a
 * formula that refers to itself is caught as a cycle rather than recursing.
 *
 * @param wb {Workbook} the workbook
 * @param sheetName {string} the sheet the formula is on
 * @param at {Ref} where the formula is
 * @param source {string} the expression
 * @return {Value} the result, or an error value
 */
func evaluateAt(wb as Workbook, sheetName as string, at as Ref, source as string) {
    def visiting as map of string to bool init {};
    $visiting[cellKey($sheetName, $at)] = true;
    def tree as Expr init Expr.Num{amount: 0.0};
    def parsed as bool init true;
    try {
        $tree = parseFormula($source);
    } catch (e) {
        $parsed = false;
    }
    if (not $parsed) {
        return Value.Err{code: ERR_NAME};
    }
    return evalExpr($tree, $wb, Scope{sheetName: $sheetName, visiting: $visiting, depth: 0});
}

/**
 * The key a cell is tracked under while it is being evaluated.
 *
 * @param sheetName {string} the sheet
 * @param at {Ref} the cell
 * @return {string} the key
 */
func cellKey(sheetName as string, at as Ref) {
    return $sheetName + "!" + cellRef($at);
}

/**
 * Whether a value is an error.
 *
 * @param v {Value} the value
 * @return {bool} whether it is an error value
 */
export func isErrorValue(v as Value) {
    match ($v) {
        when Err(e) { return true; }
        else { return false; }
    }
}

/**
 * Work out one node of an expression tree.
 *
 * @param node {Expr} the node
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what it can see
 * @return {Value} the result, or an error value
 */
func evalExpr(node as Expr, book as Workbook, scope as Scope) {
    if ($scope.depth > MAX_FORMULA_DEPTH) {
        return Value.Err{code: ERR_CIRCULAR};
    }
    match ($node) {
        when Num(n) { return Value.Number{amount: $n.amount}; }
        when Str(st) { return Value.Text{body: $st.body}; }
        when Logic(l) { return Value.Bool{flag: $l.flag}; }
        when ErrLit(e) { return Value.Err{code: $e.body}; }
        when Cell(c) { return evalCellRef($c.body, $book, $scope); }
        when Span(sp) { return firstOfSpan($sp.body, $book, $scope); }
        when NameRef(nm) { return Value.Err{code: ERR_NAME}; }
        when Unary(u) { return evalUnary($u.symbol, $u.parts, $book, $scope); }
        when Binary(b) { return evalBinary($b.symbol, $b.parts, $book, $scope); }
        when Call(call) { return applyFunction($call.name, $call.parts, $book, $scope); }
    }
}

/**
 * Work out a reference to one cell.
 *
 * A reference to a formula evaluates that formula, which is what makes the
 * dependency graph implicit. A reference already being evaluated is a cycle.
 *
 * @param body {string} the reference as written
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what it can see
 * @return {Value} the referenced cell's value
 */
func evalCellRef(body as string, book as Workbook, scope as Scope) {
    def halves as list of string init splitSheetRef($body);
    def sheetName as string init $halves[0];
    if ($sheetName == "") {
        $sheetName = $scope.sheetName;
    }
    if (not hasSheet($book, $sheetName)) {
        return Value.Err{code: ERR_REF};
    }
    def at as Ref init Ref{row: 0, col: 0};
    def ok as bool init true;
    try {
        $at = parseRef($halves[1]);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_REF};
    }
    def key as string init cellKey($sheetName, $at);
    if (maps.has($scope.visiting, $key)) {
        return Value.Err{code: ERR_CIRCULAR};
    }
    def v as Value init cellInScope($book, $sheetName, $at);
    match ($v) {
        when Formula(f) {
            def inner as map of string to bool init $scope.visiting;
            $inner[$key] = true;
            return evalNested($f.source, $sheetName, $inner, $book, $scope);
        }
        else { return $v; }
    }
}

/**
 * Work out a formula reached through a reference.
 *
 * @param source {string} the expression
 * @param sheetName {string} the sheet it lives on
 * @param visiting {map of string to bool} the cells on the stack
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} the scope it was reached from
 * @return {Value} the result, or an error value
 */
func evalNested(
    source as string,
    sheetName as string,
    visiting as map of string to bool,
    book as Workbook,
    scope as Scope) {
    def tree as Expr init Expr.Num{amount: 0.0};
    def parsed as bool init true;
    try {
        $tree = parseFormula($source);
    } catch (e) {
        $parsed = false;
    }
    if (not $parsed) {
        return Value.Err{code: ERR_NAME};
    }
    return evalExpr(
        $tree,
        $book,
        Scope{sheetName: $sheetName, visiting: $visiting, depth: $scope.depth + 1});
}

/**
 * The first cell of a range, which is what a range means in a scalar position.
 *
 * `A1:A5 * 2` is not an array formula here: the range collapses to its first
 * cell, which is what a spreadsheet does outside an array context.
 *
 * @param body {string} the range as written
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what it can see
 * @return {Value} the first cell's value
 */
func firstOfSpan(body as string, book as Workbook, scope as Scope) {
    def cells as list of Value init spanValues($body, $book, $scope);
    if (len($cells) == 0) {
        return Value.Err{code: ERR_REF};
    }
    # A multi-cell span where one value is wanted - `A1:A5*2`, or
    # `OR(A1:A5>4)` - is an array expression, which this engine does not
    # evaluate. Both reference applications answer `#VALUE!` rather than
    # silently taking one cell, and taking the first cell produced answers
    # that looked right and were not: `OR(A3:E3>4)` came back FALSE over a
    # row ending in 5.
    if (len($cells) > 1) {
        return Value.Err{code: ERR_VALUE};
    }
    return $cells[0];
}

/**
 * Wrap built-up text as a value, refusing it past the growth cap.
 *
 * The choke point for every operation that can make text longer than its
 * inputs, so one check covers `&`, `CONCATENATE` and `CONCAT`. See
 * `MAX_TEXT_GROWTH` for why the bound is not the cell limit.
 *
 * @param body {string} the text that was built
 * @return {Value} the text, or `#VALUE!` when it grew past the cap
 */
func grownText(body as string) {
    if (len($body) > MAX_TEXT_GROWTH) {
        return Value.Err{code: ERR_VALUE};
    }
    return Value.Text{body: $body};
}

/**
 * How many cells one evaluation may resolve.
 *
 * Resolution is memoised, so this counts distinct cells, not evaluations. A
 * cell whose dependencies would push the count past it resolves to `#NUM!`.
 */
export def const MAX_RESOLVED_CELLS as int init 500000;

/**
 * Resolve every formula a set of references depends on, into literal values.
 *
 * In the returned working copy, each formula cell reached from `seeds` is
 * replaced by its value, so evaluating against it follows no references.
 *
 * The obvious shape (follow a reference, evaluate what it holds, recurse) is
 * wrong twice over:
 *
 *   it re-evaluates. A column where each cell doubles the one above it
 *   (`A2` is `A1+A1`) costs 2^n evaluations, so depth 16 measured 15.9 s and
 *   depth 20 did not finish. Here each cell is computed once.
 *
 *   it recursed as deep as the chain. A running total - `B3` is `B2+A3` -
 *   is a chain as long as the column, and bounding the recursion to keep the
 *   interpreter alive meant a 100-row running total answered `#REF!`. The
 *   walk below is iterative over an explicit stack, so chain length is
 *   bounded by `MAX_RESOLVED_CELLS` rather than by the stack.
 *
 * Cycles resolve to `#REF!`, as both reference applications show. A formula
 * that will not parse resolves to `#NAME?`.
 *
 * @param wb {Workbook} the workbook to resolve against
 * @param sheetName {string} the sheet unqualified references belong to
 * @param seeds {list of string} the references to start from
 * @return {Workbook} a working copy with those formulas replaced by values
 */
func resolveFrom(wb as Workbook, sheetName as string, seeds as list of string) {
    def work as Workbook init $wb;
    def done as map of string to bool init {};
    # `onStack` marks membership rather than removing keys, and the stack
    # carries a live length instead of being truncated. Both because
    # rebuilding a map and slicing a list each copy the whole collection, so
    # doing either once per cell made a long chain quadratic: a 2 000-cell
    # chain took 16.4 s that way, against 2.5 s this way.
    def onStack as map of string to bool init {};
    def stack as list of string init [];
    for (def seed in $seeds) {
        $stack[] = $seed;
    }
    def high as int init len($stack);
    def resolved as int init 0;
    while ($high > 0) {
        def key as string init $stack[$high - 1];
        if (maps.has($done, $key)) {
            $high = $high - 1;
            continue;
        }
        def step as CellStep init stepFor($work, $key, $sheetName, $done, $onStack);
        if ($step.verdict == STEP_SKIP) {
            $done[$key] = true;
            $onStack[$key] = false;
            $high = $high - 1;
            continue;
        }
        if ($step.verdict == STEP_MARK) {
            $work.sheets[$step.which].cells[$step.ref] = Value.Err{code: $step.code};
            $done[$key] = true;
            $onStack[$key] = false;
            $high = $high - 1;
            continue;
        }
        if ($step.verdict == STEP_WAIT) {
            if ($resolved + len($step.waiting) > MAX_RESOLVED_CELLS) {
                $work.sheets[$step.which].cells[$step.ref] = Value.Err{code: ERR_NUM};
                $done[$key] = true;
                $high = $high - 1;
                continue;
            }
            $onStack[$key] = true;
            while (len($stack) < $high + len($step.waiting)) {
                $stack[] = "";
            }
            for (def i in 0..len($step.waiting)) {
                $stack[$high + $i] = $step.waiting[$i];
            }
            $high = $high + len($step.waiting);
            continue;
        }
        # Every reference this cell makes is a literal now, so evaluating it
        # follows nothing.
        def value as Value init evalExpr(
            $step.tree,
            $work,
            Scope{sheetName: $step.sheetName, visiting: {}, depth: 0});
        $work.sheets[$step.which].cells[$step.ref] = $value;
        $done[$key] = true;
        $onStack[$key] = false;
        $high = $high - 1;
        $resolved = $resolved + 1;
    }
    return $work;
}

/** The cell needs nothing: it is a literal, a blank, or unreadable. */
def const STEP_SKIP as string init "skip";

/** The cell resolves to an error, which is in the step's `code`. */
def const STEP_MARK as string init "mark";

/** The cell is waiting on the dependencies in the step's `waiting`. */
def const STEP_WAIT as string init "wait";

/** The cell's dependencies are all resolved, so it can be computed. */
def const STEP_COMPUTE as string init "compute";

/**
 * What `resolveFrom` should do with the cell on top of its stack.
 *
 * @field verdict {string} one of the four `STEP_` constants
 * @field which {int} the sheet's index in the workbook
 * @field ref {string} the cell's key within that sheet
 * @field sheetName {string} the sheet the cell's formula belongs to
 * @field code {string} the error to write, when the verdict is `STEP_MARK`
 * @field waiting {list of string} what to resolve first, for `STEP_WAIT`
 * @field tree {Expr} the parsed expression, for `STEP_COMPUTE`
 */
def struct CellStep {
    verdict as string,
    which as int,
    ref as string,
    sheetName as string,
    code as string,
    waiting as list of string,
    tree as Expr
};

/**
 * Decide what one cell on the resolution stack needs next.
 *
 * Split out of `resolveFrom` so its loop stays flat rather than nesting four
 * deep.
 *
 * @param work {Workbook} the working copy being resolved into
 * @param key {string} the cell, as a `sheet!A1` key
 * @param sheetName {string} the sheet an unqualified key belongs to
 * @param done {map of string to bool} the cells already resolved
 * @param onStack {map of string to bool} the cells being resolved
 * @return {CellStep} what to do with it
 */
func stepFor(
    work as Workbook,
    key as string,
    sheetName as string,
    done as map of string to bool,
    onStack as map of string to bool) {
    def nothing as CellStep init CellStep{
        verdict: STEP_SKIP,
        which: 0,
        ref: "",
        sheetName: $sheetName,
        code: "",
        waiting: [],
        tree: Expr.Num{amount: 0.0}
    };
    def spot as CellSpot init spotOf($key, $sheetName);
    if (not $spot.ok or not hasSheet($work, $spot.sheetName)) {
        return $nothing;
    }
    def step as CellStep init $nothing;
    $step.which = sheetIndexOf($work, $spot.sheetName);
    $step.ref = cellRef($spot.at);
    $step.sheetName = $spot.sheetName;
    def source as string init formulaSourceAt($work, $step.which, $step.ref);
    if ($source == "") {
        # A literal, a blank, or a cell already replaced by its value.
        return $step;
    }
    def tree as Expr init Expr.Num{amount: 0.0};
    def parsed as bool init true;
    try {
        $tree = parseFormula($source);
    } catch (e) {
        $parsed = false;
    }
    if (not $parsed) {
        # Unreadable, so the cell is `#NAME?` and nothing depends on it
        # any further.
        $step.verdict = STEP_MARK;
        $step.code = ERR_NAME;
        return $step;
    }
    $step.tree = $tree;
    def scan as DepScan init unresolvedDeps($tree, $spot.sheetName, $done, $onStack);
    if ($scan.looping) {
        $step.verdict = STEP_MARK;
        $step.code = ERR_CIRCULAR;
        return $step;
    }
    if (len($scan.waiting) > 0) {
        $step.verdict = STEP_WAIT;
        $step.waiting = $scan.waiting;
        return $step;
    }
    $step.verdict = STEP_COMPUTE;
    return $step;
}

/**
 * A cell's formula expression, or empty text when it holds no formula.
 *
 * @param wb {Workbook} the workbook to read from
 * @param which {int} the sheet's index
 * @param ref {string} the cell's key within the sheet
 * @return {string} the expression, or `""`
 */
func formulaSourceAt(wb as Workbook, which as int, ref as string) {
    if (not maps.has($wb.sheets[$which].cells, $ref)) {
        return "";
    }
    def held as Value init $wb.sheets[$which].cells[$ref];
    match ($held) {
        when Formula(f) { return $f.source; }
        else { return ""; }
    }
}

/**
 * What a cell is still waiting on.
 *
 * @field waiting {list of string} the dependencies not yet resolved
 * @field looping {bool} whether one of them is already being resolved
 */
def struct DepScan {
    waiting as list of string,
    looping as bool
};

/**
 * Sort an expression's references into resolved, pending and circular.
 *
 * @param tree {Expr} the cell's expression
 * @param sheetName {string} the sheet unqualified references belong to
 * @param done {map of string to bool} the cells already resolved
 * @param onStack {map of string to bool} the cells being resolved
 * @return {DepScan} what is still wanted, and whether that is a cycle
 */
func unresolvedDeps(
    tree as Expr,
    sheetName as string,
    done as map of string to bool,
    onStack as map of string to bool) {
    def waiting as list of string init [];
    def looping as bool init false;
    for (def dep in referencesOf($tree, $sheetName)) {
        if (maps.has($done, $dep)) {
            continue;
        }
        if (maps.has($onStack, $dep)) {
            $looping = true;
            continue;
        }
        $waiting[] = $dep;
    }
    return DepScan{waiting: $waiting, looping: $looping};
}

/**
 * Where a reference key points, once the sheet is filled in.
 *
 * @field sheetName {string} the sheet, never empty
 * @field at {Ref} the cell
 * @field ok {bool} whether the reference could be read at all
 */
def struct CellSpot {
    sheetName as string,
    at as Ref,
    ok as bool
};

/**
 * Read a `sheet!A1` key, defaulting the sheet.
 *
 * @param key {string} the reference
 * @param fallback {string} the sheet to assume when the key names none
 * @return {CellSpot} where it points
 */
func spotOf(key as string, fallback as string) {
    def halves as list of string init splitSheetRef($key);
    def name as string init $halves[0];
    if ($name == "") {
        $name = $fallback;
    }
    def at as Ref init Ref{row: 0, col: 0};
    def ok as bool init true;
    try {
        $at = parseRef($halves[1]);
    } catch (e) {
        $ok = false;
    }
    return CellSpot{sheetName: $name, at: $at, ok: $ok};
}

/**
 * Every cell an expression refers to, as `sheet!A1` keys.
 *
 * A range contributes every cell it covers, because any of them may hold a
 * formula. A range past `MAX_RANGE_CELLS` contributes nothing: the span
 * itself reports `#NUM!` when it is evaluated.
 *
 * @param node {Expr} the expression
 * @param sheetName {string} the sheet unqualified references belong to
 * @return {list of string} the keys, with repeats
 */
func referencesOf(node as Expr, sheetName as string) {
    def out as list of string init [];
    match ($node) {
        when Cell(c) {
            def spot as CellSpot init spotOf($c.body, $sheetName);
            if ($spot.ok) {
                $out[] = cellKey($spot.sheetName, $spot.at);
            }
        }
        when Span(sp) {
            for (def key in spanKeys($sp.body, $sheetName)) {
                $out[] = $key;
            }
        }
        when Unary(u) {
            for (def key in referencesInParts($u.parts, $sheetName)) {
                $out[] = $key;
            }
        }
        when Binary(b) {
            for (def key in referencesInParts($b.parts, $sheetName)) {
                $out[] = $key;
            }
        }
        when Call(call) {
            for (def key in referencesInParts($call.parts, $sheetName)) {
                $out[] = $key;
            }
        }
        else {
        }
    }
    return $out;
}

/**
 * Every cell a list of sub-expressions refers to.
 *
 * @param parts {list of Expr} the sub-expressions
 * @param sheetName {string} the sheet unqualified references belong to
 * @return {list of string} the keys, with repeats
 */
func referencesInParts(parts as list of Expr, sheetName as string) {
    def out as list of string init [];
    for (def part in $parts) {
        for (def key in referencesOf($part, $sheetName)) {
            $out[] = $key;
        }
    }
    return $out;
}

/**
 * Every cell key a range covers.
 *
 * @param body {string} the range as written
 * @param sheetName {string} the sheet unqualified references belong to
 * @return {list of string} the keys
 */
func spanKeys(body as string, sheetName as string) {
    def out as list of string init [];
    def colon as int init rangeColonAt($body);
    if ($colon < 0) {
        def one as CellSpot init spotOf($body, $sheetName);
        if ($one.ok) {
            $out[] = cellKey($one.sheetName, $one.at);
        }
        return $out;
    }
    def leftHalf as string init strings.substring($body, 0, $colon);
    def rightHalf as string init strings.substring($body, $colon + 1, len($body));
    def from as CellSpot init spotOf($leftHalf, $sheetName);
    def to2 as CellSpot init spotOf($rightHalf, $from.sheetName);
    if (not $from.ok or not $to2.ok) {
        return $out;
    }
    def box as Area init Area{from: Ref{row: 0, col: 0}, to2: Ref{row: 0, col: 0}};
    def ok as bool init true;
    try {
        $box = area($from.at, $to2.at);
    } catch (e) {
        $ok = false;
    }
    if (not $ok or areaSize($box) > MAX_RANGE_CELLS) {
        return $out;
    }
    for (def r in $box.from.row..($box.to2.row + 1)) {
        for (def c in $box.from.col..($box.to2.col + 1)) {
            $out[] = cellKey($from.sheetName, Ref{row: $r, col: $c});
        }
    }
    return $out;
}

/**
 * Read one cell without ever materialising the sheet that holds it.
 *
 * `sheetByName($book, $name)` binds a whole `Sheet` to a local, and
 * Jennifer's value semantics deep-copy the cells map to do it - once per cell
 * read, which made every range quadratic: `SUM(A1:A5000)` took 18.5 s and
 * recalculating 4 000 formulas took 87 s. Walking the field chain and
 * indexing the map in place copies nothing. Measured over 3 000 reads:
 * 4 643 ms binding the sheet to a local, 2 336 ms passing it to a helper,
 * **15 ms** this way - 310x. Keep the chain inline: do not lift any part of
 * it into a local, and do not hand a `Sheet` or a `Workbook` to a helper on
 * this path. Passing the `Scope` itself is free, because nothing in the
 * callee binds its fields.
 *
 * A sheet that is not there reads as empty rather than failing; the callers
 * check `hasSheet` first where a missing sheet is a `#REF!`.
 *
 * @param book {Workbook} the workbook every reference reads from
 * @param sheetName {string} the sheet to read from
 * @param at {Ref} the cell
 * @return {Value} the cell's value, or empty when it holds nothing
 */
func cellInScope(book as Workbook, sheetName as string, at as Ref) {
    def key as string init cellRef($at);
    for (def i in 0..len($book.sheets)) {
        if ($book.sheets[$i].name == $sheetName) {
            if (maps.has($book.sheets[$i].cells, $key)) {
                return $book.sheets[$i].cells[$key];
            }
            return Value.Empty;
        }
    }
    return Value.Empty;
}

/**
 * Every value a range covers, row by row.
 *
 * @param body {string} the range as written
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what it can see
 * @return {list of Value} the values, empty when the range is unreadable
 */
func spanValues(body as string, book as Workbook, scope as Scope) {
    def out as list of Value init [];
    def colon as int init rangeColonAt($body);
    if ($colon < 0) {
        $out[] = evalCellRef($body, $book, $scope);
        return $out;
    }
    def leftHalf as string init strings.substring($body, 0, $colon);
    def rightHalf as string init strings.substring($body, $colon + 1, len($body));
    def halves as list of string init splitSheetRef($leftHalf);
    def sheetName as string init $halves[0];
    if ($sheetName == "") {
        $sheetName = $scope.sheetName;
    }
    # Each of the three refusals below returns the error as the span's only
    # value, so an aggregate over it propagates the error the way it would for
    # any other bad operand. Returning an empty span instead would make
    # `SUM` answer 0, and a plausible wrong number is worse than an error.
    if (not hasSheet($book, $sheetName)) {
        $out[] = Value.Err{code: ERR_REF};
        return $out;
    }
    def box as Area init Area{from: Ref{row: 0, col: 0}, to2: Ref{row: 0, col: 0}};
    def ok as bool init true;
    try {
        $box = area(parseRef($halves[1]), parseRef(splitSheetRef($rightHalf)[1]));
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        $out[] = Value.Err{code: ERR_REF};
        return $out;
    }
    if (areaSize($box) > MAX_RANGE_CELLS) {
        $out[] = Value.Err{code: ERR_NUM};
        return $out;
    }
    for (def r in $box.from.row..($box.to2.row + 1)) {
        for (def c in $box.from.col..($box.to2.col + 1)) {
            $out[] = evalCellAt($sheetName, Ref{row: $r, col: $c}, $book, $scope);
        }
    }
    return $out;
}

/**
 * How many cells one range in a formula may cover.
 *
 * `SUM(A1:XFD1048576)` is a legal expression and asks for 17 billion cells.
 * A range past this yields an error value rather than being walked.
 */
export def const MAX_RANGE_CELLS as int init 1000000;

/**
 * Work out one cell of a sheet by reference, following a formula.
 *
 * @param sheetName {string} the sheet
 * @param at {Ref} the cell
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what it can see
 * @return {Value} the value
 */
func evalCellAt(sheetName as string, at as Ref, book as Workbook, scope as Scope) {
    def key as string init cellKey($sheetName, $at);
    if (maps.has($scope.visiting, $key)) {
        return Value.Err{code: ERR_CIRCULAR};
    }
    def v as Value init cellInScope($book, $sheetName, $at);
    match ($v) {
        when Formula(f) {
            def inner as map of string to bool init $scope.visiting;
            $inner[$key] = true;
            return evalNested($f.source, $sheetName, $inner, $book, $scope);
        }
        else { return $v; }
    }
}

/**
 * Work out a prefix or postfix operator.
 *
 * @param symbol {string} the operator
 * @param parts {list of Expr} the single operand
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what it can see
 * @return {Value} the result, or an error value
 */
func evalUnary(symbol as string, parts as list of Expr, book as Workbook, scope as Scope) {
    if (len($parts) != 1) {
        return Value.Err{code: ERR_VALUE};
    }
    def operand as Value init evalExpr($parts[0], $book, $scope);
    if (isErrorValue($operand)) {
        return $operand;
    }
    def amount as float init 0.0;
    def ok as bool init true;
    try {
        $amount = asNumber($operand);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    match ($symbol) {
        when "-" { return Value.Number{amount: -$amount}; }
        when "+" { return Value.Number{amount: $amount}; }
        when "%" { return Value.Number{amount: $amount / 100.0}; }
        else { return Value.Err{code: ERR_VALUE}; }
    }
}

/**
 * Work out a binary operator.
 *
 * An error on either side propagates, which is the rule that makes a wrong
 * cell visible at the end of a chain instead of silently becoming a zero.
 *
 * @param symbol {string} the operator
 * @param parts {list of Expr} the two operands
 * @param book {Workbook} the workbook every reference reads from
 * @param scope {Scope} what it can see
 * @return {Value} the result, or an error value
 */
func evalBinary(symbol as string, parts as list of Expr, book as Workbook, scope as Scope) {
    if (len($parts) != 2) {
        return Value.Err{code: ERR_VALUE};
    }
    def left as Value init evalExpr($parts[0], $book, $scope);
    if (isErrorValue($left)) {
        return $left;
    }
    def right as Value init evalExpr($parts[1], $book, $scope);
    if (isErrorValue($right)) {
        return $right;
    }
    if ($symbol == "&") {
        return grownText(asString($left) + asString($right));
    }
    if (precedenceOf($symbol) == 1) {
        return compareValues($symbol, $left, $right);
    }
    return arithmetic($symbol, $left, $right);
}

/**
 * Work out an arithmetic operator.
 *
 * @param symbol {string} the operator
 * @param left {Value} the left operand
 * @param right {Value} the right operand
 * @return {Value} the result, or an error value
 */
func arithmetic(symbol as string, left as Value, right as Value) {
    def a as float init 0.0;
    def b as float init 0.0;
    def ok as bool init true;
    try {
        $a = asNumber($left);
        $b = asNumber($right);
    } catch (e) {
        $ok = false;
    }
    if (not $ok) {
        return Value.Err{code: ERR_VALUE};
    }
    match ($symbol) {
        when "+" { return guardedNumber($a + $b); }
        when "-" { return guardedNumber($a - $b); }
        when "*" { return guardedNumber($a * $b); }
        when "/" { return divide($a, $b); }
        when "^" { return power($a, $b); }
        else { return Value.Err{code: ERR_VALUE}; }
    }
}

/**
 * A number, unless the arithmetic overflowed.
 *
 * Jennifer raises on a non-finite float rather than producing one, and that
 * raise would abort a recalculation. `#NUM!` is the spreadsheet answer.
 *
 * @param amount {float} the result
 * @return {Value} the number, or `#NUM!`
 */
func guardedNumber(amount as float) {
    return Value.Number{amount: $amount};
}

/**
 * Divide, with the spreadsheet's answer for a zero divisor.
 *
 * @param a {float} the dividend
 * @param b {float} the divisor
 * @return {Value} the quotient, or `#DIV/0!`
 */
func divide(a as float, b as float) {
    if ($b == 0.0) {
        return Value.Err{code: ERR_DIV0};
    }
    def out as float init 0.0;
    try {
        $out = $a / $b;
    } catch (e) {
        return Value.Err{code: ERR_NUM};
    }
    return Value.Number{amount: $out};
}

/**
 * Raise to a power, with the spreadsheet's answers for the awkward cases.
 *
 * @param a {float} the base
 * @param b {float} the exponent
 * @return {Value} the result, or an error value
 */
func power(a as float, b as float) {
    # 0 to a negative power is `#NUM!`, not `#DIV/0!`: verified against both
    # LibreOffice 26.8 and Gnumeric, which agree on `#NUM!` for `0^-1`.
    if ($a == 0.0 and $b < 0.0) {
        return Value.Err{code: ERR_NUM};
    }
    def out as float init 0.0;
    try {
        $out = math.pow($a, $b);
    } catch (e) {
        return Value.Err{code: ERR_NUM};
    }
    return Value.Number{amount: $out};
}

/**
 * Compare two values.
 *
 * A spreadsheet orders a number before text and text before a boolean, so
 * `1 < "a"` is true. Within a kind the comparison is the natural one; text
 * compares case-insensitively, as in every application.
 *
 * @param symbol {string} the comparison
 * @param left {Value} the left operand
 * @param right {Value} the right operand
 * @return {Value} the result, or an error value
 */
func compareValues(symbol as string, left as Value, right as Value) {
    def order as int init compareOrder($left, $right);
    match ($symbol) {
        when "=" { return Value.Bool{flag: $order == 0}; }
        when "<>" { return Value.Bool{flag: $order != 0}; }
        when "<" { return Value.Bool{flag: $order < 0}; }
        when ">" { return Value.Bool{flag: $order > 0}; }
        when "<=" { return Value.Bool{flag: $order <= 0}; }
        when ">=" { return Value.Bool{flag: $order >= 0}; }
        else { return Value.Err{code: ERR_VALUE}; }
    }
}

/**
 * Which of two values sorts first.
 *
 * @param left {Value} the left operand
 * @param right {Value} the right operand
 * @return {int} negative, zero or positive
 */
func compareOrder(left as Value, right as Value) {
    # A blank cell takes the class of whatever it is compared against, so both
    # `E1=0` and `E1=""` are TRUE in LibreOffice and Gnumeric. Without this
    # coercion the ranks differ and an empty cell equals neither.
    def leftSide as Value init blankAs($left, $right);
    def rightSide as Value init blankAs($right, $left);
    def leftRank as int init compareRank($leftSide);
    def rightRank as int init compareRank($rightSide);
    if ($leftRank != $rightRank) {
        return $leftRank - $rightRank;
    }
    if ($leftRank == 1) {
        return compareFloats(numberOrZero($leftSide), numberOrZero($rightSide));
    }
    if ($leftRank == 2) {
        def a as string init strings.lower(asString($leftSide));
        def b as string init strings.lower(asString($rightSide));
        if ($a == $b) {
            return 0;
        }
        if ($a < $b) {
            return -1;
        }
        return 1;
    }
    if ($leftRank == 3) {
        return compareFloats(numberOrZero($leftSide), numberOrZero($rightSide));
    }
    return 0;
}

/**
 * Give a blank value the class of the value it is being compared against.
 *
 * An empty cell is the one value with no class of its own: against a number it
 * reads as 0, against text as the empty string, against a boolean as FALSE.
 *
 * @param v {Value} the value to coerce
 * @param against {Value} the other side of the comparison
 * @return {Value} `v` unchanged, or the zero of `against`'s class
 */
func blankAs(v as Value, against as Value) {
    def isBlank as bool init false;
    match ($v) {
        when Empty { $isBlank = true; }
        else { $isBlank = false; }
    }
    if (not $isBlank) {
        return $v;
    }
    match ($against) {
        when Text(t) { return Value.Text{body: ""}; }
        when Bool(b) { return Value.Bool{flag: false}; }
        else { return $v; }
    }
}

/**
 * Which kind a value is, for ordering.
 *
 * Empty sorts with whatever it is compared against, so it is given the same
 * rank as a number: an empty cell behaves as zero in a comparison, which is
 * what a spreadsheet does.
 *
 * @param v {Value} the value
 * @return {int} 1 for a number or empty, 2 for text, 3 for a boolean
 */
func compareRank(v as Value) {
    match ($v) {
        when Number(n) { return 1; }
        when Empty { return 1; }
        when Stamp(st) { return 1; }
        when Text(t) { return 2; }
        when Formula(f) { return 2; }
        when Bool(b) { return 3; }
        when Err(e) { return 4; }
    }
}

/**
 * A value's number, or zero when it has none.
 *
 * @param v {Value} the value
 * @return {float} the number
 */
func numberOrZero(v as Value) {
    def out as float init 0.0;
    try {
        $out = asNumber($v);
    } catch (e) {
        return 0.0;
    }
    return $out;
}

/**
 * Compare two floats.
 *
 * @param a {float} the first
 * @param b {float} the second
 * @return {int} negative, zero or positive
 */
func compareFloats(a as float, b as float) {
    if ($a == $b) {
        return 0;
    }
    if ($a < $b) {
        return -1;
    }
    return 1;
}
