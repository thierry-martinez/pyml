(** List of possible names for libpython given major and minor versions.
    On Linux, "libpython%d.%d.so"; on Mac OS X, "libpython%d.%d.dylib";
    on Windows, "python%d%d.dll". There may be some variants to try,
    like "libpython%d.%dm.so", so we return a list. *)
val library_patterns: (int -> int -> string, unit, string) format list

(** Suffix to add to library names returned by pkg-config (".so" on Linux,
    ".dylib" on Mac OSX, we don't use pkg-config on Windows) *)
val library_suffix: string

(** Ensure that the executable has the ".exe" suffix on Windows, do nothing
    on other platforms. *)
val ensure_executable_suffix: string -> string

(** The tool to search in PATH: "which" on Unix/Mac OS X; "where" on Windows. *)
val which: string

(** Convert a file descriptor index to a file descriptor usable in
    OCaml.  It is the identity on Unix and Mac OS X, and the stdlib
    "win_handle_fd" C stub on Windows. *)
val fd_of_int: int -> Unix.file_descr

(** Separator between paths in PATH environment variable. ":" on Unix/Mac OS X;
    ";" on Windows. *)
val path_separator: string
