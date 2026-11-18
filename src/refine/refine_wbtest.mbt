///|
fn raw_cut(g : @model.Hypergraph, parts : Array[Int32]) -> Int64 {
  let mut value = 0L
  for e in 0..<g.edge_count() {
    let mut zero = false
    let mut one = false
    for i in 0..<g.edge_size(e) {
      if parts[g.pin_at(e, i)] == 0 {
        zero = true
      } else {
        one = true
      }
    }
    if zero && one {
      value += g.edge_weight(e)
    }
  }
  value
}

///|
test "valid/refine every move gain equals independent objective delta" {
  let g = @model.build([1L, 1L, 1L, 1L], [[0, 1, 2], [1, 3], [0], [0, 2, 3]], [
    5L, 3L, 7L, 2L,
  ]).unwrap()
  for mask in 1..<15 {
    let parts = Array::makei(4, fn(v) { (mask >> v) & 1 })
    let state = State::new(
      g,
      parts,
      @metrics.verify(g, parts, [4L, 4L]).unwrap(),
    )
    for v in 0..<4 {
      let changed = parts.copy()
      changed[v] = 1 - changed[v]
      assert_eq(state.gain(g, v), raw_cut(g, parts) - raw_cut(g, changed))
    }
  }
}

///|
test "valid/refine every exchange gain equals independent objective delta" {
  let g = @model.build([1L, 1L, 1L, 1L], [[0, 1, 2], [1, 3], [0], [0, 2, 3]], [
    5L, 3L, 7L, 2L,
  ]).unwrap()
  for mask in 1..<15 {
    let parts = Array::makei(4, fn(v) { (mask >> v) & 1 })
    let state = State::new(
      g,
      parts,
      @metrics.verify(g, parts, [4L, 4L]).unwrap(),
    )
    let delta = Array::make(g.edge_count(), 0)
    for a in 0..<4 {
      for b in (a + 1)..<4 {
        if parts[a] != parts[b] {
          let changed = parts.copy()
          changed[a] = 1 - changed[a]
          changed[b] = 1 - changed[b]
          assert_eq(
            state.swap_gain(g, a, b, delta),
            raw_cut(g, parts) - raw_cut(g, changed),
          )
          assert_true(delta.iter().all(fn(x) { x == 0 }))
        }
      }
    }
  }
}

///|
test "valid/refine cached counts stay correct after move and inverse" {
  let g = @model.build([1L, 2L, 1L], [[0, 1, 2], [0, 1], [2]], [4L, 8L, 2L]).unwrap()
  let parts = [0, 1, 1]
  let state = State::new(g, parts, @metrics.verify(g, parts, [4L, 4L]).unwrap())
  let before = state.cut
  state.apply(g, 1)
  assert_eq(state.cut, raw_cut(g, state.assignment))
  state.apply(g, 1)
  assert_eq(state.cut, before)
  assert_eq(state.assignment, parts)
}
