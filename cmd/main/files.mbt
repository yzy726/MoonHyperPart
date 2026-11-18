///|
priv suberror OutputFailure {
  OutputFailure(String)
}

///|
// Open once, bound the allocation, then reject growth past the observed size.
async fn read_limited(
  path : String,
  limit : Int32,
) -> Result[String, @lib.InputError] {
  let file = @fs.open(path, mode=@fs.ReadOnly)
  defer file.close()
  let size = file.size()
  if size < 0L || size > limit.to_int64() {
    return Err({
      code: "limit",
      line: 0,
      message: "input file exceeds byte limit",
    })
  }
  let bytes = file.read_exactly(size.to_int())
  if file.read() is Some(extra) {
    if !extra.is_empty() {
      return Err({
        code: "limit",
        line: 0,
        message: "input changed while being read",
      })
    }
  }
  let text = @utf8.decode(bytes) catch {
    _ =>
      return Err({ code: "utf8", line: 0, message: "input is not valid UTF-8", })
  }
  Ok(text)
}

///|
async fn stage_file(
  path : String,
  content : String,
  owned : Array[String],
) -> Unit {
  let file = @fs.open(path, mode=@fs.WriteOnly, create_mode=@fs.CreateNew)
  owned.push(path)
  defer file.close()
  file.write(@utf8.encode(content))
  file.sync()
}

///|
// Stage every artifact before publishing names. Only newly created paths are removed on failure.
async fn write_outputs(outputs : Array[(String, String)]) -> Unit {
  let owned : Array[String] = []
  let published : Array[String] = []
  try {
    for pair in outputs {
      if @fs.exists(pair.0) {
        raise OutputFailure("output already exists: " + pair.0)
      }
      stage_file(pair.0 + ".moonhyperpart.tmp", pair.1, owned)
    }
    for pair in outputs {
      @fs.rename(pair.0 + ".moonhyperpart.tmp", pair.0, replace=false)
      published.push(pair.0)
    }
  } catch {
    error => {
      let mut message = error.to_string()
      for path in published {
        @fs.remove(path, allow_missing=true) catch {
          cleanup => message += "; cleanup failed: " + cleanup.to_string()
        }
      }
      for path in owned {
        @fs.remove(path, allow_missing=true) catch {
          cleanup => message += "; cleanup failed: " + cleanup.to_string()
        }
      }
      raise OutputFailure(message)
    }
  }
}
