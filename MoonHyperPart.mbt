///|
pub using @model {type Hypergraph, type Limits, type InputError, build}

///|
pub using @hmetis {parse}

///|
pub using @metrics {type Metrics, uniform_capacity, verify}

///|
pub using @initial {type SolveError}

///|
pub using @refine {type RefinementBudget}

///|
pub using @report {
  parse_partition,
  partition_text,
  metrics_json,
  inspect_json,
  error_json,
}

///|
/// Deterministic construction and refinement work bounds.
#derive(Debug)
pub(all) struct Options {
  seed : UInt32
  starts : Int32
  search_nodes : Int32
  refinement : @refine.RefinementBudget
}

///|
pub extend Options with @debug.Debug::{to_repr}

///|
/// Reproducible defaults, using seed 726 and eight initial starts.
pub fn Options::default() -> Options {
  {
    seed: 726U,
    starts: 8,
    search_nodes: 100000,
    refinement: @refine.RefinementBudget::default(),
  }
}

///|
/// A complete result independently revalidated on the original graph.
#derive(Debug)
pub struct PartitionResult {
  assignment : Array[Int32]
  metrics : @metrics.Metrics
  initial_cut : Int64
  starts_tried : Int32
  search_nodes : Int32
  options : Options
  refinement : @refine.RefineResult
}

///|
pub extend PartitionResult with @debug.Debug::{to_repr}

///|
/// Find a feasible weighted bipartition and improve cut-net within explicit bounds.
/// Returns no partial assignment on construction, option or validation failure.
pub fn partition(
  graph : @model.Hypergraph,
  capacities : Array[Int64],
  options~ : Options = Options::default(),
) -> Result[PartitionResult, @initial.SolveError] {
  let initial = match
    @initial.construct(
      graph,
      capacities,
      seed=options.seed,
      starts=options.starts,
      search_nodes=options.search_nodes,
    ) {
    Ok(initial) => initial
    Err(error) => return Err(error)
  }
  let refined = match
    @refine.refine(
      graph,
      initial.assignment,
      capacities,
      budget=options.refinement,
    ) {
    Ok(refined) => refined
    Err(error) => return Err(error)
  }
  let metrics = match @metrics.verify(graph, refined.assignment, capacities) {
    Ok(metrics) => metrics
    Err(error) => return Err({ kind: "internal", message: error.message, })
  }
  if metrics.cut_net > initial.metrics.cut_net {
    return Err({
      kind: "internal",
      message: "refinement worsened the initial objective",
    })
  }
  Ok({
    assignment: refined.assignment,
    metrics,
    initial_cut: initial.metrics.cut_net,
    starts_tried: initial.starts_tried,
    search_nodes: initial.search_nodes,
    options,
    refinement: refined,
  })
}

///|
/// Serialize measurements, seed, work limits and actual refinement work.
pub fn result_json(
  graph : @model.Hypergraph,
  result : PartitionResult,
) -> String {
  let budget = result.options.refinement
  let limits : Map[String, @json.Json] = {
    "passes": @json.Json::number(budget.max_passes.to_double()),
    "moves": @json.Json::number(budget.max_moves.to_double()),
    "swap_trials": @json.Json::number(budget.max_swap_trials.to_double()),
    "candidates": @json.Json::number(budget.max_candidates.to_double()),
    "search_nodes": @json.Json::number(result.options.search_nodes.to_double()),
  }
  let run : Map[String, @json.Json] = {
    "seed": @json.Json::number(result.options.seed.to_double()),
    "starts": @json.Json::number(result.starts_tried.to_double()),
    "initial_cut": @json.Json::string(result.initial_cut.to_string()),
    "search_nodes_used": @json.Json::number(result.search_nodes.to_double()),
    "moves": @json.Json::number(result.refinement.moves.to_double()),
    "swaps": @json.Json::number(result.refinement.swaps.to_double()),
    "passes": @json.Json::number(result.refinement.passes.to_double()),
    "rolled_back": @json.Json::number(result.refinement.rolled_back.to_double()),
    "budget_limited": @json.Json::boolean(result.refinement.budget_limited),
    "budget": @json.Json::object(limits),
  }
  @report.metrics_json(graph, result.metrics, run=@json.Json::object(run))
}
