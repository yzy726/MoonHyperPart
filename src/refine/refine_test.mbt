///|
fn tiny() -> @model.Hypergraph {
  @model.build([1L, 1L, 1L, 1L, 1L, 1L], [[0, 1, 2], [3, 4, 5], [2, 3]], [
    10L, 10L, 1L,
  ]).unwrap()
}

///|
test "valid/refine strict balance swap reaches tiny optimum" {
  let r = @refine.refine(tiny(), [0, 1, 0, 1, 0, 1], [3L, 3L]).unwrap()
  assert_eq(r.initial_cut, 21L)
  assert_eq(r.metrics.cut_net, 1L)
  assert_eq(r.metrics.part_weights, (3L, 3L))
  assert_true(r.swaps > 0)
}

///|
test "valid/refine single vertex improvement" {
  let g = @model.build([1L, 1L, 1L, 1L], [[0, 1], [2, 3]], [10L, 1L]).unwrap()
  let r = @refine.refine(g, [0, 1, 1, 1], [3L, 3L]).unwrap()
  assert_eq(r.metrics.cut_net, 0L)
  assert_true(r.moves > 0)
}

///|
test "valid/refine best prefix rolls back worsening moves" {
  let r = @refine.refine(tiny(), [0, 0, 0, 1, 1, 1], [3L, 3L]).unwrap()
  assert_eq(r.metrics.cut_net, 1L)
  assert_true(r.rolled_back > 0)
}

///|
test "valid/refine owns assignment and repeats exactly" {
  let parts = [0, 1, 0, 1, 0, 1]
  let a = @refine.refine(tiny(), parts, [3L, 3L]).unwrap()
  let b = @refine.refine(tiny(), parts, [3L, 3L]).unwrap()
  assert_eq(parts, [0, 1, 0, 1, 0, 1])
  assert_eq(a.assignment, b.assignment)
  assert_eq(a.moves, b.moves)
}

///|
test "edge/refine zero moves retains feasible initial solution" {
  let budget : @refine.RefinementBudget = {
    ..@refine.RefinementBudget::default(),
    max_moves: 0,
  }
  let r = @refine.refine(tiny(), [0, 1, 0, 1, 0, 1], [3L, 3L], budget~).unwrap()
  assert_eq(r.metrics.cut_net, 21L)
  assert_eq(r.moves, 0)
  assert_true(r.budget_limited)
}

///|
test "edge/refine candidate budget bounds work" {
  let budget : @refine.RefinementBudget = {
    ..@refine.RefinementBudget::default(),
    max_candidates: 1,
    max_swap_trials: 0,
  }
  let r = @refine.refine(tiny(), [0, 1, 0, 1, 0, 1], [3L, 3L], budget~).unwrap()
  assert_true(r.budget_limited)
  assert_true(r.metrics.cut_net <= r.initial_cut)
}

///|
test "edge/refine disabled swaps leave strict balance unchanged" {
  let budget : @refine.RefinementBudget = {
    ..@refine.RefinementBudget::default(),
    max_swap_trials: 0,
  }
  let r = @refine.refine(tiny(), [0, 1, 0, 1, 0, 1], [3L, 3L], budget~).unwrap()
  assert_eq(r.metrics.cut_net, 21L)
}

///|
test "invalid/refine rejects infeasible starting assignment" {
  assert_true(
    @refine.refine(tiny(), [0, 0, 0, 0, 0, 1], [3L, 3L])
    is Err({ kind: "validation", .. }),
  )
}

///|
test "invalid/refine negative work budget" {
  let budget : @refine.RefinementBudget = {
    ..@refine.RefinementBudget::default(),
    max_passes: -1,
  }
  assert_true(
    @refine.refine(tiny(), [0, 0, 0, 1, 1, 1], [3L, 3L], budget~)
    is Err({ kind: "options", .. }),
  )
}

///|
test "edge/refine weighted exchanges preserve capacities" {
  let g = @model.build([2L, 2L, 1L, 1L], [[0, 2], [1, 3]], [8L, 9L]).unwrap()
  let r = @refine.refine(g, [0, 1, 1, 0], [3L, 3L]).unwrap()
  assert_eq(r.metrics.cut_net, 0L)
  assert_eq(r.metrics.part_weights, (3L, 3L))
}

///|
test "edge/refine maximum objective avoids gain overflow" {
  let g = @model.build([1L, 1L, 1L, 1L], [[0, 1], [2, 3]], [
    9223372036854775806L, 1L,
  ]).unwrap()
  let r = @refine.refine(g, [0, 1, 0, 1], [2L, 2L]).unwrap()
  assert_eq(r.metrics.cut_net, 0L)
}

///|
test "valid/refine all feasible small assignments never worsen" {
  let g = @model.build([1L, 1L, 1L, 1L], [[0, 1, 2], [1, 3], [0]], [5L, 3L, 7L]).unwrap()
  for mask in 1..<15 {
    let parts = Array::makei(4, fn(v) { (mask >> v) & 1 })
    let before = @metrics.verify(g, parts, [3L, 3L]).unwrap()
    let r = @refine.refine(g, parts, [3L, 3L]).unwrap()
    let independent = @metrics.verify(g, r.assignment, [3L, 3L]).unwrap()
    assert_eq(r.metrics.cut_net, independent.cut_net)
    assert_true(independent.cut_net <= before.cut_net)
  }
}
