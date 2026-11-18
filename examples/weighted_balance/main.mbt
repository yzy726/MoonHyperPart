///|
fn main raise {
  let graph = @hyperpart.build([2L, 2L, 1L, 1L], [[0, 2], [1, 3]], [8L, 9L]).unwrap()
  let capacity = @hyperpart.uniform_capacity(graph.total_vertex_weight(), 0).unwrap()
  let refined = @refine.refine(graph, [0, 1, 1, 0], [capacity, capacity]).unwrap()
  assert_eq(refined.initial_cut, 17L)
  assert_eq(refined.metrics.cut_net, 0L)
  assert_eq(refined.metrics.part_weights, (3L, 3L))
  assert_true(refined.swaps > 0)
  println(@hyperpart.metrics_json(graph, refined.metrics))
}
