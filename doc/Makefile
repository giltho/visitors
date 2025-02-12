export VISITORS_BUILDING_DOCUMENTATION=true

include ../Makefile.preprocess

export TEXINPUTS=.:../test:../test/ppx_import:

SOURCEDIRS := ../test,../test/ppx_import
ML         := $(shell ls {$(SOURCEDIRS)}/*.ml | grep -v cppo | grep -v processed)
PROCESSED  := $(patsubst %.ml,%.processed.ml,$(ML))

.PHONY: all loop clean prerequisites sources

all: prerequisites
	make sources
	latexmk -g -pdf manual

loop: prerequisites
	make sources
	latexmk -pdf -pvc manual

clean:
	rm -f $(PROCESSED)
	git clean -fdX

# We need the following packages, plus visitors itself,
# which we install in the current switch.
prerequisites:
	opam install --yes ocamlfind ppx_import ppx_tools ocp-indent
	make -C .. install

sources: $(wildcard *.tex) $(wildcard *.bib) $(wildcard *.sty) $(ML) $(PROCESSED)
