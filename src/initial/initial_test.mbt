///|
fn graph(weights : Array[Int64]) -> @model.Hypergraph {
  @model.build(weights, [], []).unwrap()
}

///|
test "valid/initial deterministic balanced construction" {
  let g = graph([1L, 1L, 1L, 1L, 1L, 1L])
  let a = @initial.construct(g, [3L, 3L], seed=42U, starts=4, search_nodes=100).unwrap()
  let b = @initial.construct(g, [3L, 3L], seed=42U, starts=4, search_nodes=100).unwrap()
  assert_eq(a.assignment, b.assignment)
  assert_eq(a.metrics.part_weights, (3L, 3L))
  assert_true(@metrics.verify(g, a.assignment, [3L, 3L]) is Ok(_))
}

///|
test "valid/initial bounded repair finds missed greedy packing" {
  let g = graph([8L, 7L, 6L, 5L, 4L])
  let result = @initial.construct(
    g,
    [15L, 15L],
    seed=1U,
    starts=1,
    search_nodes=100,
  ).unwrap()
  assert_eq(result.metrics.part_weights, (15L, 15L))
  assert_true(result.search_nodes > 0)
}

///|
test "invalid/initial repair budget exhaustion is search failure" {
  let g = graph([8L, 7L, 6L, 5L, 4L])
  assert_true(
    @initial.construct(g, [15L, 15L], seed=1U, starts=1, search_nodes=0)
    is Err({ kind: "search_exhausted", .. }),
  )
}

///|
test "invalid/initial infeasible heavy vertex proved" {
  assert_true(
    @initial.construct(
      graph([9L, 1L]),
      [5L, 5L],
      seed=0U,
      starts=1,
      search_nodes=100,
    )
    is Err({ kind: "impossible", .. }),
  )
}

///|
test "invalid/initial insufficient total capacity proved" {
  assert_true(
    @initial.construct(
      graph([2L, 2L, 2L]),
      [2L, 3L],
      seed=0U,
      starts=1,
      search_nodes=100,
    )
    is Err({ kind: "impossible", .. }),
  )
}

///|
test "invalid/initial one vertex cannot make two nonempty parts" {
  assert_true(
    @initial.construct(
      graph([1L]),
      [1L, 1L],
      seed=0U,
      starts=1,
      search_nodes=100,
    )
    is Err({ kind: "impossible", .. }),
  )
}

///|
test "invalid/initial failed packing does not claim impossibility" {
  assert_true(
    @initial.construct(
      graph([2L, 2L, 2L]),
      [3L, 3L],
      seed=0U,
      starts=2,
      search_nodes=100,
    )
    is Err({ kind: "search_exhausted", .. }),
  )
}

///|
test "invalid/initial options checked" {
  let g = graph([1L, 1L])
  assert_true(
    @initial.construct(g, [1L, 1L], seed=0U, starts=0, search_nodes=1)
    is Err({ kind: "options", .. }),
  )
  assert_true(
    @initial.construct(g, [1L, 1L], seed=0U, starts=1, search_nodes=-1)
    is Err({ kind: "options", .. }),
  )
  assert_true(
    @initial.construct(g, [1L], seed=0U, starts=1, search_nodes=1)
    is Err({ kind: "options", .. }),
  )
}

///|
test "edge/initial maximum capacities avoid sum overflow" {
  let a = @initial.construct(
    graph([1L, 1L]),
    [9223372036854775807L, 9223372036854775807L],
    seed=0U,
    starts=1,
    search_nodes=1,
  ).unwrap()
  assert_eq(a.metrics.part_sizes, (1, 1))
}

///|
test "valid/initial multiple starts keep best feasible candidate" {
  let g = @model.build(
    [1L, 1L, 1L, 1L, 1L, 1L],
    [[0, 1, 2], [3, 4, 5], [2, 3]],
    [10L, 10L, 1L],
  ).unwrap()
  let a = @initial.construct(g, [3L, 3L], seed=123U, starts=1, search_nodes=0).unwrap()
  let b = @initial.construct(g, [3L, 3L], seed=123U, starts=8, search_nodes=0).unwrap()
  assert_true(b.metrics.cut_net <= a.metrics.cut_net)
  assert_eq(b.starts_tried, 8)
}

///|
test "valid/initial asymmetric capacities" {
  let g = graph([4L, 2L, 1L])
  let r = @initial.construct(g, [4L, 3L], seed=5U, starts=4, search_nodes=100).unwrap()
  assert_eq(r.metrics.part_weights, (4L, 3L))
}
