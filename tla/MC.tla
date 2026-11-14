---- MODULE MC ----
EXTENDS PymlThreads
\* o1: an OCaml thread of domain 1 (with the Python threads); o2: a domain.
MCODom(t) == IF t = "o1" THEN 1 ELSE 2
====
