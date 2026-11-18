///|
test "valid/report partition roundtrip" {
  let g = @model.build([1L, 1L], [[0, 1]], [4L]).unwrap()
  let text = @report.partition_text(g, [0, 1], [1L, 1L]).unwrap()
  assert_eq(text, "0\n1\n")
  assert_eq(@report.parse_partition(text, 2).unwrap(), [0, 1])
}

///|
test "valid/report partition without final newline and CRLF" {
  assert_eq(@report.parse_partition("0\r\n1", 2).unwrap(), [0, 1])
}

///|
test "invalid/report missing assignment" {
  assert_true(
    @report.parse_partition("0\n", 2) is Err({ code: "assignment_count", .. }),
  )
}

///|
test "invalid/report extra assignment" {
  assert_true(
    @report.parse_partition("0\n1\n0\n", 2)
    is Err({ code: "assignment_count", .. }),
  )
}

///|
test "invalid/report malformed ID and empty interior line" {
  assert_true(
    @report.parse_partition("0\n2\n", 2)
    is Err({ code: "partition_id", line: 2, .. }),
  )
  assert_true(
    @report.parse_partition("0\n\n1\n", 3)
    is Err({ code: "partition_id", line: 2, .. }),
  )
}

///|
test "invalid/report export requires independent feasibility" {
  let g = @model.build([1L, 1L], [], []).unwrap()
  assert_true(
    @report.partition_text(g, [0, 0], [2L, 2L])
    is Err({ code: "empty_partition", .. }),
  )
}

///|
test "edge/report input resource bound" {
  let limits : @model.Limits = {
    ..@model.Limits::default(),
    max_text_bytes: 3,
  }
  assert_true(
    @report.parse_partition("0\n1\n", 2, limits~) is Err({ code: "limit", .. }),
  )
}

///|
test "valid/report JSON preserves full Int64 decimal weights" {
  let g = @model.build([9007199254740993L, 1L], [[0, 1]], [9223372036854775807L]).unwrap()
  let m = @metrics.verify(g, [0, 1], [9007199254740993L, 1L]).unwrap()
  let text = @report.metrics_json(g, m)
  let json = @json.parse(text)
  assert_true(
    json
    is {
      "cut_net": "9223372036854775807",
      "part_weights": ["9007199254740993", "1"],
      ..
    },
  )
}

///|
test "valid/report inspection and errors are valid JSON" {
  let g = @model.build([1L, 1L], [], []).unwrap()
  assert_true(
    @json.parse(@report.inspect_json(g)) is { "vertices": 2, "edges": 0, .. },
  )
  let error : @model.InputError = {
    code: "input",
    line: 2,
    message: "quoted \"path\"\nnewline",
  }
  assert_true(
    @json.parse(@report.error_json(error))
    is { "status": "error", "message": "quoted \"path\"\nnewline", .. },
  )
}
