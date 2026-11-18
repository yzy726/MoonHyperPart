///|
async fn main {
  let command = match @cli.parse_args(@env.args()[1:].to_owned()) {
    Ok(command) => command
    Err(error) => {
      println(@lib.error_json(error))
      @env.exit(2)
    }
  }
  if command.action == "help" {
    println(@cli.help())
    return
  }
  let code = execute(command) catch {
    error => {
      println(
        @lib.error_json({ code: "io", line: 0, message: error.to_string(), }),
      )
      5
    }
  }
  if code != 0 {
    @env.exit(code)
  }
}
