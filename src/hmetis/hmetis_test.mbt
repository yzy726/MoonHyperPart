///|
test "valid/hmetis unweighted and one based pins" {
  let g = @hmetis.parse("2 3\n1 2 3\n2\n").unwrap()
  assert_eq(g.pin_at(0, 0), 0)
  assert_eq(g.pin_at(0, 2), 2)
  assert_eq(g.edge_weight(1), 1L)
  assert_eq(g.total_vertex_weight(), 3L)
}

///|
test "valid/hmetis edge weights 01" {
  let g = @hmetis.parse("1 3 01\n42 1 3\n").unwrap()
  assert_eq(g.edge_weight(0), 42L)
  assert_eq(g.vertex_weight(1), 1L)
}

///|
test "valid/hmetis vertex weights 10" {
  let g = @hmetis.parse("1 3 10\n1 3\n2\n3\n4\n").unwrap()
  assert_eq(g.total_vertex_weight(), 9L)
  assert_eq(g.vertex_weight(2), 4L)
}

///|
test "valid/hmetis both weights 11" {
  let g = @hmetis.parse("1 2 11\n9 1 2\n3\n4").unwrap()
  assert_eq(g.total_vertex_weight(), 7L)
  assert_eq(g.edge_weight(0), 9L)
}

///|
test "valid/hmetis 00 comments CRLF and tabs" {
  let g = @hmetis.parse("% top\r\n1\t2 00\r\n  % comment\r\n1\t2\r\n% end\r\n").unwrap()
  assert_eq(g.pin_count(), 2)
}

///|
test "edge/hmetis isolated vertices no edges" {
  let g = @hmetis.parse("0 2\n").unwrap()
  assert_eq(g.degree(1), 0)
}

///|
test "invalid/hmetis missing header" {
  assert_true(
    @hmetis.parse("% only a comment\n") is Err({ code: "header", .. }),
  )
}

///|
test "invalid/hmetis incomplete header" {
  assert_true(@hmetis.parse("1\n") is Err({ code: "header", line: 1, .. }))
}

///|
test "invalid/hmetis multiple constraints unsupported" {
  assert_true(
    @hmetis.parse("1 2 11 2\n1 1 2\n1 2\n1 2\n") is Err({ code: "header", .. }),
  )
}

///|
test "invalid/hmetis unknown weight mode" {
  assert_true(
    @hmetis.parse("1 2 2\n1 2\n") is Err({ code: "format", line: 1, .. }),
  )
}

///|
test "invalid/hmetis nondecimal integer" {
  assert_true(
    @hmetis.parse("1 0x2\n1\n") is Err({ code: "integer", line: 1, .. }),
  )
}

///|
test "invalid/hmetis duplicate source line" {
  assert_true(
    @hmetis.parse("% before\n1 2\n% middle\n1 2 1\n")
    is Err({ code: "duplicate_pin", line: 4, .. }),
  )
}

///|
test "invalid/hmetis zero pin" {
  assert_true(
    @hmetis.parse("1 2\n0 1\n") is Err({ code: "pin_range", line: 2, .. }),
  )
}

///|
test "invalid/hmetis out of range pin" {
  assert_true(
    @hmetis.parse("1 2\n1 3\n") is Err({ code: "pin_range", line: 2, .. }),
  )
}

///|
test "invalid/hmetis negative pin" {
  assert_true(
    @hmetis.parse("1 2\n-1 2\n") is Err({ code: "integer", line: 2, .. }),
  )
}

///|
test "invalid/hmetis zero edge weight" {
  assert_true(
    @hmetis.parse("1 2 1\n0 1 2\n") is Err({ code: "edge_weight", line: 2, .. }),
  )
}

///|
test "invalid/hmetis zero vertex weight" {
  assert_true(
    @hmetis.parse("0 2 10\n0\n1\n")
    is Err({ code: "vertex_weight", line: 2, .. }),
  )
}

///|
test "invalid/hmetis truncated edges" {
  assert_true(@hmetis.parse("2 2\n1 2\n") is Err({ code: "truncated", .. }))
}

///|
test "invalid/hmetis truncated vertex weights" {
  assert_true(@hmetis.parse("0 2 10\n1\n") is Err({ code: "truncated", .. }))
}

///|
test "invalid/hmetis extra data" {
  assert_true(
    @hmetis.parse("0 2\n1 2\n") is Err({ code: "extra_data", line: 2, .. }),
  )
}

///|
test "invalid/hmetis empty edge" {
  assert_true(
    @hmetis.parse("1 2\n\n") is Err({ code: "empty_edge", line: 2, .. }),
  )
}

///|
test "invalid/hmetis inline comment" {
  assert_true(
    @hmetis.parse("1 2\n1 2 % inline\n")
    is Err({ code: "integer", line: 2, .. }),
  )
}

///|
test "invalid/hmetis multiple vertex weights" {
  assert_true(
    @hmetis.parse("0 1 10\n1 2\n")
    is Err({ code: "vertex_weight", line: 2, .. }),
  )
}

///|
test "edge/hmetis integer overflow" {
  assert_true(
    @hmetis.parse("1 2 1\n9223372036854775808 1 2\n")
    is Err({ code: "overflow", line: 2, .. }),
  )
}

///|
test "edge/hmetis sum overflow source line" {
  assert_true(
    @hmetis.parse("0 2 10\n9223372036854775807\n1\n")
    is Err({ code: "overflow", line: 3, .. }),
  )
}

///|
test "edge/hmetis resource limits" {
  assert_true(
    @hmetis.parse("0 999999999999\n") is Err({ code: "limit", line: 1, .. }),
  )
  let limits : @model.Limits = {
    ..@model.Limits::default(),
    max_text_bytes: 5,
  }
  assert_true(
    @hmetis.parse("0 2\n% 中文", limits~) is Err({ code: "limit", .. }),
  )
  let pins : @model.Limits = { ..@model.Limits::default(), max_pins: 1, }
  assert_true(
    @hmetis.parse("1 2\n1 2\n", limits=pins)
    is Err({ code: "limit", line: 2, .. }),
  )
}
