///|
/// Work bounds for FM passes, vertex moves, pair trials and candidate scans.
#derive(Debug)
pub(all) struct RefinementBudget {
  max_passes : Int32
  max_moves : Int32
  max_swap_trials : Int32
  max_candidates : Int32
}

///|
pub extend RefinementBudget with @debug.Debug::{to_repr}

///|
/// Default bounds for the single-level implementation.
pub fn RefinementBudget::default() -> RefinementBudget {
  {
    max_passes: 8,
    max_moves: 10000,
    max_swap_trials: 10000,
    max_candidates: 200000,
  }
}

///|
/// Counts include exploratory moves subsequently rolled back.
#derive(Debug)
pub struct RefineResult {
  assignment : Array[Int32]
  metrics : @metrics.Metrics
  initial_cut : Int64
  moves : Int32
  swaps : Int32
  passes : Int32
  rolled_back : Int32
  budget_limited : Bool
}

///|
pub extend RefineResult with @debug.Debug::{to_repr}

///|
priv struct State {
  assignment : Array[Int32]
  zero_pins : Array[Int32]
  loads : Array[Int64]
  sizes : Array[Int32]
  mut cut : Int64
}

///|
fn State::new(
  g : @model.Hypergraph,
  assignment : Array[Int32],
  metrics : @metrics.Metrics,
) -> State {
  let zero_pins = Array::make(g.edge_count(), 0)
  for e in 0..<g.edge_count() {
    for i in 0..<g.edge_size(e) {
      if assignment[g.pin_at(e, i)] == 0 {
        zero_pins[e] += 1
      }
    }
  }
  {
    assignment: assignment.copy(),
    zero_pins,
    loads: [metrics.part_weights.0, metrics.part_weights.1],
    sizes: [metrics.part_sizes.0, metrics.part_sizes.1],
    cut: metrics.cut_net,
  }
}

///|
fn State::gain(self : State, g : @model.Hypergraph, v : Int32) -> Int64 {
  let from = self.assignment[v]
  let mut gain = 0L
  for i in 0..<g.degree(v) {
    let e = g.incident_at(v, i)
    let zero = self.zero_pins[e]
    let one = g.edge_size(e) - zero
    let from_count = if from == 0 { zero } else { one }
    let to_count = if from == 0 { one } else { zero }
    if from_count == 1 {
      gain += g.edge_weight(e)
    }
    if to_count == 0 {
      gain -= g.edge_weight(e)
    }
  }
  gain
}

///|
// Update one vertex. The caller checks a single move or an atomic exchange.
fn State::apply(self : State, g : @model.Hypergraph, v : Int32) -> Unit {
  let from = self.assignment[v]
  let to = 1 - from
  let gain = self.gain(g, v)
  let delta = if from == 0 { -1 } else { 1 }
  for i in 0..<g.degree(v) {
    self.zero_pins[g.incident_at(v, i)] += delta
  }
  self.assignment[v] = to
  self.loads[from] -= g.vertex_weight(v)
  self.loads[to] += g.vertex_weight(v)
  self.sizes[from] -= 1
  self.sizes[to] += 1
  self.cut -= gain
}

///|
// Sum objective differences on the union of incident edges, counting each once.
fn State::swap_gain(
  self : State,
  g : @model.Hypergraph,
  a : Int32,
  b : Int32,
  delta : Array[Int32],
) -> Int64 {
  let touched = []
  let change_a = if self.assignment[a] == 0 { -1 } else { 1 }
  for i in 0..<g.degree(a) {
    let e = g.incident_at(a, i)
    touched.push(e)
    delta[e] = change_a
  }
  for i in 0..<g.degree(b) {
    let e = g.incident_at(b, i)
    if delta[e] == 0 {
      touched.push(e)
    }
    delta[e] -= change_a
  }
  let mut gain = 0L
  for e in touched {
    let before = self.zero_pins[e]
    let after = before + delta[e]
    let was_cut = before > 0 && before < g.edge_size(e)
    let is_cut = after > 0 && after < g.edge_size(e)
    if was_cut && !is_cut {
      gain += g.edge_weight(e)
    }
    if !was_cut && is_cut {
      gain -= g.edge_weight(e)
    }
    delta[e] = 0
  }
  gain
}
