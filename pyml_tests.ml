type status =
  | Passed
  | Failed of string
  | Disabled of string

let tests = Queue.create ()

let add_test ~title f =
  Queue.add (title, f) tests

let failed = ref false

let launch_test (title, f) =
  Printf.printf "Test '%s' ... %!" title;
  try
    match f () with
      Passed -> Printf.printf "passed\n%!"
    | Failed reason ->
       Printf.printf "failed: %s\n%!" reason;
       failed := true
    | Disabled reason -> Printf.printf "disabled: %s\n%!" reason
  with
    Py.E (_, value) ->
    Printf.printf
      "raised a Python exception: %s\n%!"
      (Py.Object.to_string value);
    failed := true
  | e ->
     Printf.printf "raised an exception: %s\n%!" (Printexc.to_string e);
     failed := true

let rec launch_tests () =
  match
    try Some (Queue.pop tests)
    with Queue.Empty -> None
  with
    None -> ()
  | Some test ->
      launch_test test;
      launch_tests ()

let enable_only_on_unix f arg =
  if Sys.os_type = "Unix" then
    f arg
  else
    Disabled "only on Unix"

let () =
  add_test
    ~title:"version"
    (fun () ->
      Printf.printf "Python version %s\n%!" (Py.version ());
      Passed
    )

let () =
  add_test
    ~title:"library version"
    (fun () ->
      Printf.printf "Python library version %s\n%!" (Py.get_version ());
      Passed
    )

let () =
  add_test
    ~title:"hello world"
    (fun () ->
      assert (Py.Run.simple_string "print('Hello world!')");
      Passed
    )

let () =
  add_test
    ~title:"class"
    (fun () ->
      let m = Py.Import.add_module "test" in
      let value_obtained = ref None in
      let callback arg =
        value_obtained := Some (Py.String.to_string (Py.Tuple.get_item arg 1));
        Py.none in
      let c =
        Py.Class.init (Py.String.of_string "myClass")
          ~methods:[("callback", callback)] in
      Py.Module.set m "myClass" c;
      assert (Py.Run.simple_string "
from test import myClass
myClass().callback('OK')
");
      assert (!value_obtained = Some "OK");
      Passed
    )

let () =
  add_test
    ~title:"empty tuple"
    (fun () ->
      assert (Py.Tuple.create 0 = Py.Tuple.empty);
      Passed
    )

let () =
  add_test
    ~title:"make tuple"
    (fun () ->
      assert
        (Py.Tuple.to_singleton (Py.Tuple.singleton (Py.Long.of_int 0))
           = Py.Long.of_int 0);
      Passed
    )

let () =
  add_test
    ~title:"module get/set/remove"
    (fun () ->
      let m = Py.Module.create "test" in
      Py.Module.set m "test" Py.none;
      assert (Py.Module.get m "test" = Py.none);
      Py.Module.remove m "test";
      begin
        try
          ignore (Py.Module.get m "test");
          Failed "Should have been removed"
        with Py.E _ -> Passed
      end)

let () =
  add_test
    ~title:"capsule"
    (fun () ->
      let (wrap, unwrap) = Py.Capsule.make "string" in
      let m = Py.Import.add_module "test" in
      let pywrap args =
        let s = Py.String.to_string args.(0) in
        wrap s in
      let pyunwrap args =
        let s = unwrap args.(0) in
        Py.String.of_string s in
      Py.Module.set m "wrap" (Py.Callable.of_function_array pywrap);
      Py.Module.set m "unwrap" (Py.Callable.of_function_array pyunwrap);
      assert (Py.Run.simple_string "
from test import wrap, unwrap
x = wrap('OK')
print('Capsule type: {}'.format(x))
assert unwrap(x) == 'OK'
");
      Passed
    )

let () =
  add_test
    ~title:"exception"
    (fun () ->
      try
        let _ = Py.Run.eval ~start:Py.File "
raise Exception('Great')
" in
        Failed "uncaught exception"
      with Py.E (_, value) ->
        assert (Py.Object.to_string value = "Great");
        Passed)

let () =
  add_test
    ~title:"ocaml exception"
    (fun () ->
      let m = Py.Import.add_module "test" in
      let f _ =
        raise (Py.Err (Py.Err.Exception, "Great")) in
      let mywrap = Py.Callable.of_function f in
      Py.Module.set m "mywrap" mywrap;
      assert (Py.Run.simple_string "
from test import mywrap
try:
    mywrap()
    raise Exception('No exception raised')
except Exception as err:
    assert str(err) == \"Great\"
");
      Passed
    )

let () =
  add_test
    ~title:"ocaml other exception"
    (fun () ->
      let m = Py.Import.add_module "test" in
      let f _ = raise Exit in
      let mywrap = Py.Callable.of_function f in
      Py.Module.set m "mywrap" mywrap;
      try
        assert (Py.Run.simple_string "
from test import mywrap
try:
    mywrap()
except Exception as err:
    raise Exception('Should not be caught by Python')
");
        Failed "Uncaught exception"
      with Exit ->
        Passed
    )

let () =
  add_test
    ~title:"run file with filename"
    (fun () ->
      let result = Pyutils.with_temp_file "print(\"Hello, world!\")"
        begin fun file channel ->
         Py.Run.load (Py.Filename file) "test.py"
        end in
      if result = Py.none then
        Passed
      else
        let result_str = Py.Object.to_string result in
        let msg = Printf.sprintf "Result None expected but got %s" result_str in
        Failed msg
    )

let () =
  add_test
    ~title:"run file with channel"
    (enable_only_on_unix
       (fun () ->
         let result = Pyutils.with_temp_file "print(\"Hello, world!\")"
           begin fun file channel ->
           Py.Run.load (Py.Channel channel) "test.py"
           end in
         if result = Py.none then
           Passed
         else
           let result_str = Py.Object.to_string result in
           let msg = Printf.sprintf "Result None expected but got %s" result_str in
           Failed msg
       )
    )

let () =
  add_test
    ~title:"boolean"
    (fun () ->
      try
        if not (Py.Bool.to_bool (Py.Run.eval "True")) then
          Failed "true is false"
        else if Py.Bool.to_bool (Py.Run.eval "False") then
          Failed "false is true"
        else
          Passed;
      with Py.E (_, value) ->
        Failed (Py.Object.to_string value))

let () =
  add_test
    ~title:"reinitialize"
    (fun () ->
      Py.finalize ();
      begin
        try
          assert (Py.Run.simple_string "not initialized");
          raise Exit
        with
          Failure _ -> ()
        | Exit -> failwith "Uncaught not initialized"
      end;
      Py.initialize ();
      Passed
    )

let () =
  add_test
    ~title:"string conversion error"
    (fun () ->
      try
        let _ = Py.String.to_string (Py.Long.of_int 0) in
        Failed "uncaught exception"
      with
        Py.E (_, value) ->
          Printf.printf "Caught exception: %s\n%!" (Py.Object.to_string value);
          Passed
      | Failure s ->
          Printf.printf "Caught failure: %s\n%!" s;
          Passed)

let () =
  add_test
    ~title:"float conversion error"
    (fun () ->
      try
        let _ = Py.Float.to_float (Py.String.of_string "a") in
        Failed "uncaught exception"
      with Py.E (_, value) ->
        Printf.printf "Caught exception: %s\n%!" (Py.Object.to_string value);
        Passed)

let () =
  add_test
    ~title:"long conversion error"
    (fun () ->
      try
        let _ = Py.Long.to_int (Py.String.of_string "a") in
        Failed "uncaught exception"
      with Py.E (_, value) ->
        Printf.printf "Caught exception: %s\n%!" (Py.Object.to_string value);
        Passed)

let () =
  add_test
    ~title:"iterators"
    (fun () ->
      let iter = Py.Object.get_iter (Py.Run.eval "['a','b','c']") in
      let list = Py.Iter.to_list_map Py.String.to_string iter in
      assert (list = ["a"; "b"; "c"]);
      Passed)

let () =
  add_test
    ~title:"Dict.iter"
    (fun () ->
      let dict = Py.Dict.create () in
      for i = 0 to 9 do
        Py.Dict.set_item_string dict (string_of_int i) (Py.Long.of_int i)
      done;
      let table = Array.make 10 None in
      Py.Dict.iter begin fun key value ->
        let index = Py.Long.to_int value in
        assert (table.(index) = None);
        table.(index) <- Some (Py.String.to_string key)
      end dict;
      Array.iteri begin fun i v ->
        match v with
          None -> failwith "None!"
        | Some v' -> assert (i = int_of_string v')
      end table;
      Passed)

let () =
  add_test
    ~title:"unicode"
    (fun () ->
      let codepoints = [| 8203; 127; 83; 2384; 0; 12 |] in
      let python_string = Py.String.of_unicode codepoints in
      let ocaml_string = Py.String.to_string python_string in
      let python_string' = Py.String.decode_UTF8 ocaml_string in
      let codepoints' = Py.String.to_unicode python_string' in
      assert (codepoints = codepoints');
      Passed
    )

let () =
  add_test
    ~title:"interactive loop"
    (enable_only_on_unix (fun () ->
      Pyutils.with_stdin_from_string "42"
        Py.Run.interactive ();
      assert (Py.Long.to_int (Py.last_value ()) = 42);
      Passed))

let () =
  add_test
    ~title:"IPython"
    (enable_only_on_unix (Py.Run.frame (Pyutils.with_stdin_from_string "exit" (fun () ->
      if Py.Import.try_import_module "IPython" = None then
        Disabled "IPython is not available"
      else
        begin
          Py.Run.ipython ~frame:false ();
          Passed
        end))))

let () =
  add_test
    ~title:"Marshal"
    (fun () ->
      let v = Py.Long.of_int 42 in
      let m = Py.Marshal.dumps v in
      let v' = Py.Marshal.loads m in
      assert (Py.Long.to_int v' = 42);
      Passed)

let () =
  add_test
    ~title:"Py.List.of_list"
    (fun () ->
      let v = Py.List.of_list [Py.Long.of_int 42] in
      assert (Py.List.length v = 1);
      assert (Py.Long.to_int (Py.List.get v 0) = 42);
      Passed)

let () =
  add_test ~title:"array"
    (fun () ->
      let array = [| 1; 2 |] in
      let a = Py.Array.of_array Py.Long.of_int Py.Long.to_int array in
      let m = Py.Import.add_module "test" in
      Py.Module.set m "array" a;
      assert (Py.Run.simple_string "
from test import array
assert len(array) == 2
assert array[0] == 1
assert array[1] == 2
array[0] = 42
array[1] = 43
copy = []
for x in array:
  copy.append(x)
assert copy == [42, 43]
");
      assert (array.(0) = 42);
      assert (array.(1) = 43);
      Passed)

let () =
  add_test ~title:"numpy"
    (fun () ->
      if Py.Import.try_import_module "numpy" = None then
        Disabled "numpy is not available"
      else
        begin
          let array = [| 1.; 2. |] in
          let a = Py.Array.numpy array in
          let m = Py.Import.add_module "test" in
          Py.Module.set m "array" a;
          assert (Py.Run.simple_string "
from test import array
assert len(array) == 2
assert array[0] == 1.
assert array[1] == 2.
array[0] = 42.
array[1] = 43.
");
          assert (array.(0) = 42.);
          assert (array.(1) = 43.);
          Passed
        end)

let show_environment_variable envvar =
  try
    Printf.eprintf "%s=%s\n" envvar (Sys.getenv envvar)
  with Not_found ->
    Printf.eprintf "%s not set\n" envvar

let () =
  prerr_endline "Environment variables:";
  show_environment_variable "PATH";
  show_environment_variable "PYTHONHOME";
  show_environment_variable "DYLD_LIBRARY_PATH";
  show_environment_variable "DYLD_FALLBACK_LIBRARY_PATH";
  prerr_endline "Initializing library...";
  Py.initialize ~verbose:true ();
  begin
    match Py.get_library_filename () with
      None -> prerr_endline "No library has been loaded.\n"
    | Some filename -> Printf.eprintf "Library \"%s\" has been loaded.\n" filename
  end;
  prerr_endline "Starting tests...";
  launch_tests ();
  if !failed then
    exit 1
