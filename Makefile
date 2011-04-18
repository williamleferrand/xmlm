all:
	ocamlbuild src/xmlm.cmo

essai:
	ocamlbuild src/essai.byte

remove:
	ocamlfind remove xmlm

install:
	ocamlfind install xmlm-lwt META _build/src/xmlm.cm*

clean:
	ocamlbuild -clean
	find . |grep '~'| xargs rm -rf 

