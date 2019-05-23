[*] marks changes that break compatibility with previous versions.

Next version
============
- Support for debug build of Python library
  (Suggested by Arlen Cox:
   https://github.com/thierry-martinez/pyml/issues/18)
- Bug fix in pyml_check_symbol_available
- `Py.compile` is a wrapper for the built-in function `compile`
  (Suggested by Dhruv Makwana:
   https://github.com/thierry-martinez/pyml/issues/25)
- Guarantees for structural and physical equalities on `Py.Object.t`
  are now documented. New predicates Py.is_none, Py.is_null, Py.Bool.is_true,
  Py.Bool.is_false, Py.Tuple.is_empty.
  (Suggested by Laurent Mazare:
   https://github.com/thierry-martinez/pyml/pull/31)
- Fix Py.Array.numpy to handle OCaml GC's moving the floatarray
  (Reported by Ilias Garnier:
   https://github.com/thierry-martinez/pyml/issues/30)

2018-05-30
==========

- `Py.import` is an alias for `Py.Import.import_module`.
- Use `*_opt` naming convention for the functions that return an option
  instead of an exception: `Py.import_opt`, `Py.Object.find_opt`,...
- of_seq/to_seq converters
- [*] get_attr/get_attr_string now returns option type
- Indexing operators (for OCaml 4.06.0 and above) defined in Pyops