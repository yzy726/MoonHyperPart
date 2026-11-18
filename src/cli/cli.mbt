///|
#derive(Debug)
pub struct Command {
  action : String
  input : String
  partition_file : String?
  output : String?
  report : String?
  capacities : Array[Int64]?
  imbalance_permille : Int32
  options : @lib.Options
  limits : @lib.Limits
}

///|
pub extend Command with @debug.Debug::{to_repr}

///|
fn arg_error(message : String) -> @lib.InputError {
  { code: "arguments", line: 0, message, }
}

///|
fn number(
  text : StringView,
  minimum : Int64,
  maximum : Int64,
) -> Result[Int64, @lib.InputError] {
  if text.is_empty() {
    return Err(arg_error("expected decimal integer"))
  }
  let mut value = 0L
  for c in text.iter() {
    if c < '0' || c > '9' {
      return Err(arg_error("expected unsigned decimal integer"))
    }
    let digit = (c.to_int() - 48).to_int64()
    if value > (9223372036854775807L - digit) / 10L {
      return Err(arg_error("integer overflow"))
    }
    value = value * 10L + digit
  }
  if value < minimum || value > maximum {
    return Err(arg_error("numeric option outside its supported range"))
  }
  Ok(value)
}

///|
fn tolerance(text : StringView) -> Result[Int32, @lib.InputError] {
  if text == "0" {
    return Ok(0)
  }
  if text == "1" {
    return Ok(1000)
  }
  let fields = text.split(".").to_array()
  if fields.length() != 2 ||
    (fields[0] != "0" && fields[0] != "1") ||
    fields[1].length() < 1 ||
    fields[1].length() > 3 {
    return Err(
      arg_error(
        "imbalance must be a decimal from 0 to 1 with at most three fractional digits",
      ),
    )
  }
  let fraction = match number(fields[1], 0L, 999L) {
    Ok(x) => x.to_int()
    Err(e) => return Err(e)
  }
  let factor = match fields[1].length() {
    1 => 100
    2 => 10
    _ => 1
  }
  if fields[0] == "1" {
    if fraction != 0 {
      return Err(arg_error("imbalance exceeds 1"))
    }
    Ok(1000)
  } else {
    Ok(fraction * factor)
  }
}

///|
/// Parse arguments excluding the executable name. Resource options tighten defaults.
pub fn parse_args(args : Array[String]) -> Result[Command, @lib.InputError] {
  let mut action = if args.is_empty() { "help" } else { args[0] }
  if args.iter().any(fn(arg) { arg == "--help" || arg == "-h" }) {
    action = "help"
  }
  let mut options = @lib.Options::default()
  let mut refinement = options.refinement
  let mut limits = @lib.Limits::default()
  if action == "help" {
    return Ok({
      action,
      input: "",
      partition_file: None,
      output: None,
      report: None,
      capacities: None,
      imbalance_permille: 30,
      options,
      limits,
    })
  }
  if action != "inspect" && action != "partition" && action != "verify" {
    return Err(arg_error("expected inspect, partition or verify"))
  }
  let positional = []
  let seen : Map[String, Bool] = Map([])
  let mut output = None
  let mut report = None
  let mut capacities = None
  let mut imbalance_permille = 30
  let mut i = 1
  while i < args.length() {
    let key = args[i]
    if !key.has_prefix("--") {
      positional.push(key)
      i += 1
      continue
    }
    if seen.get(key) is Some(_) {
      return Err(arg_error("duplicate option " + key))
    }
    seen.set(key, true)
    if i + 1 >= args.length() {
      return Err(arg_error("missing value for " + key))
    }
    let value = args[i + 1]
    if value.is_empty() {
      return Err(arg_error("empty value for " + key))
    }
    let solver_flag = key == "--seed" ||
      key == "--starts" ||
      key == "--search-nodes" ||
      key == "--passes" ||
      key == "--moves" ||
      key == "--swap-trials" ||
      key == "--candidates" ||
      key == "--output"
    if solver_flag && action != "partition" {
      return Err(arg_error(key + " requires partition"))
    }
    if (key == "--imbalance" || key == "--capacities" || key == "--report") &&
      action == "inspect" {
      return Err(arg_error(key + " requires partition or verify"))
    }
    match key {
      "--output" => output = Some(value)
      "--report" => report = Some(value)
      "--imbalance" =>
        imbalance_permille = match tolerance(value) {
          Ok(x) => x
          Err(e) => return Err(e)
        }
      "--capacities" => {
        let parts = value.split(",").to_array()
        if parts.length() != 2 {
          return Err(
            arg_error(
              "capacities require two positive integers separated by a comma",
            ),
          )
        }
        let a = match number(parts[0], 1L, 9223372036854775807L) {
          Ok(x) => x
          Err(e) => return Err(e)
        }
        let b = match number(parts[1], 1L, 9223372036854775807L) {
          Ok(x) => x
          Err(e) => return Err(e)
        }
        capacities = Some([a, b])
      }
      "--seed" => {
        let seed = match number(value, 0L, 4294967295L) {
          Ok(x) => x.to_int().reinterpret_as_uint()
          Err(e) => return Err(e)
        }
        options = { ..options, seed, }
      }
      "--starts" => {
        let starts = match number(value, 1L, 64L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        options = { ..options, starts, }
      }
      "--search-nodes" => {
        let search_nodes = match number(value, 0L, 10000000L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        options = { ..options, search_nodes, }
      }
      "--passes" => {
        let x = match number(value, 0L, 100L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        refinement = { ..refinement, max_passes: x, }
      }
      "--moves" => {
        let x = match number(value, 0L, 1000000L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        refinement = { ..refinement, max_moves: x, }
      }
      "--swap-trials" => {
        let x = match number(value, 0L, 1000000L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        refinement = { ..refinement, max_swap_trials: x, }
      }
      "--candidates" => {
        let x = match number(value, 0L, 10000000L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        refinement = { ..refinement, max_candidates: x, }
      }
      "--max-vertices" => {
        let x = match number(value, 1L, 100000L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        limits = { ..limits, max_vertices: x, }
      }
      "--max-edges" => {
        let x = match number(value, 0L, 100000L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        limits = { ..limits, max_edges: x, }
      }
      "--max-pins" => {
        let x = match number(value, 0L, 1000000L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        limits = { ..limits, max_pins: x, }
      }
      "--max-input-bytes" => {
        let x = match number(value, 0L, 16777216L) {
          Ok(x) => x.to_int()
          Err(e) => return Err(e)
        }
        limits = { ..limits, max_text_bytes: x, }
      }
      _ => return Err(arg_error("unknown option " + key))
    }
    i += 2
  }
  if seen.get("--capacities") is Some(_) && seen.get("--imbalance") is Some(_) {
    return Err(arg_error("choose capacities or imbalance"))
  }
  let count = if action == "verify" { 2 } else { 1 }
  if positional.length() != count {
    return Err(arg_error("incorrect number of input paths"))
  }
  if action == "partition" && output is None {
    return Err(arg_error("partition requires --output"))
  }
  let input = positional[0]
  if output is Some(path) {
    if path == input || report == Some(path) {
      return Err(
        arg_error("output paths must be distinct from inputs and each other"),
      )
    }
  }
  if report == Some(input) ||
    (action == "verify" && report == Some(positional[1])) {
    return Err(arg_error("report path must differ from input paths"))
  }
  Ok({
    action,
    input,
    partition_file: if action == "verify" {
      Some(positional[1])
    } else {
      None
    },
    output,
    report,
    capacities,
    imbalance_permille,
    options: { ..options, refinement, },
    limits,
  })
}

///|
/// Command synopsis and exact option units.
pub fn help() -> String {
  "MoonHyperPart 0.1.0\ninspect INPUT.hgr\npartition INPUT.hgr --output OUTPUT.part [--report METRICS.json]\nverify INPUT.hgr PARTITION.part [--report METRICS.json]\nBalance: --capacities C0,C1 | --imbalance 0.030 (default)\nSolver: --seed 726 --starts 8 --search-nodes 100000\nFM: --passes 8 --moves 10000 --swap-trials 10000 --candidates 200000\nResource bounds: --max-vertices 100000 --max-edges 100000 --max-pins 1000000 --max-input-bytes 16777216\nExit codes: 0 success, 2 input/arguments, 3 search/impossibility, 4 verification, 5 I/O, 6 internal error\nOutput files must be new paths. Weights and objectives in JSON are decimal strings.\n"
}
