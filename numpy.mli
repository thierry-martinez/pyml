val of_bigarray:
  ('a, 'b, 'c) Bigarray.Genarray.t -> Py.Object.t
(** [of_bigarray a] returns a Numpy array that shares the same contents
    than the OCaml array [a].
    The array is passed in place (without copy): Python programs can
    change the contents of the array and the changes are visible in
    the OCaml array. *)

val to_bigarray:
  ('a, 'b) Bigarray.kind -> 'c Bigarray.layout -> Py.Object.t ->
    ('a, 'b, 'c) Bigarray.Genarray.t
(** [to_bigarray kind layout a] returns a bigarray that shares the same
    contents than the Numpy array [a].
    [kind] and [layout] should match the Numpy format of the array.
    The array is passed in place (without copy): OCaml programs can
    change the contents of the array and the changes are visible in
    the Numpy array. *)
