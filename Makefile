OCAMLFIND=ocamlfind

HAVE_OCAMLFIND:=$(shell \
	if $(OCAMLFIND) query -help >/dev/null 2>&1; then \
		echo yes; \
	else \
		echo no; \
	fi \
)

OCAMLC:=$(shell \
	if [ "$(HAVE_OCAMLFIND)" = yes ]; then \
		echo $(OCAMLFIND) ocamlc; \
	elif ocamlc.opt -version >/dev/null 2>&1; then \
		echo ocamlc.opt; \
	else \
		echo ocamlc; \
	fi \
)
OCAMLOPT:=$(shell \
	if [ "$(HAVE_OCAMLFIND)" = yes ]; then \
		echo $(OCAMLFIND) ocamlopt; \
	elif ocamlopt.opt -version >/dev/null 2>&1; then \
		echo ocamlopt.opt; \
	else \
		echo ocamlopt; \
	fi \
)
OCAMLMKLIB:=$(shell \
	if [ "$(HAVE_OCAMLFIND)" = yes ]; then \
		echo $(OCAMLFIND) ocamlmklib; \
	else \
		echo ocamlmklib; \
	fi \
)
OCAMLDEP:=$(shell \
	if [ "$(HAVE_OCAMLFIND)" = yes ]; then \
		echo $(OCAMLFIND) ocamldep; \
	else \
		echo ocamldep; \
	fi \
)
OCAMLDOC:=$(shell \
	if [ "$(HAVE_OCAMLFIND)" = yes ]; then \
		echo $(OCAMLFIND) ocamldoc; \
	else \
		echo ocamldoc; \
	fi \
)

MODULES=pyml_compat pytypes pywrappers py pycaml_compat

VERSION:=$(shell date "+%Y%m%d")

OCAMLLIBFLAGS=-cclib "-L. -lpyml_stubs"

OCAMLLIBFLAGSNATIVE=$(OCAMLLIBFLAGS)
OCAMLLIBFLAGSBYTECODE=-custom $(OCAMLLIBFLAGS)

OCAMLVERSION:=$(shell $(OCAMLC) -version)

PYML_COMPAT:=$(shell \
	if [ "$(OCAMLVERSION)" "<" 4.00.0 ]; then \
		echo pyml_compat312.ml; \
	elif [ "$(OCAMLVERSION)" "<" 4.03.0 ]; then \
		echo pyml_compat400.ml; \
	else \
		echo pyml_compat403.ml; \
	fi \
)

.PHONY: all
all: py.cmi pycaml_compat.cmi pyml.cma pyml.cmxa pyml.cmxs doc

.PHONY: tests
tests: pyml_tests
	./pyml_tests

.PHONY: tests.bytecode
tests.bytecode: pyml_tests.bytecode
	./pyml_tests.bytecode

.PHONY: install
install:
	$(OCAMLFIND) install pyml \
		py.mli \
		py.cmi pytypes.cmi pywrappers.cmi pycaml_compat.cmi \
		py.cmx pytypes.cmx pywrappers.cmx pycaml_compat.cmx \
		pyml.cma pyml.cmxa pyml.cmxs pyml.a \
		libpyml_stubs.a dllpyml_stubs.so \
		META

.PHONY: clean
clean:
	for module in $(MODULES) generate pyml_tests; do \
		rm -f $$module.cmi $$module.cmo $$module.cmx $$module.a $$module.o; \
	done
	rm -f pyml.cma pyml.cmxa pyml.cmxs pyml.a
	rm -f pywrappers.mli pywrappers.ml pyml_dlsyms.inc pyml_wrappers.inc
	rm -f pyml.h
	rm -f pyml_stubs.o dllpyml_stubs.so libpyml_stubs.a
	rm -f pyml_compat.ml
	rm -f generate pyml_tests pyml_tests.bytecode
	rm -f .depend
	rm -rf doc

.PHONY: tarball
tarball:
	git archive --format=tar.gz HEAD >pyml-$(VERSION).tar.gz

doc: py.mli pycaml_compat.mli pywrappers.ml
	mkdir -p $@
	$(OCAMLDOC) -html -d $@ $^
	touch $@

ifneq ($(MAKECMDGOALS),clean)
-include .depend
endif

.depend: $(MODULES:=.ml) $(MODULES:=.mli) pyml_tests.ml
	$(OCAMLDEP) $^ >$@

generate: pyml_compat.cmx generate.cmx
	$(OCAMLOPT) $^ -o $@

generate.cmx: generate.ml pyml_compat.cmi pyml_compat.cmx

pywrappers.ml pyml_wrappers.inc: generate
	./generate

pyml_wrappers.inc: pywrappers.ml

pywrappers.mli: pywrappers.ml pytypes.cmi
	$(OCAMLC) -i $< >$@

pyml_tests: py.cmi pyml.cmxa pyml_tests.cmx
	$(OCAMLOPT) $(OCAMLLDFLAGS) unix.cmxa pyml.cmxa pyml_tests.cmx -o $@

pyml_tests.bytecode: py.cmi pyml.cma pyml_tests.cmo
	$(OCAMLC) unix.cma pyml.cma pyml_tests.cmo -o $@

pyml_compat.ml: $(PYML_COMPAT)
	cp $< $@

pyml_compat.cmx: pyml_compat.cmi

%.cmi: %.mli
	$(OCAMLC) $(OCAMLCFLAGS) -c $< -o $@

%.cmo: %.ml
	$(OCAMLC) $(OCAMLCFLAGS) -c $< -o $@

%.cmx: %.ml
	$(OCAMLOPT) $(OCAMLCFLAGS) -c $< -o $@

pyml_stubs.o: pyml_stubs.c pyml_wrappers.inc
	$(OCAMLC) -c $< -o $@

pyml.cma: $(MODULES:=.cmo) libpyml_stubs.a
	$(OCAMLC) $(OCAMLLIBFLAGSBYTECODE) -a $(MODULES:=.cmo) -o $@

pyml.cmxa: $(MODULES:=.cmx) libpyml_stubs.a
	$(OCAMLOPT) $(OCAMLLIBFLAGSNATIVE) -a $(MODULES:=.cmx) -o $@

pyml.cmxs: $(MODULES:=.cmx) libpyml_stubs.a
	$(OCAMLOPT) $(OCAMLLIBFLAGSNATIVE) -shared $(MODULES:=.cmx) -o $@

libpyml_stubs.a: pyml_stubs.o
	$(OCAMLMKLIB) -o pyml_stubs $<
