///|
fn tiny() -> @model.Hypergraph {
  @model.build([1L, 1L, 1L, 1L, 1L, 1L], [[0, 1, 2], [3, 4, 5], [2, 3]], [
    10L, 10L, 1L,
  ]).unwrap()
}

///|
test "valid/metrics hand computed tiny optimum" {
  let m = @metrics.verify(tiny(), [0, 0, 0, 1, 1, 1], [3L, 3L]).unwrap()
  assert_eq(m.cut_net, 1L)
  assert_eq(m.connectivity, 1L)
  assert_eq(m.part_weights, (3L, 3L))
  assert_eq(m.part_sizes, (3, 3))
  assert_eq(m.max_to_average, 1.0)
}

///|
test "valid/metrics exact uniform capacity rounding" {
  assert_eq(@metrics.uniform_capacity(6L, 0).unwrap(), 3L)
  assert_eq(@metrics.uniform_capacity(5L, 0).unwrap(), 3L)
  assert_eq(@metrics.uniform_capacity(100L, 30).unwrap(), 52L)
  assert_eq(@metrics.uniform_capacity(3L, 1000).unwrap(), 3L)
}

///|
test "edge/metrics capacity near Int64 maximum" {
  assert_eq(
    @metrics.uniform_capacity(9223372036854775807L, 0).unwrap(),
    4611686018427387904L,
  )
  assert_eq(
    @metrics.uniform_capacity(9223372036854775807L, 1000).unwrap(),
    9223372036854775807L,
  )
}

///|
test "invalid/metrics negative and excessive tolerance" {
  assert_true(@metrics.uniform_capacity(5L, -1) is Err(_))
  assert_true(@metrics.uniform_capacity(5L, 1001) is Err(_))
  assert_true(@metrics.uniform_capacity(0L, 30) is Err(_))
}

///|
test "invalid/metrics assignment too short" {
  assert_true(
    @metrics.verify(tiny(), [0, 1], [3L, 3L])
    is Err({ code: "assignment_count", .. }),
  )
}

///|
test "invalid/metrics assignment too long" {
  assert_true(
    @metrics.verify(tiny(), [0, 0, 0, 1, 1, 1, 1], [4L, 4L])
    is Err({ code: "assignment_count", .. }),
  )
}

///|
test "invalid/metrics partition index range" {
  assert_true(
    @metrics.verify(tiny(), [0, 0, 0, 1, 1, 2], [4L, 4L])
    is Err({ code: "partition_id", .. }),
  )
  assert_true(
    @metrics.verify(tiny(), [0, 0, 0, 1, 1, -1], [4L, 4L])
    is Err({ code: "partition_id", .. }),
  )
}

///|
test "invalid/metrics nonempty partitions required" {
  assert_true(
    @metrics.verify(tiny(), [0, 0, 0, 0, 0, 0], [6L, 6L])
    is Err({ code: "empty_partition", .. }),
  )
}

///|
test "invalid/metrics capacity violation" {
  assert_true(
    @metrics.verify(tiny(), [0, 0, 0, 0, 1, 1], [3L, 3L])
    is Err({ code: "capacity", .. }),
  )
}

///|
test "invalid/metrics malformed capacities" {
  assert_true(
    @metrics.verify(tiny(), [0, 0, 0, 1, 1, 1], [3L])
    is Err({ code: "capacity_count", .. }),
  )
  assert_true(
    @metrics.verify(tiny(), [0, 0, 0, 1, 1, 1], [0L, 6L])
    is Err({ code: "capacity", .. }),
  )
}

///|
test "edge/metrics singleton edges contribute zero" {
  let g = @model.build([2L, 1L], [[0], [1]], [99L, 7L]).unwrap()
  let m = @metrics.verify(g, [0, 1], [2L, 2L]).unwrap()
  assert_eq(m.cut_net, 0L)
  assert_eq(m.max_to_average, 4.0 / 3.0)
}

///|
test "valid/metrics asymmetric weighted capacities" {
  let g = @model.build([4L, 2L, 1L], [[0, 1, 2]], [9L]).unwrap()
  let m = @metrics.verify(g, [0, 1, 1], [4L, 3L]).unwrap()
  assert_eq(m.part_weights, (4L, 3L))
  assert_eq(m.cut_net, 9L)
}

///|
test "valid/metrics exhaustive tiny assignments oracle" {
  let g = tiny()
  let mut best = 9223372036854775807L
  let mut feasible = 0
  for mask in 0..<64 {
    let parts = Array::make(6, 0)
    for v in 0..<6 {
      parts[v] = (mask >> v) & 1
    }
    match @metrics.verify(g, parts, [3L, 3L]) {
      Ok(m) => {
        feasible += 1
        let mut oracle = 0L
        if parts[0] != parts[1] || parts[1] != parts[2] {
          oracle += 10L
        }
        if parts[3] != parts[4] || parts[4] != parts[5] {
          oracle += 10L
        }
        if parts[2] != parts[3] {
          oracle += 1L
        }
        assert_eq(m.cut_net, oracle)
        assert_eq(m.connectivity, oracle)
        if oracle < best {
          best = oracle
        }
      }
      Err(_) => ()
    }
  }
  assert_eq(feasible, 20)
  assert_eq(best, 1L)
}

///|
test "valid/metrics renumbering edge permutation and scaling" {
  let original = @metrics.verify(tiny(), [0, 0, 0, 1, 1, 1], [3L, 3L]).unwrap()
  let g = @model.build(
    [2L, 2L, 2L, 2L, 2L, 2L],
    [[3, 2], [5, 4, 3], [2, 1, 0]],
    [2L, 20L, 20L],
  ).unwrap()
  let m = @metrics.verify(g, [1, 1, 1, 0, 0, 0], [6L, 6L]).unwrap()
  assert_eq(m.cut_net, original.cut_net * 2L)
  assert_eq(m.part_weights, (6L, 6L))
}
