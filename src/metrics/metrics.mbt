///|
/// Independently recomputed measurements for a complete feasible bipartition.
#derive(Debug)
pub struct Metrics {
  part_weights : (Int64, Int64)
  part_sizes : (Int32, Int32)
  capacities : (Int64, Int64)
  cut_net : Int64
  connectivity : Int64
  max_to_average : Double
}

///|
pub extend Metrics with @debug.Debug::{to_repr}

///|
/// Exact ceil(total * (1000 + imbalance_permille) / 2000).
/// Tolerance is between 0 and 1000 per mille. Intermediate products cannot overflow.
pub fn uniform_capacity(
  total : Int64,
  imbalance_permille : Int32,
) -> Result[Int64, @model.InputError] {
  if total <= 0L || imbalance_permille < 0 || imbalance_permille > 1000 {
    return Err({
      code: "capacity",
      line: 0,
      message: "positive total and tolerance in 0..1000 per mille required",
    })
  }
  let factor = (1000 + imbalance_permille).to_int64()
  let whole = total / 2000L * factor
  let remainder = total % 2000L * factor
  let round_up = if remainder % 2000L == 0L { 0L } else { 1L }
  Ok(whole + remainder / 2000L + round_up)
}

///|
/// Validate assignment length, IDs, nonempty parts, capacities and objective.
/// Only the original graph is read. No solver counts or gain caches are accepted.
pub fn verify(
  graph : @model.Hypergraph,
  assignment : Array[Int32],
  capacities : Array[Int64],
) -> Result[Metrics, @model.InputError] {
  if capacities.length() != 2 {
    return Err({
      code: "capacity_count",
      line: 0,
      message: "exactly two capacities are required",
    })
  }
  if capacities[0] <= 0L || capacities[1] <= 0L {
    return Err({
      code: "capacity",
      line: 0,
      message: "capacities must be positive",
    })
  }
  if assignment.length() != graph.vertex_count() {
    return Err({
      code: "assignment_count",
      line: 0,
      message: "assignment must cover every vertex exactly once",
    })
  }
  let weights = [0L, 0L]
  let sizes = [0, 0]
  for v in 0..<graph.vertex_count() {
    let part = assignment[v]
    if part != 0 && part != 1 {
      return Err({
        code: "partition_id",
        line: v + 1,
        message: "partition ID must be 0 or 1",
      })
    }
    weights[part] += graph.vertex_weight(v)
    sizes[part] += 1
  }
  if sizes[0] == 0 || sizes[1] == 0 {
    return Err({
      code: "empty_partition",
      line: 0,
      message: "both partitions must contain a vertex",
    })
  }
  if weights[0] > capacities[0] || weights[1] > capacities[1] {
    return Err({
      code: "capacity",
      line: 0,
      message: "partition weight exceeds its capacity",
    })
  }
  let mut cut_net = 0L
  for e in 0..<graph.edge_count() {
    let first = assignment[graph.pin_at(e, 0)]
    let mut cut = false
    for i in 1..<graph.edge_size(e) {
      if assignment[graph.pin_at(e, i)] != first {
        cut = true
        break
      }
    }
    if cut {
      cut_net += graph.edge_weight(e)
    }
  }
  let heaviest = if weights[0] > weights[1] { weights[0] } else { weights[1] }
  Ok({
    part_weights: (weights[0], weights[1]),
    part_sizes: (sizes[0], sizes[1]),
    capacities: (capacities[0], capacities[1]),
    cut_net,
    connectivity: cut_net,
    max_to_average: 2.0 *
    heaviest.to_double() /
    graph.total_vertex_weight().to_double(),
  })
}
