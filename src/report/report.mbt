///|
using @json {type Json}

///|
/// Read one zero-based part ID per vertex, with an optional final newline.
pub fn parse_partition(
  text : StringView,
  vertex_count : Int32,
  limits~ : @model.Limits = @model.Limits::default(),
) -> Result[Array[Int32], @model.InputError] {
  if vertex_count < 1 ||
    vertex_count > limits.max_vertices ||
    text.length() > limits.max_text_bytes ||
    @utf8.encode(text).length() > limits.max_text_bytes {
    return Err({
      code: "limit",
      line: 0,
      message: "partition input exceeds resource limits",
    })
  }
  let lines = text.split("\n").to_array()
  let count = if lines.length() > 0 && lines[lines.length() - 1].is_empty() {
    lines.length() - 1
  } else {
    lines.length()
  }
  if count != vertex_count {
    return Err({
      code: "assignment_count",
      line: 0,
      message: "partition file must have one line per vertex",
    })
  }
  let assignment = []
  for i in 0..<count {
    match lines[i].trim() {
      "0" => assignment.push(0)
      "1" => assignment.push(1)
      _ =>
        return Err({
          code: "partition_id",
          line: i + 1,
          message: "expected partition ID 0 or 1",
        })
    }
  }
  Ok(assignment)
}

///|
/// Export only an independently verified complete feasible assignment.
pub fn partition_text(
  g : @model.Hypergraph,
  assignment : Array[Int32],
  capacities : Array[Int64],
) -> Result[String, @model.InputError] {
  match @metrics.verify(g, assignment, capacities) {
    Err(error) => Err(error)
    Ok(_) => Ok(assignment.map(fn(part) { part.to_string() }).join("\n") + "\n")
  }
}

///|
/// Versioned JSON. All weights and objectives are exact decimal strings.
pub fn metrics_json(
  g : @model.Hypergraph,
  metrics : @metrics.Metrics,
  run~ : Json = Json::null(),
) -> String {
  let value : Map[String, Json] = {
    "schema_version": Json::number(1.0),
    "status": Json::string("ok"),
    "vertices": Json::number(g.vertex_count().to_double()),
    "edges": Json::number(g.edge_count().to_double()),
    "pins": Json::number(g.pin_count().to_double()),
    "k": Json::number(2.0),
    "objective": Json::string("cut-net"),
    "cut_net": Json::string(metrics.cut_net.to_string()),
    "connectivity": Json::string(metrics.connectivity.to_string()),
    "part_weights": Json::array([
      Json::string(metrics.part_weights.0.to_string()),
      Json::string(metrics.part_weights.1.to_string()),
    ]),
    "part_sizes": Json::array([
      Json::number(metrics.part_sizes.0.to_double()),
      Json::number(metrics.part_sizes.1.to_double()),
    ]),
    "capacities": Json::array([
      Json::string(metrics.capacities.0.to_string()),
      Json::string(metrics.capacities.1.to_string()),
    ]),
    "max_to_average": Json::number(metrics.max_to_average),
    "run": run,
  }
  Json::object(value).stringify()
}

///|
/// Graph size and weight summary, with no solver invocation.
pub fn inspect_json(g : @model.Hypergraph) -> String {
  let value : Map[String, Json] = {
    "schema_version": Json::number(1.0),
    "status": Json::string("ok"),
    "vertices": Json::number(g.vertex_count().to_double()),
    "edges": Json::number(g.edge_count().to_double()),
    "pins": Json::number(g.pin_count().to_double()),
    "vertex_weight": Json::string(g.total_vertex_weight().to_string()),
    "edge_weight": Json::string(g.total_edge_weight().to_string()),
  }
  Json::object(value).stringify()
}

///|
/// Escape diagnostic data using the standard JSON encoder.
pub fn error_json(error : @model.InputError) -> String {
  let value : Map[String, Json] = {
    "schema_version": Json::number(1.0),
    "status": Json::string("error"),
    "code": Json::string(error.code),
    "line": Json::number(error.line.to_double()),
    "message": Json::string(error.message),
  }
  Json::object(value).stringify()
}
