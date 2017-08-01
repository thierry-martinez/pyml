``py.ml``: OCaml bindings for Python
====================================

``py.ml`` provides OCaml bindings for Python 2 and Python 3.
This library subsumes the ``pycaml`` library, which is no longer
actively maintained.

*Homepage:* http://pyml.gforge.inria.fr

*Documentation:* http://pyml.gforge.inria.fr/doc

*Git:* ``git clone http://pyml.gforge.inria.fr/pyml.git``

*Git Repository Browser:* http://pyml.gforge.inria.fr/browser

*Tracker for bug reports and feature requests:*
http://pyml.gforge.inria.fr/tracker

*OPAM:* ``opam install pyml``

The Python library is linked at runtime and the same executable can be
run in a Python 2 or a Python 3 environment. ``py.ml`` does not
require any Python library at compile time, nor any other
dependency.

Bindings are split in three modules:

- ``Py`` provides the initialization functions and some high-level
  bindings, with error handling and naming conventions closer to OCaml
  usages.

- ``Pycaml`` provides a signature close to the old ``Pycaml``
  module, so as to ease migration.

- ``Pywrappers`` provides low-level bindings, which follow closely the
  conventions of the C bindings for Python. Submodules
  ``Pywrappers.Python2`` and ``Pywrappers.Python3`` contain version-specific
  bindings.


Custom top-level
----------------

A custom top-level with the C bindings can be compiled by ``make pymltop``.

If you have ``utop`` and ``ocamlfind``, you can ``make pymlutop``.

*For OPAM users:* ``pymltop`` is installed by default by ``opam install pyml``.
``pymlutop`` is installed whenever ``utop`` is available.

Getting started
---------------

``Py.initialize ()`` loads the Python library.

``Py.Run.simple_string "print('Hello, world!')"`` executes a Python phrase.

``Py.Run.eval "18 + 42"`` evaluates a Python phrase and returns a value
of type ``Py.Object.t``. Such a value can then be converted to an OCaml
value: ``assert (Py.Int.to_int (Py.Run.eval "18 + 42") = 60)``.

To make an OCaml value accessible from Python, we create a module (called
``ocaml`` in this example, but it can be any valid Python module name):

```ocaml
	let m = Py.Import.add_module "ocaml" in
	Py.Module.set m "example_value" (Py.List.of_list_map Py.Int.of_int [1;2;3]);
	Py.Run.simple_string "
	from ocaml import example_value
	print(example_value)"
```

OCaml functions can be passed in the same way.

``` ocaml
	let m = Py.Import.add_module "ocaml" in
	let hello args =
	  Printf.printf "Hello, %s!\n" (Py.String.to_string args.(0));
	  Py.none in
	Py.Module.set m "hello" (Py.Callable.of_function_array hello);
	Py.Run.simple_string "
	from ocaml import hello
	hello('World')"
```

And Python functions can be called from OCaml too.

```ocaml
	let builtins = Py.Eval.get_builtins () in
	let sorted_python = Py.Dict.find_string builtins "sorted" in
	let sorted = Py.Callable.to_function_array sorted_python in
	let result = sorted [| Py.List.of_list_map Py.Float.of_float [3.0; 2.0] |] in
	assert (Py.List.to_list_map Py.Float.to_float result = [2.0; 3.0])
```

NumPy
-----

If the NumPy library is installed, then OCaml float arrays can be shared
in place with Python code as NumPy arrays (without copy).
Python code can then directly read and write from and to the OCaml arrays
and changes are readable from OCaml.

```ocaml
	let array = [| 1.; 2. ; 3. |] in
	let m = Py.Import.add_module "ocaml" in
	Py.Module.set m "array" (Py.Array.numpy array);
	assert (Py.Run.simple_string "
	from ocaml import array
	array *= 2" = true);
	assert (array = [| 2.; 4.; 6. |])
```
