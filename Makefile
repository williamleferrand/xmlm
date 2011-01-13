all:
	ocamlbuild src/xmlm.cmo

remove:
	ocamlfind remove xmlm

install:
	ocamlfind install xmlm META _build/src/xmlm.cm*

clean:
	ocamlbuild -clean
	find . |grep '~'| xargs rm -rf 

