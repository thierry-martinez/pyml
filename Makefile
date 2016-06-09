OCAMLC=ocamlc.opt
OCAMLOPT=ocamlopt.opt
OCAMLMKLIB=ocamlmklib
OCAMLDEP=ocamldep

MODULES=pyml_compat pytypes pywrappers py pycaml_compat
GENERATED=pyml_dlsyms.inc pyml_wrappers.inc pyml.h

VERSION=$(shell date "+%Y%m%d")

OCAMLLIBFLAGS=-cclib "-L$(PWD) -lpyml_stubs"

OCAMLLIBFLAGSNATIVE=$(OCAMLLIBFLAGS)
OCAMLLIBFLAGSBYTECODE=-custom $(OCAMLLIBFLAGS)

#OCAMLLIBFLAGS=-ccopt "`pkg-config --cflags python2`"
#OCAMLLDFLAGS=-cclib "`pkg-config --libs python2`"

OCAMLVERSION=$(shell $(OCAMLC) -version)

PYML_COMPAT=$(shell \
	if [ "$(OCAMLVERSION)" "<" 4.03.0 ]; then \
	  echo pyml_compat312.ml; \
	else \
	  echo pyml_compat403.ml; \
	fi \
)

all: py.cmi pycaml_compat.cmi pyml.cma pyml.cmxa doc

.PHONY: all tests tests.bytecode clean

tests: pyml_tests
	./pyml_tests

tests.bytecode: pyml_tests.bytecode
	./pyml_tests.bytecode

doc: pywrappers.ml py.mli pycaml_compat.mli
	mkdir -p $@
	ocamldoc -html -d $@ $^
	touch $@

ifneq ($(MAKECMDGOALS),clean)
include .depend
endif

.depend: $(MODULES:=.ml) pyml_tests.ml
	$(OCAMLDEP) py.mli pycaml_compat.mli $^ >$@

clean:
	rm -f py.{cmi,cmx,cmo,a,o}
	rm -f pyml.{cma,cmxa}
	rm -f pytypes.{cmi,cmo,cmx,o}
	rm -f pywrappers.{ml,cmi,cmo,cmx,o}
	rm -f pyml_stubs.o
	rm -f generate.{cmi,cmx}
	rm -f pyml_compat.{ml,cmi,cmo,cmx,o}
	rm -f pycaml_compat.{cmi,cmx,cmo,a,o}
	rm -f pyml_tests.{cmi,cmx,cmo,a,o}
	rm -f $(GENERATED)
	rm -f .depend
	rm -rf doc

tarball:
	mkdir py.ml-$(VERSION)/
	cp Makefile pyml_compat312.ml pyml_compat403.ml generate.ml py.ml \
		pyml_stubs.c pyml_tests.ml README \
		py.ml-$(VERSION)/
	rm -f py.ml-$(VERSION).tar.gz
	tar -czf py.ml-$(VERSION).tar.gz py.ml-$(VERSION)/
	rm -rf py.ml-$(VERSION)/

generate: pyml_compat.cmx generate.cmx
	$(OCAMLOPT) $^ -o $@

pywrappers.ml $(GENERATED): generate
	./generate

pyml_tests: py.cmi pyml.cmxa pyml_tests.cmx
	$(OCAMLOPT) $(OCAMLLDFLAGS) unix.cmxa pyml.cmxa pyml_tests.cmx -o $@

pyml_tests.bytecode: py.cmi pyml.cma pyml_tests.cmo
	$(OCAMLC) unix.cma pyml.cma pyml_tests.cmo -o $@

pyml_compat.ml: $(PYML_COMPAT)
	cp $< $@

%.cmi: %.mli
	$(OCAMLC) $(OCAMLCFLAGS) -c $< -o $@

%.cmo: %.ml
	$(OCAMLC) $(OCAMLCFLAGS) -c $< -o $@

%.cmx: %.ml
	$(OCAMLOPT) $(OCAMLCFLAGS) -c $< -o $@

pyml_stubs.o: pyml_stubs.c $(GENERATED)
	$(OCAMLC) -c $< -o $@

pyml.cmxa: $(MODULES:=.cmx) libpyml_stubs.a
	$(OCAMLOPT) $(OCAMLLIBFLAGSNATIVE) -a $(MODULES:=.cmx) -o $@

pyml.cma: $(MODULES:=.cmo) libpyml_stubs.a
	$(OCAMLC) $(OCAMLLIBFLAGSBYTECODE) -a $(MODULES:=.cmo) -o $@

libpyml_stubs.a: pyml_stubs.o
	$(OCAMLMKLIB) -o pyml_stubs $<
