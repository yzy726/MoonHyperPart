///|
fn fail(code : String, line : Int32, message : String) -> @model.InputError {
  { code, line, message, }
}

///|
fn tokens(line : StringView) -> Array[StringView] {
  let fields = []
  for field in line.split(" ") {
    for token in field.split("\t") {
      if !token.is_empty() {
        fields.push(token)
      }
    }
  }
  fields
}

///|
fn decimal(
  token : StringView,
  line : Int32,
) -> Result[Int64, @model.InputError] {
  if token.is_empty() {
    return Err(fail("integer", line, "expected unsigned decimal integer"))
  }
  let mut value = 0L
  for c in token.iter() {
    if c < '0' || c > '9' {
      return Err(fail("integer", line, "expected unsigned decimal integer"))
    }
    let digit = (c.to_int() - 48).to_int64()
    if value > (@model.max_weight - digit) / 10L {
      return Err(fail("overflow", line, "integer exceeds Int64"))
    }
    value = value * 10L + digit
  }
  Ok(value)
}

///|
fn next_line(lines : Array[StringView], start : Int32) -> Int32 {
  let mut pos = start
  while pos < lines.length() && lines[pos].trim().has_prefix("%") {
    pos += 1
  }
  pos
}

///|
/// Parse hMETIS modes 0, 1/01, 10 and 11. Errors retain physical line numbers.
/// Empty edges, inline comments, multiple weight constraints and extra records fail.
pub fn parse(
  text : StringView,
  limits~ : @model.Limits = @model.Limits::default(),
) -> Result[@model.Hypergraph, @model.InputError] {
  if limits.max_vertices < 1 ||
    limits.max_edges < 0 ||
    limits.max_pins < 0 ||
    limits.max_text_bytes < 0 {
    return Err(fail("limit", 0, "invalid resource limits"))
  }
  if text.length() > limits.max_text_bytes ||
    @utf8.encode(text).length() > limits.max_text_bytes {
    return Err(fail("limit", 0, "input text byte limit exceeded"))
  }
  let lines = text.split("\n").to_array()
  let mut pos = 0
  while pos < lines.length() &&
        (lines[pos].trim().is_empty() || lines[pos].trim().has_prefix("%")) {
    pos += 1
  }
  if pos == lines.length() {
    return Err(fail("header", 0, "missing hMETIS header"))
  }
  let header_line = pos + 1
  let header = tokens(lines[pos].trim())
  if header.length() < 2 || header.length() > 3 {
    return Err(
      fail(
        "header", header_line, "expected edge count, vertex count and optional format",
      ),
    )
  }
  let m = match decimal(header[0], header_line) {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  let n = match decimal(header[1], header_line) {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  if n == 0L {
    return Err(
      fail("vertex_count", header_line, "at least one vertex is required"),
    )
  }
  if n > limits.max_vertices.to_int64() ||
    m > limits.max_edges.to_int64() ||
    n >= 2147483647L ||
    m >= 2147483647L {
    return Err(
      fail("limit", header_line, "header exceeds vertex or edge limits"),
    )
  }
  let mode = if header.length() == 3 {
    match decimal(header[2], header_line) {
      Ok(x) => x
      Err(e) => return Err(e)
    }
  } else {
    0L
  }
  if mode != 0L && mode != 1L && mode != 10L && mode != 11L {
    return Err(
      fail("format", header_line, "supported formats are 0, 1, 10 and 11"),
    )
  }
  let edge_weighted = mode == 1L || mode == 11L
  let vertex_weighted = mode == 10L || mode == 11L
  let edges : Array[Array[Int32]] = []
  let edge_weights : Array[Int64] = []
  let seen = Array::make(n.to_int(), -1)
  let mut pin_count = 0
  let mut edge_total = 0L
  pos += 1
  for e in 0..<m.to_int() {
    pos = next_line(lines, pos)
    if pos >= lines.length() ||
      (pos == lines.length() - 1 && lines[pos].is_empty()) {
      return Err(fail("truncated", pos + 1, "missing hyperedge record"))
    }
    let fields = tokens(lines[pos].trim())
    let first_pin = if edge_weighted { 1 } else { 0 }
    if fields.length() <= first_pin {
      return Err(
        fail("empty_edge", pos + 1, "hyperedge must have at least one pin"),
      )
    }
    if fields.length() - first_pin > limits.max_pins - pin_count {
      return Err(fail("limit", pos + 1, "pin limit exceeded"))
    }
    let weight = if edge_weighted {
      match decimal(fields[0], pos + 1) {
        Ok(x) => x
        Err(err) => return Err(err)
      }
    } else {
      1L
    }
    if weight == 0L {
      return Err(fail("edge_weight", pos + 1, "edge weights must be positive"))
    }
    if weight > @model.max_weight - edge_total {
      return Err(fail("overflow", pos + 1, "edge weight sum exceeds Int64"))
    }
    edge_total += weight
    let pins = []
    for i in first_pin..<fields.length() {
      let pin = match decimal(fields[i], pos + 1) {
        Ok(x) => x
        Err(err) => return Err(err)
      }
      if pin == 0L || pin > n {
        return Err(
          fail("pin_range", pos + 1, "pin outside one-based vertex range"),
        )
      }
      let v = (pin - 1L).to_int()
      if seen[v] == e {
        return Err(
          fail("duplicate_pin", pos + 1, "repeated vertex in hyperedge"),
        )
      }
      seen[v] = e
      pins.push(v)
    }
    pin_count += pins.length()
    edges.push(pins)
    edge_weights.push(weight)
    pos += 1
  }
  let weights = Array::make(n.to_int(), 1L)
  let mut total = 0L
  if vertex_weighted {
    for v in 0..<n.to_int() {
      pos = next_line(lines, pos)
      if pos >= lines.length() ||
        (pos == lines.length() - 1 && lines[pos].is_empty()) {
        return Err(fail("truncated", pos + 1, "missing vertex weight"))
      }
      let fields = tokens(lines[pos].trim())
      if fields.length() != 1 {
        return Err(fail("vertex_weight", pos + 1, "expected one vertex weight"))
      }
      let weight = match decimal(fields[0], pos + 1) {
        Ok(x) => x
        Err(err) => return Err(err)
      }
      if weight == 0L {
        return Err(
          fail("vertex_weight", pos + 1, "vertex weights must be positive"),
        )
      }
      if weight > @model.max_weight - total {
        return Err(fail("overflow", pos + 1, "vertex weight sum exceeds Int64"))
      }
      total += weight
      weights[v] = weight
      pos += 1
    }
  }
  while pos < lines.length() {
    let line = lines[pos].trim()
    if !line.is_empty() && !line.has_prefix("%") {
      return Err(
        fail("extra_data", pos + 1, "unexpected record after declared data"),
      )
    }
    pos += 1
  }
  @model.build(weights, edges, edge_weights, limits~)
}
