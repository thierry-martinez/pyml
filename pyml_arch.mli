type t = Linux | Windows | Macos

val os : t

val fd_of_int: int -> Unix.file_descr
