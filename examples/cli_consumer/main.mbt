///|
fn main raise {
  let graph = @hyperpart.parse("3 6 1\n10 1 2 3\n10 4 5 6\n1 3 4\n").unwrap()
  let options : @hyperpart.Options = { ..@hyperpart.Options::default(), starts: 1 }
  let result = @hyperpart.partition(graph, [3L, 3L], options~).unwrap()
  let checked = @hyperpart.verify(graph, result.assignment, [3L, 3L]).unwrap()
  assert_eq(checked.cut_net, 1L)
  println(@hyperpart.result_json(graph, result))
  println(@hyperpart.partition_text(graph, result.assignment, [3L, 3L]).unwrap())
}
