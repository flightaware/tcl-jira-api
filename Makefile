#
# Tcl JIRA REST API package
#

PACKAGE=	tcl-jira

PREFIX?=	/usr/local
LIB?=		$(PREFIX)/lib
BIN?=		$(PREFIX)/bin

TARGET?=	$(LIB)/$(PACKAGE)

UID?=		0
GID?=		0

TCLSH?=		tclsh

all:

install:	install-package 

uninstall:	uninstall-package

pkgIndex:
	@echo Generating pkgIndex
	@cd package && echo "pkg_mkIndex -- ." | $(TCLSH)

install-package: pkgIndex
	@echo Installing $(PACKAGE) to $(TARGET)
	@install -o $(UID) -g $(GID) -m 0755 -d $(TARGET)
	@echo "  Copying package Tcl files"
	@install -o $(UID) -g $(GID) -m 0644 package/*.tcl $(TARGET)
	@sed -i '' -e's/tclsh.\../$(TCLSH)/' $(TARGET)/*
	@echo "Installation complete"

make uninstall-package:
	rm -rf $(TARGET)

install-git-hook:
	@echo "Installing jira-git-hook to $(BIN)" 
	@cd githook
	@install -o $(UID) -g $(GID) -m 0755 tools/jira-git-hook $(BIN)/ 
	@sed -i '' -e's/tclsh.\../$(TCLSH)/' $(BIN)/jira-git-hook

