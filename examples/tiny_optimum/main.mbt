///|
fn main raise {
  let graph = @hyperpart.parse("3 6 1\n10 1 2 3\n10 4 5 6\n1 3 4\n").unwrap()
  let options : @hyperpart.Options = {
    ..@hyperpart.Options::default(),
    starts: 1,
  }
  let result = @hyperpart.partition(graph, [3L, 3L], options~).unwrap()
  let mut optimum = 9223372036854775807L
  for mask in 0..<64 {
    let parts = Array::makei(6, fn(v) { (mask >> v) & 1 })
    if @hyperpart.verify(graph, parts, [3L, 3L]) is Ok(metrics) {
      if metrics.cut_net < optimum {
        optimum = metrics.cut_net
      }
    }
  }
  assert_eq(optimum, 1L)
  assert_eq(result.metrics.cut_net, optimum)
  assert_eq(result.metrics.part_weights, (3L, 3L))
  println(@hyperpart.result_json(graph, result))
}
