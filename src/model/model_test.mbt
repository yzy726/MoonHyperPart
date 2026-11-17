///|
fn graph() -> @model.Hypergraph {
  @model.build([1L, 2L, 3L, 4L], [[0, 1, 2], [2], [1, 3]], [10L, 7L, 2L]).unwrap()
}

///|
test "valid/model weighted sizes and totals" {
  let g = graph()
  assert_eq(g.vertex_count(), 4)
  assert_eq(g.edge_count(), 3)
  assert_eq(g.pin_count(), 6)
  assert_eq(g.total_vertex_weight(), 10L)
  assert_eq(g.total_edge_weight(), 19L)
  assert_eq(g.vertex_weight(1), 2L)
  assert_eq(g.edge_weight(0), 10L)
}

///|
test "valid/model bidirectional incidence" {
  let g = graph()
  assert_eq(g.edge_size(0), 3)
  assert_eq(g.pin_at(0, 2), 2)
  assert_eq(g.degree(1), 2)
  assert_eq(g.incident_at(1, 0), 0)
  assert_eq(g.incident_at(1, 1), 2)
  for e in 0..<g.edge_count() {
    for i in 0..<g.edge_size(e) {
      let v = g.pin_at(e, i)
      let mut found = false
      for j in 0..<g.degree(v) {
        if g.incident_at(v, j) == e {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
test "edge/model isolated vertices and singleton edges" {
  let g = @model.build([1L, 1L], [[0]], [2L]).unwrap()
  assert_eq(g.degree(1), 0)
  assert_eq(g.edge_size(0), 1)
  let empty = @model.build([1L, 1L], [], []).unwrap()
  assert_eq(empty.pin_count(), 0)
  assert_eq(empty.edge_count(), 0)
}

///|
test "valid/model owns defensive copies" {
  let weights = [2L, 3L]
  let pins = [0, 1]
  let edges = [pins]
  let ew = [4L]
  let g = @model.build(weights, edges, ew).unwrap()
  weights[0] = 9L
  pins[0] = 1
  ew[0] = 8L
  assert_eq(g.vertex_weight(0), 2L)
  assert_eq(g.pin_at(0, 0), 0)
  assert_eq(g.edge_weight(0), 4L)
}

///|
test "invalid/model rejects empty vertex set" {
  assert_true(@model.build([], [], []) is Err({ code: "vertex_count", .. }))
}

///|
test "invalid/model rejects mismatched edge weights" {
  assert_true(@model.build([1L], [[0]], []) is Err({ code: "edge_count", .. }))
}

///|
test "invalid/model rejects zero vertex weight" {
  assert_true(@model.build([0L], [], []) is Err({ code: "vertex_weight", .. }))
}

///|
test "invalid/model rejects negative vertex weight" {
  assert_true(@model.build([-1L], [], []) is Err({ code: "vertex_weight", .. }))
}

///|
test "invalid/model rejects zero and negative edge weights" {
  assert_true(
    @model.build([1L], [[0]], [0L]) is Err({ code: "edge_weight", .. }),
  )
  assert_true(
    @model.build([1L], [[0]], [-1L]) is Err({ code: "edge_weight", .. }),
  )
}

///|
test "invalid/model rejects empty edge" {
  assert_true(@model.build([1L], [[]], [1L]) is Err({ code: "empty_edge", .. }))
}

///|
test "invalid/model rejects duplicate pins" {
  assert_true(
    @model.build([1L, 1L], [[0, 1, 0]], [1L])
    is Err({ code: "duplicate_pin", .. }),
  )
}

///|
test "invalid/model rejects negative and out of range pins" {
  assert_true(
    @model.build([1L], [[-1]], [1L]) is Err({ code: "pin_range", .. }),
  )
  assert_true(@model.build([1L], [[1]], [1L]) is Err({ code: "pin_range", .. }))
}

///|
test "edge/model vertex sum overflow" {
  assert_true(
    @model.build([9223372036854775807L, 1L], [], [])
    is Err({ code: "overflow", .. }),
  )
}

///|
test "edge/model edge sum overflow" {
  assert_true(
    @model.build([1L], [[0], [0]], [9223372036854775807L, 1L])
    is Err({ code: "overflow", .. }),
  )
}

///|
test "edge/model exact limits accepted" {
  let limits : @model.Limits = {
    max_vertices: 2,
    max_edges: 1,
    max_pins: 2,
    max_text_bytes: 100,
  }
  assert_true(@model.build([1L, 1L], [[0, 1]], [1L], limits~) is Ok(_))
}

///|
test "invalid/model vertex edge and pin limits" {
  let limits : @model.Limits = {
    max_vertices: 1,
    max_edges: 0,
    max_pins: 0,
    max_text_bytes: 100,
  }
  assert_true(
    @model.build([1L, 1L], [], [], limits~) is Err({ code: "limit", .. }),
  )
  assert_true(
    @model.build([1L], [[0]], [1L], limits~) is Err({ code: "limit", .. }),
  )
  let pins : @model.Limits = { ..limits, max_edges: 1, }
  assert_true(
    @model.build([1L], [[0]], [1L], limits=pins) is Err({ code: "limit", .. }),
  )
}

///|
test "invalid/model negative limit rejected" {
  let limits : @model.Limits = { ..@model.Limits::default(), max_pins: -1, }
  assert_true(@model.build([1L], [], [], limits~) is Err({ code: "limit", .. }))
}
