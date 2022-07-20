ACTIONLINT_VERSION ?= 1.6.8
CUE_VERSION ?= 0.4.3

SHELL := env PATH=$(abspath bin):$(shell echo $$PATH) /bin/bash

_bullet := $(shell printf "\033[34;1m▶\033[0m")

srcdir := pkg/workflows
outdir := .github/workflows

# find all templates
srcs := $(wildcard $(srcdir)/*.cue)

# generate output file names from templates
outputs := $(patsubst $(srcdir)/%.cue,$(outdir)/%.yaml,$(srcs))

os := $(shell uname -s | tr [:upper:] [:lower:])
arch := $(shell uname -m)

ifeq ($(arch),x86_64)
	arch = amd64
endif

binary := $(os)_$(arch)

CUE := bin/cue-$(CUE_VERSION)/cue
ACTIONLINT := bin/actionlint-$(ACTIONLINT_VERSION)/actionlint

.PHONY: all lint generate tools lint-workflows generate-workflows $(srcs)

all: generate lint

tools: $(CUE) $(ACTIONLINT)

# install cue
$(CUE):
	$(info $(_bullet) Installing <cue>)
	@echo $(CUE)
	@mkdir -p $(dir $(CUE))
	@curl -s -L https://github.com/cue-lang/cue/releases/download/v$(CUE_VERSION)/cue_v$(CUE_VERSION)_$(binary).tar.gz | \
    tar xz -C $(dir $(CUE))
	ln -sf $(subst bin/,,$(CUE)) bin/cue

# install actionlint
$(ACTIONLINT):
	$(info $(_bullet) Installing <actionlint>)
	@mkdir -p $(dir $(ACTIONLINT))
	@curl -s -L https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_${binary}.tar.gz | \
    tar xz -C $(dir $(ACTIONLINT)) actionlint
	ln -s $(subst bin/,,$(ACTIONLINT)) bin/actionlint

lint: lint-workflows

lint-workflows: $(ACTIONLINT)
	$(info $(_bullet) Lint <workflows>)
	@actionlint

generate: generate-workflows

generate-workflows::
	$(info $(_bullet) Generating <workflows>)

generate-workflows:: $(CUE) $(outputs)

$(outdir)/%.yaml: $(srcdir)/%.cue
	@echo "$@"
	@cue export $< --out yaml > $@
