///|
/// `impossible` marks a proved failure of a necessary feasibility condition.
/// `search_exhausted` describes the bounded search only.
#derive(Debug, Eq, ToJson)
pub(all) struct SolveError {
  kind : String
  message : String
}

///|
pub extend SolveError with @debug.Debug::{to_repr}

///|
pub extend SolveError with Eq::{equal, not_equal}

///|
pub extend SolveError with @json.ToJson::{to_json}

///|
#derive(Debug)
pub struct InitialResult {
  assignment : Array[Int32]
  metrics : @metrics.Metrics
  starts_tried : Int32
  search_nodes : Int32
}

///|
pub extend InitialResult with @debug.Debug::{to_repr}

///|
priv struct Rng {
  mut state : UInt32
}

///|
fn Rng::next(self : Rng) -> UInt32 {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  x
}

///|
fn greedy(
  graph : @model.Hypergraph,
  order : Array[Int32],
  capacities : Array[Int64],
) -> Array[Int32]? {
  let assignment = Array::make(order.length(), -1)
  let loads = [0L, 0L]
  let sizes = [0, 0]
  for i in 0..<order.length() {
    let v = order[i]
    let weight = graph.vertex_weight(v)
    let mut side = if loads[0] <= loads[1] { 0 } else { 1 }
    if i == order.length() - 1 && (sizes[0] == 0 || sizes[1] == 0) {
      side = if sizes[0] == 0 { 0 } else { 1 }
      if weight > capacities[side] - loads[side] {
        return None
      }
    } else if weight > capacities[side] - loads[side] {
      side = 1 - side
      if weight > capacities[side] - loads[side] {
        return None
      }
    }
    assignment[v] = side
    loads[side] += weight
    sizes[side] += 1
  }
  Some(assignment)
}

///|
// Iterative backtracking keeps stack use independent of the vertex count.
fn repair(
  graph : @model.Hypergraph,
  order : Array[Int32],
  capacities : Array[Int64],
  budget : Int32,
) -> (Array[Int32]?, Int32) {
  let n = order.length()
  let assignment = Array::make(n, -1)
  let choices = Array::make(n, 0)
  let loads = [0L, 0L]
  let sizes = [0, 0]
  let mut depth = 0
  let mut used = 0
  while depth >= 0 {
    if depth == n {
      if sizes[0] > 0 && sizes[1] > 0 {
        return (Some(assignment), used)
      }
      depth -= 1
      let v = order[depth]
      let side = assignment[v]
      loads[side] -= graph.vertex_weight(v)
      sizes[side] -= 1
      assignment[v] = -1
      continue
    }
    if choices[depth] == 2 {
      choices[depth] = 0
      depth -= 1
      if depth >= 0 {
        let v = order[depth]
        let side = assignment[v]
        loads[side] -= graph.vertex_weight(v)
        sizes[side] -= 1
        assignment[v] = -1
      }
      continue
    }
    if used >= budget {
      return (None, used)
    }
    used += 1
    let side = choices[depth]
    choices[depth] += 1
    let v = order[depth]
    let weight = graph.vertex_weight(v)
    if weight > capacities[side] - loads[side] {
      continue
    }
    assignment[v] = side
    loads[side] += weight
    sizes[side] += 1
    depth += 1
    if depth < n {
      choices[depth] = 0
    }
  }
  (None, used)
}

///|
/// Multi-start greedy packing followed by bounded repair when all starts fail.
/// Start zero uses decreasing vertex weight and increasing ID for ties.
pub fn construct(
  graph : @model.Hypergraph,
  capacities : Array[Int64],
  seed~ : UInt32,
  starts~ : Int32,
  search_nodes~ : Int32,
) -> Result[InitialResult, SolveError] {
  if capacities.length() != 2 ||
    starts < 1 ||
    starts > 64 ||
    search_nodes < 0 ||
    search_nodes > 10000000 {
    return Err({
      kind: "options",
      message: "two capacities, 1..64 starts and 0..10000000 search nodes required",
    })
  }
  if capacities[0] <= 0L || capacities[1] <= 0L {
    return Err({ kind: "options", message: "capacities must be positive", })
  }
  let total = graph.total_vertex_weight()
  if graph.vertex_count() < 2 ||
    (capacities[0] < total && capacities[1] < total - capacities[0]) {
    return Err({
      kind: "impossible",
      message: "two nonempty parts require two vertices and sufficient total capacity",
    })
  }
  for v in 0..<graph.vertex_count() {
    let weight = graph.vertex_weight(v)
    if weight > capacities[0] && weight > capacities[1] {
      return Err({
        kind: "impossible",
        message: "a vertex exceeds both capacities",
      })
    }
  }
  let order = Array::makei(graph.vertex_count(), fn(i) { i })
  order.sort_by(fn(a, b) {
    let wa = graph.vertex_weight(a)
    let wb = graph.vertex_weight(b)
    if wa > wb {
      -1
    } else if wa < wb {
      1
    } else {
      a.compare(b)
    }
  })
  let rng : Rng = { state: if seed == 0U { 2463534242U } else { seed }, }
  let mut best : InitialResult? = None
  for start in 0..<starts {
    let current = order.copy()
    if start > 0 {
      let mut i = current.length() - 1
      while i > 0 {
        let j = (rng.next() % (i + 1).reinterpret_as_uint()).reinterpret_as_int()
        let temporary = current[i]
        current[i] = current[j]
        current[j] = temporary
        i -= 1
      }
    }
    if greedy(graph, current, capacities) is Some(assignment) {
      if @metrics.verify(graph, assignment, capacities) is Ok(metrics) {
        let improve = match best {
          None => true
          Some(previous) => metrics.cut_net < previous.metrics.cut_net
        }
        if improve {
          best = Some({
            assignment,
            metrics,
            starts_tried: starts,
            search_nodes: 0,
          })
        }
      }
    }
  }
  if best is Some(result) {
    return Ok(result)
  }
  let (candidate, used) = repair(graph, order, capacities, search_nodes)
  if candidate is Some(assignment) {
    if @metrics.verify(graph, assignment, capacities) is Ok(metrics) {
      return Ok({
        assignment,
        metrics,
        starts_tried: starts,
        search_nodes: used,
      })
    }
  }
  Err({
    kind: "search_exhausted",
    message: "no feasible bipartition found within the construction budget",
  })
}
