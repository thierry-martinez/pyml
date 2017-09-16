external get_pyarray_type: Py.Object.t -> Py.Object.t = "get_pyarray_type"

external pyarray_of_bigarray: Py.Object.t -> Py.Object.t
  -> ('a, 'b, 'c) Bigarray.Genarray.t
  -> Py.Object.t = "pyarray_of_bigarray_wrapper"

external bigarray_of_pyarray: Py.Object.t -> Py.Object.t
  -> ('a, 'b) Bigarray.kind * 'c Bigarray.layout * ('a, 'b, 'c) Bigarray.Genarray.t
  = "bigarray_of_pyarray_wrapper"

let pyarray_subtype_ref = ref None

let () = Py.on_finalize (fun () -> pyarray_subtype_ref := None)

let pyarray_subtype () =
  match !pyarray_subtype_ref with
    Some pyarray_subtype -> pyarray_subtype
  | None ->
     let pyarray_type = Py.Array.pyarray_type () in
     let pyarray_subtype =
       Py.Type.create "ocamlbigarray" [pyarray_type]
         [("ocamlbigarray", Py.none)] in
     pyarray_subtype_ref := Some pyarray_subtype;
     pyarray_subtype

let of_bigarray bigarray =
  let result =
    pyarray_of_bigarray (Py.Array.numpy_api ()) (pyarray_subtype ()) bigarray in
  let result = Py.check_not_null result in
  let capsule = Py.Capsule.unsafe_wrap_value bigarray in
  Py.Object.set_attr_string result "ocamlbigarray" capsule;
  result

let to_bigarray kind layout t =
  let kind', layout', array = bigarray_of_pyarray (Py.Array.numpy_api ()) t in
  if kind <> kind' then
    failwith "Unexpected kind";
  if layout <> layout' then
    failwith "Unexpected layout";
  array
