///|
/// Input/resource errors. `line` is one based for text, zero for memory input.
#derive(Debug, Eq, ToJson)
pub(all) struct InputError {
  code : String
  line : Int32
  message : String
}

///|
/// Allocation limits checked before constructing the incidence arrays.
#derive(Debug, Eq)
pub(all) struct Limits {
  max_vertices : Int32
  max_edges : Int32
  max_pins : Int32
  max_text_bytes : Int32
}

///|
/// Conservative defaults for the single-level implementation.
pub fn Limits::default() -> Limits {
  {
    max_vertices: 100000,
    max_edges: 100000,
    max_pins: 1000000,
    max_text_bytes: 16777216,
  }
}

///|
/// An owned immutable hypergraph, using CSR in both incidence directions.
#derive(Debug)
struct Hypergraph {
  vertex_weights : Array[Int64]
  edge_weights : Array[Int64]
  edge_offsets : Array[Int32]
  pins : Array[Int32]
  vertex_offsets : Array[Int32]
  incidents : Array[Int32]
  vertex_total : Int64
  edge_total : Int64
}

///|
/// Maximum positive weight/sum accepted on every backend.
pub let max_weight : Int64 = 9223372036854775807L

///|
/// Validate and own the input. Pins use zero-based vertex indices.
pub fn build(
  vertex_weights : Array[Int64],
  edges : Array[Array[Int32]],
  edge_weights : Array[Int64],
  limits~ : Limits = Limits::default(),
) -> Result[Hypergraph, InputError] {
  let n = vertex_weights.length()
  let m = edges.length()
  if limits.max_vertices < 1 ||
    limits.max_edges < 0 ||
    limits.max_pins < 0 ||
    limits.max_text_bytes < 0 {
    return Err({ code: "limit", line: 0, message: "invalid resource limits", })
  }
  if n == 0 {
    return Err({
      code: "vertex_count",
      line: 0,
      message: "at least one vertex is required",
    })
  }
  if n > limits.max_vertices ||
    m > limits.max_edges ||
    n == 2147483647 ||
    m == 2147483647 {
    return Err({
      code: "limit",
      line: 0,
      message: "vertex or edge limit exceeded",
    })
  }
  if m != edge_weights.length() {
    return Err({
      code: "edge_count",
      line: 0,
      message: "edge weight count does not match edges",
    })
  }
  let mut vertex_total = 0L
  for w in vertex_weights {
    if w <= 0L {
      return Err({
        code: "vertex_weight",
        line: 0,
        message: "vertex weights must be positive",
      })
    }
    if w > max_weight - vertex_total {
      return Err({
        code: "overflow",
        line: 0,
        message: "vertex weight sum exceeds Int64",
      })
    }
    vertex_total += w
  }
  let mut edge_total = 0L
  let mut pin_count = 0
  // A timestamp per vertex detects duplicates without sorting or quadratic scans.
  let seen = Array::make(n, -1)
  for e in 0..<m {
    let w = edge_weights[e]
    if w <= 0L {
      return Err({
        code: "edge_weight",
        line: 0,
        message: "edge weights must be positive",
      })
    }
    if w > max_weight - edge_total {
      return Err({
        code: "overflow",
        line: 0,
        message: "edge weight sum exceeds Int64",
      })
    }
    edge_total += w
    if edges[e].is_empty() {
      return Err({
        code: "empty_edge",
        line: 0,
        message: "an edge must contain at least one pin",
      })
    }
    if edges[e].length() > limits.max_pins - pin_count ||
      edges[e].length() >= 2147483647 - pin_count {
      return Err({ code: "limit", line: 0, message: "pin limit exceeded", })
    }
    pin_count += edges[e].length()
    for v in edges[e] {
      if v < 0 || v >= n {
        return Err({
          code: "pin_range",
          line: 0,
          message: "pin outside vertex range",
        })
      }
      if seen[v] == e {
        return Err({
          code: "duplicate_pin",
          line: 0,
          message: "repeated vertex in an edge",
        })
      }
      seen[v] = e
    }
  }
  let edge_offsets = Array::make(m + 1, 0)
  let pins : Array[Int32] = []
  let vertex_offsets = Array::make(n + 1, 0)
  for e in 0..<m {
    edge_offsets[e] = pins.length()
    for v in edges[e] {
      pins.push(v)
      vertex_offsets[v + 1] += 1
    }
  }
  edge_offsets[m] = pin_count
  for v in 0..<n {
    vertex_offsets[v + 1] += vertex_offsets[v]
  }
  let next = vertex_offsets.copy()
  let incidents = Array::make(pin_count, 0)
  for e in 0..<m {
    for v in edges[e] {
      incidents[next[v]] = e
      next[v] += 1
    }
  }
  Ok({
    vertex_weights: vertex_weights.copy(),
    edge_weights: edge_weights.copy(),
    edge_offsets,
    pins,
    vertex_offsets,
    incidents,
    vertex_total,
    edge_total,
  })
}

///|
/// Number of vertices, including isolated vertices.
pub fn Hypergraph::vertex_count(self : Hypergraph) -> Int32 {
  self.vertex_weights.length()
}

///|
/// Number of hyperedges, including singleton hyperedges.
pub fn Hypergraph::edge_count(self : Hypergraph) -> Int32 {
  self.edge_weights.length()
}

///|
/// Total number of pins.
pub fn Hypergraph::pin_count(self : Hypergraph) -> Int32 {
  self.pins.length()
}

///|
/// Positive weight of a vertex. Requires `0 <= v < vertex_count()`.
pub fn Hypergraph::vertex_weight(self : Hypergraph, v : Int32) -> Int64 {
  self.vertex_weights[v]
}

///|
/// Positive weight of an edge. Requires `0 <= e < edge_count()`.
pub fn Hypergraph::edge_weight(self : Hypergraph, e : Int32) -> Int64 {
  self.edge_weights[e]
}

///|
/// Number of pins in edge `e`. Requires a valid edge index.
pub fn Hypergraph::edge_size(self : Hypergraph, e : Int32) -> Int32 {
  self.edge_offsets[e + 1] - self.edge_offsets[e]
}

///|
/// Vertex at pin `i` of edge `e`. Requires valid edge and pin indices.
pub fn Hypergraph::pin_at(self : Hypergraph, e : Int32, i : Int32) -> Int32 {
  self.pins[self.edge_offsets[e] + i]
}

///|
/// Number of edges incident to vertex `v`. Requires a valid vertex index.
pub fn Hypergraph::degree(self : Hypergraph, v : Int32) -> Int32 {
  self.vertex_offsets[v + 1] - self.vertex_offsets[v]
}

///|
/// Incident edge at index `i` of vertex `v`. Requires valid indices.
pub fn Hypergraph::incident_at(
  self : Hypergraph,
  v : Int32,
  i : Int32,
) -> Int32 {
  self.incidents[self.vertex_offsets[v] + i]
}

///|
/// Checked sum of all vertex weights.
pub fn Hypergraph::total_vertex_weight(self : Hypergraph) -> Int64 {
  self.vertex_total
}

///|
/// Checked sum of all edge weights (an upper bound on bipartition cut-net).
pub fn Hypergraph::total_edge_weight(self : Hypergraph) -> Int64 {
  self.edge_total
}

///|
pub extend InputError with @debug.Debug::{to_repr}

///|
pub extend InputError with Eq::{equal, not_equal}

///|
pub extend InputError with @json.ToJson::{to_json}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Hypergraph with @debug.Debug::{to_repr}
