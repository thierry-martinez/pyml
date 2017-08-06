let lowercase = String.lowercase_ascii

let mapi = List.mapi

let lazy_from_fun = Lazy.from_fun

let trim = String.trim

let index_opt string c = Pyutils.option_find (String.index string) c

let index_from_opt string from c =
  Pyutils.option_find (String.index_from string from) c

let split_on_char = String.split_on_char

let list_find_opt p l = Pyutils.option_find (List.find p) l

let getenv_opt var = Pyutils.option_find Sys.getenv var
