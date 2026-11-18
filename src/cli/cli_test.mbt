///|
test "valid/cli help and inspection arguments" {
  assert_eq(@cli.parse_args([]).unwrap().action, "help")
  assert_eq(@cli.parse_args(["partition", "--help"]).unwrap().action, "help")
  assert_eq(@cli.parse_args(["inspect", "tiny.hgr"]).unwrap().input, "tiny.hgr")
}

///|
test "valid/cli partition explicit integer capacities" {
  let command = @cli.parse_args([
    "partition", "tiny.hgr", "--output", "tiny.part", "--capacities", "3,3", "--seed",
    "726", "--starts", "1",
  ]).unwrap()
  assert_eq(command.output, Some("tiny.part"))
  assert_eq(command.capacities, Some([3L, 3L]))
  assert_eq(command.options.seed, 726U)
}

///|
test "valid/cli verify and decimal imbalance" {
  let command = @cli.parse_args([
    "verify", "g.hgr", "g.part", "--imbalance", "0.035",
  ]).unwrap()
  assert_eq(command.partition_file, Some("g.part"))
  assert_eq(command.imbalance_permille, 35)
}

///|
test "valid/cli complete work limits" {
  let command = @cli.parse_args([
    "partition", "g.hgr", "--output", "g.part", "--search-nodes", "0", "--passes",
    "2", "--moves", "4", "--swap-trials", "10", "--candidates", "20",
  ]).unwrap()
  assert_eq(command.options.search_nodes, 0)
  assert_eq(command.options.refinement.max_moves, 4)
  assert_eq(command.options.refinement.max_swap_trials, 10)
}

///|
test "valid/cli configurable resource limits" {
  let command = @cli.parse_args([
    "inspect", "g.hgr", "--max-vertices", "10", "--max-edges", "20", "--max-pins",
    "50", "--max-input-bytes", "1000",
  ]).unwrap()
  assert_eq(command.limits.max_vertices, 10)
  assert_eq(command.limits.max_pins, 50)
}

///|
test "invalid/cli unknown command and unknown flag" {
  assert_true(@cli.parse_args(["unknown", "g.hgr"]) is Err(_))
  assert_true(@cli.parse_args(["inspect", "g.hgr", "--k", "4"]) is Err(_))
}

///|
test "invalid/cli missing output input or option value" {
  assert_true(@cli.parse_args(["partition", "g.hgr"]) is Err(_))
  assert_true(@cli.parse_args(["inspect"]) is Err(_))
  assert_true(@cli.parse_args(["partition", "g.hgr", "--output"]) is Err(_))
}

///|
test "invalid/cli duplicate flags and positional arguments" {
  assert_true(@cli.parse_args(["inspect", "a", "b"]) is Err(_))
  assert_true(
    @cli.parse_args([
      "partition", "g", "--output", "p", "--seed", "1", "--seed", "2",
    ])
    is Err(_),
  )
}

///|
test "invalid/cli seed overflow and negative budget" {
  assert_true(
    @cli.parse_args(["partition", "g", "--output", "p", "--seed", "4294967296"])
    is Err(_),
  )
  assert_true(
    @cli.parse_args(["partition", "g", "--output", "p", "--moves", "-1"])
    is Err(_),
  )
}

///|
test "invalid/cli tolerance precision and range" {
  assert_true(
    @cli.parse_args(["verify", "g", "p", "--imbalance", "0.0001"]) is Err(_),
  )
  assert_true(
    @cli.parse_args(["verify", "g", "p", "--imbalance", "1.001"]) is Err(_),
  )
  assert_true(
    @cli.parse_args(["verify", "g", "p", "--imbalance", "NaN"]) is Err(_),
  )
}

///|
test "invalid/cli malformed capacities and conflicting modes" {
  assert_true(
    @cli.parse_args(["verify", "g", "p", "--capacities", "3"]) is Err(_),
  )
  assert_true(
    @cli.parse_args(["verify", "g", "p", "--capacities", "3,0"]) is Err(_),
  )
  assert_true(
    @cli.parse_args([
      "verify", "g", "p", "--capacities", "3,3", "--imbalance", "0.03",
    ])
    is Err(_),
  )
}

///|
test "invalid/cli rejects output aliases spelled identically" {
  assert_true(@cli.parse_args(["partition", "g", "--output", "g"]) is Err(_))
  assert_true(
    @cli.parse_args(["partition", "g", "--output", "p", "--report", "p"])
    is Err(_),
  )
}

///|
test "invalid/cli rejects solver flags on inspect" {
  assert_true(@cli.parse_args(["inspect", "g", "--seed", "1"]) is Err(_))
}
