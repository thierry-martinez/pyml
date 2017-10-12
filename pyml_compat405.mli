type floatarray = float array

val floatarray_create : int -> floatarray

val floatarray_length : floatarray -> int

val floatarray_get: floatarray -> int -> float

val floatarray_set: floatarray -> int -> float -> unit

val lowercase: string -> string

val mapi: (int -> 'a -> 'b) -> 'a list -> 'b list

val lazy_from_fun: (unit -> 'a) -> 'a Lazy.t

val trim: string -> string

val index_opt: string -> char -> int option

val index_from_opt: string -> int -> char -> int option

val split_on_char: char -> string -> string list

val list_find_opt: ('a -> bool) -> 'a list -> 'a option

val getenv_opt: string -> string option
