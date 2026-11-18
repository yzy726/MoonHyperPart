///|
fn tiny() -> @MoonHyperPart.Hypergraph {
  @MoonHyperPart.parse("3 6 1\n10 1 2 3\n10 4 5 6\n1 3 4\n").unwrap()
}

///|
test "valid/api tiny optimum from library entry point" {
  let options : @MoonHyperPart.Options = {
    ..@MoonHyperPart.Options::default(),
    starts: 1,
  }
  let result = @MoonHyperPart.partition(tiny(), [3L, 3L], options~).unwrap()
  assert_eq(result.metrics.cut_net, 1L)
  assert_eq(result.metrics.part_weights, (3L, 3L))
  assert_true(result.metrics.cut_net < result.initial_cut)
  assert_eq(
    @MoonHyperPart.verify(tiny(), result.assignment, [3L, 3L]).unwrap().cut_net,
    1L,
  )
}

///|
test "valid/api reproducible assignment bytes and JSON" {
  let a = @MoonHyperPart.partition(tiny(), [3L, 3L]).unwrap()
  let b = @MoonHyperPart.partition(tiny(), [3L, 3L]).unwrap()
  assert_eq(
    @MoonHyperPart.partition_text(tiny(), a.assignment, [3L, 3L]).unwrap(),
    @MoonHyperPart.partition_text(tiny(), b.assignment, [3L, 3L]).unwrap(),
  )
  assert_eq(
    @MoonHyperPart.result_json(tiny(), a),
    @MoonHyperPart.result_json(tiny(), b),
  )
}

///|
test "invalid/api construction failure propagates" {
  let g = @MoonHyperPart.build([8L, 7L, 6L, 5L, 4L], [], []).unwrap()
  let options : @MoonHyperPart.Options = {
    ..@MoonHyperPart.Options::default(),
    starts: 1,
    search_nodes: 0,
  }
  assert_true(
    @MoonHyperPart.partition(g, [15L, 15L], options~)
    is Err({ kind: "search_exhausted", .. }),
  )
}

///|
test "edge/api refinement limit returns a complete verified solution" {
  let refinement : @MoonHyperPart.RefinementBudget = {
    ..@MoonHyperPart.RefinementBudget::default(),
    max_moves: 0,
  }
  let options : @MoonHyperPart.Options = {
    ..@MoonHyperPart.Options::default(),
    starts: 1,
    refinement,
  }
  let result = @MoonHyperPart.partition(tiny(), [3L, 3L], options~).unwrap()
  assert_true(result.refinement.budget_limited)
  assert_true(
    @MoonHyperPart.verify(tiny(), result.assignment, [3L, 3L]) is Ok(_),
  )
}

///|
test "valid/api JSON seed work bounds and objective" {
  let options : @MoonHyperPart.Options = {
    ..@MoonHyperPart.Options::default(),
    seed: 726U,
    starts: 1,
  }
  let result = @MoonHyperPart.partition(tiny(), [3L, 3L], options~).unwrap()
  let json = @json.parse(@MoonHyperPart.result_json(tiny(), result))
  assert_true(
    json is { "cut_net": "1", "run": { "seed": 726, "starts": 1, .. }, .. },
  )
}

///|
test "valid/api small graph oracle and feasible outputs" {
  for sample in 0..<8 {
    let edges = [[0, 1, 2], [2, 3, 4], [0, 4, 5], [sample % 6]]
    let g = @MoonHyperPart.build([1L, 1L, 1L, 1L, 1L, 1L], edges, [
      1L,
      3L,
      (sample + 1).to_int64(),
      5L,
    ]).unwrap()
    let mut optimum = 9223372036854775807L
    for mask in 0..<64 {
      let parts = Array::makei(6, fn(v) { (mask >> v) & 1 })
      if @MoonHyperPart.verify(g, parts, [3L, 3L]) is Ok(m) {
        if m.cut_net < optimum {
          optimum = m.cut_net
        }
      }
    }
    let result = @MoonHyperPart.partition(g, [3L, 3L]).unwrap()
    assert_true(result.metrics.cut_net >= optimum)
    assert_true(result.metrics.cut_net <= result.initial_cut)
  }
}
