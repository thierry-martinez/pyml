let library_patterns: (int -> int -> string, unit, string) format list =
  ["libpython%d.%dm.dylib"; "libpython%d.%d.dylib"]

let library_suffix = ".dylib"
