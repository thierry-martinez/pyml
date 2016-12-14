let library_patterns: (int -> int -> string, unit, string) format list =
  ["python%d%d.dll"]

let library_suffix = ".dll"

external fd_of_int: int -> Unix.file_descr = "win_handle_fd"
