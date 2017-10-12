type sys_floatarray = floatarray

type floatarray = sys_floatarray

let floatarray_create = Array.Floatarray.create

let floatarray_length = Array.Floatarray.length

let floatarray_get = Array.Floatarray.get

let floatarray_set = Array.Floatarray.set

let lowercase = String.lowercase_ascii

let mapi = List.mapi

let lazy_from_fun = Lazy.from_fun

let trim = String.trim

let index_opt = String.index_opt

let index_from_opt = String.index_from_opt

let split_on_char = String.split_on_char

let list_find_opt = List.find_opt

let getenv_opt = Sys.getenv_opt
