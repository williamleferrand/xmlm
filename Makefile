lib=_build/src/xmlm
SITELIB=$(shell ocamlfind printconf destdir)

default:
	./build

install:
	mkdir -p $(DESTDIR)$(SITELIB)
	ocamlfind install -destdir $(DESTDIR)$(SITELIB) -ldconf ignore xmlm src/META $(lib).cmi $(lib).cmx $(lib).cmo $(lib).o
 
uninstall:
	ocamlfind remove xmlm
