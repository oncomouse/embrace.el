EMACS ?= emacs
EXPREG_REPO ?= https://github.com/casouri/expreg.git
EXPREG_DIR := test/externals/expreg
LOAD_PATH := -L . -L $(EXPREG_DIR)

.PHONY: all expreg test compile clean

all: compile test

## expreg -- vendor expreg (1.4.1) into test/externals for the load-path
expreg: $(EXPREG_DIR)/expreg.el

$(EXPREG_DIR)/expreg.el:
	@git clone --depth 1 $(EXPREG_REPO) $(EXPREG_DIR)

## compile -- byte-compile embrace.el against expreg
compile: $(EXPREG_DIR)/expreg.el
	$(EMACS) -Q --batch $(LOAD_PATH) -f batch-byte-compile embrace.el

## test -- byte-compile, then run the ert suite
test: compile
	$(EMACS) -Q --batch $(LOAD_PATH) -l test/embrace-tests.el \
		-f ert-run-tests-batch-and-exit

clean:
	rm -f embrace.elc test/*.elc
