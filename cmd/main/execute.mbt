///|
async fn execute(command : @cli.Command) -> Int32 {
  let text = match read_limited(command.input, command.limits.max_text_bytes) {
    Ok(text) => text
    Err(error) => {
      println(@lib.error_json(error))
      return 2
    }
  }
  let graph = match @lib.parse(text, limits=command.limits) {
    Ok(graph) => graph
    Err(error) => {
      println(@lib.error_json(error))
      return 2
    }
  }
  if command.action == "inspect" {
    println(@lib.inspect_json(graph))
    return 0
  }
  let capacities = match command.capacities {
    Some(capacities) => capacities
    None => {
      let capacity = match
        @lib.uniform_capacity(
          graph.total_vertex_weight(),
          command.imbalance_permille,
        ) {
        Ok(capacity) => capacity
        Err(error) => {
          println(@lib.error_json(error))
          return 2
        }
      }
      [capacity, capacity]
    }
  }
  if command.action == "verify" {
    let path = match command.partition_file {
      Some(path) => path
      None => return 6
    }
    let text = match read_limited(path, command.limits.max_text_bytes) {
      Ok(text) => text
      Err(error) => {
        println(@lib.error_json(error))
        return 4
      }
    }
    let assignment = match
      @lib.parse_partition(text, graph.vertex_count(), limits=command.limits) {
      Ok(assignment) => assignment
      Err(error) => {
        println(@lib.error_json(error))
        return 4
      }
    }
    let metrics = match @lib.verify(graph, assignment, capacities) {
      Ok(metrics) => metrics
      Err(error) => {
        println(@lib.error_json(error))
        return 4
      }
    }
    let json = @lib.metrics_json(graph, metrics)
    if command.report is Some(path) {
      write_outputs([(path, json + "\n")])
    }
    println(json)
    return 0
  }
  let result = match
    @lib.partition(graph, capacities, options=command.options) {
    Ok(result) => result
    Err(error) => {
      println(
        @lib.error_json({ code: error.kind, line: 0, message: error.message, }),
      )
      return match error.kind {
        "options" => 2
        "impossible" | "search_exhausted" => 3
        "validation" => 4
        _ => 6
      }
    }
  }
  let content = match
    @lib.partition_text(graph, result.assignment, capacities) {
    Ok(content) => content
    Err(error) => {
      println(@lib.error_json(error))
      return 6
    }
  }
  let json = @lib.result_json(graph, result)
  let outputs = []
  if command.report is Some(path) {
    outputs.push((path, json + "\n"))
  }
  let output = match command.output {
    Some(path) => path
    None => return 6
  }
  outputs.push((output, content))
  write_outputs(outputs)
  println(json)
  0
}
