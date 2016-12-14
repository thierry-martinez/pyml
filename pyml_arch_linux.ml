let library_patterns: (int -> int -> string, unit, string) format list =
  ["libpython%d.%dm.so"; "libpython%d.%d.so"]

let library_suffix = ".so"

external fd_of_int: int -> Unix.file_descr = "%identity"
