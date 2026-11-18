///|
priv struct Choice {
  first : Int32
  second : Int32
  gain : Int64
}

///|
priv struct Work {
  mut candidates : Int32
  mut swap_trials : Int32
  mut moves : Int32
  mut swaps : Int32
}

///|
fn select_move(
  g : @model.Hypergraph,
  state : State,
  capacities : Array[Int64],
  locked : Array[Bool],
  delta : Array[Int32],
  budget : RefinementBudget,
  work : Work,
) -> Choice? {
  let mut best : Choice? = None
  for v in 0..<g.vertex_count() {
    if work.candidates >= budget.max_candidates {
      break
    }
    work.candidates += 1
    if locked[v] {
      continue
    }
    let from = state.assignment[v]
    let to = 1 - from
    if state.sizes[from] <= 1 ||
      g.vertex_weight(v) > capacities[to] - state.loads[to] {
      continue
    }
    let gain = state.gain(g, v)
    let better = match best {
      None => true
      Some(previous) => gain > previous.gain
    }
    if better {
      best = Some({ first: v, second: -1, gain, })
    }
  }
  if budget.max_moves - work.moves < 2 {
    return best
  }
  for a in 0..<g.vertex_count() {
    if work.swap_trials >= budget.max_swap_trials {
      break
    }
    for b in (a + 1)..<g.vertex_count() {
      if work.swap_trials >= budget.max_swap_trials {
        break
      }
      work.swap_trials += 1
      if locked[a] || locked[b] || state.assignment[a] == state.assignment[b] {
        continue
      }
      let from = state.assignment[a]
      let to = 1 - from
      let wa = g.vertex_weight(a)
      let wb = g.vertex_weight(b)
      if wb > capacities[from] - (state.loads[from] - wa) ||
        wa > capacities[to] - (state.loads[to] - wb) {
        continue
      }
      let gain = state.swap_gain(g, a, b, delta)
      let better = match best {
        None => true
        Some(previous) => gain > previous.gain
      }
      if better {
        best = Some({ first: a, second: b, gain, })
      }
    }
  }
  best
}

///|
/// Improve a feasible bipartition using pin-count FM gains and feasible swaps.
/// Every pass locks moved vertices, retains its best prefix and reverts the suffix.
pub fn refine(
  g : @model.Hypergraph,
  assignment : Array[Int32],
  capacities : Array[Int64],
  budget~ : RefinementBudget = RefinementBudget::default(),
) -> Result[RefineResult, @initial.SolveError] {
  if budget.max_passes < 0 ||
    budget.max_passes > 100 ||
    budget.max_moves < 0 ||
    budget.max_moves > 1000000 ||
    budget.max_swap_trials < 0 ||
    budget.max_swap_trials > 1000000 ||
    budget.max_candidates < 0 ||
    budget.max_candidates > 10000000 {
    return Err({ kind: "options", message: "invalid refinement work budget", })
  }
  let initial = match @metrics.verify(g, assignment, capacities) {
    Ok(m) => m
    Err(error) => return Err({ kind: "validation", message: error.message, })
  }
  let state = State::new(g, assignment, initial)
  let work : Work = { candidates: 0, swap_trials: 0, moves: 0, swaps: 0, }
  let delta = Array::make(g.edge_count(), 0)
  let mut passes = 0
  let mut rolled_back = 0
  let mut measured = initial
  while passes < budget.max_passes {
    if work.moves >= budget.max_moves ||
      work.candidates >= budget.max_candidates {
      break
    }
    passes += 1
    let locked = Array::make(g.vertex_count(), false)
    let history : Array[(Int32, Int32)] = []
    let pass_start = state.cut
    let mut best_cut = state.cut
    let mut best_prefix = 0
    while work.moves < budget.max_moves &&
          work.candidates < budget.max_candidates {
      let choice = match
        select_move(g, state, capacities, locked, delta, budget, work) {
        Some(choice) => choice
        None => break
      }
      state.apply(g, choice.first)
      locked[choice.first] = true
      work.moves += 1
      if choice.second >= 0 {
        state.apply(g, choice.second)
        locked[choice.second] = true
        work.moves += 1
        work.swaps += 1
      }
      history.push((choice.first, choice.second))
      if state.cut < best_cut {
        best_cut = state.cut
        best_prefix = history.length()
      }
    }
    let mut suffix = history.length()
    while suffix > best_prefix {
      suffix -= 1
      let (first, second) = history[suffix]
      if second >= 0 {
        state.apply(g, second)
        rolled_back += 1
      }
      state.apply(g, first)
      rolled_back += 1
    }
    measured = match @metrics.verify(g, state.assignment, capacities) {
      Ok(m) => m
      Err(error) => return Err({ kind: "internal", message: error.message, })
    }
    if measured.cut_net != state.cut ||
      measured.cut_net != best_cut ||
      measured.cut_net > pass_start {
      return Err({
        kind: "internal",
        message: "FM counts disagree with independent validation",
      })
    }
    if best_cut == pass_start {
      break
    }
  }
  let limited = budget.max_passes > 0 &&
    (
      work.moves >= budget.max_moves ||
      work.candidates >= budget.max_candidates ||
      (budget.max_swap_trials > 0 && work.swap_trials >= budget.max_swap_trials) ||
      passes == budget.max_passes
    )
  Ok({
    assignment: state.assignment,
    metrics: measured,
    initial_cut: initial.cut_net,
    moves: work.moves,
    swaps: work.swaps,
    passes,
    rolled_back,
    budget_limited: limited,
  })
}
