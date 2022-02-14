YQ_VERSION ?= 4.16.2
ACTIONLINT_VERSION ?= 1.6.8

SHELL := env PATH=$(abspath bin):$(shell echo $$PATH) /bin/bash

_bullet := $(shell printf "\033[34;1m▶\033[0m")

srcdir := templates
commondir := $(srcdir)/common
outdir := .github/workflows

# find all templates
srcs := $(wildcard $(srcdir)/*.yaml)

# generate output file names from templates
outputs := $(patsubst $(srcdir)/%.yaml,$(outdir)/%.yaml,$(srcs))

os := $(shell uname -s | tr [:upper:] [:lower:])
arch := $(shell uname -m)

ifeq ($(arch),x86_64)
	arch = amd64
endif

binary := $(os)_$(arch)

YQ := bin/yq-$(YQ_VERSION)/yq_$(binary)
ACTIONLINT := bin/actionlint-$(ACTIONLINT_VERSION)/actionlint

.PHONY: all lint generate tools lint-workflows generate-workflows

.PHONY: $(srcs)

all: generate lint

tools: $(YQ) $(ACTIONLINT)

# install yq
$(YQ):
	$(info $(_bullet) Installing <yq>)
	@mkdir -p $(dir $(YQ))
	@curl -s -L https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_$(binary).tar.gz | \
    tar xz -C $(dir $(YQ))
	ln -s $(subst bin/,,$(YQ)) bin/yq

# install actionlint
$(ACTIONLINT):
	$(info $(_bullet) Installing <actionlint>)
	@mkdir -p $(dir $(ACTIONLINT))
	@curl -s -L https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_${binary}.tar.gz | \
    tar xz -C $(dir $(ACTIONLINT)) actionlint
	ln -s $(subst bin/,,$(ACTIONLINT)) bin/actionlint

# define workflow dependencies
$(outdir)/build-go.yaml $(outdir)/build-python.yaml: $(commondir)/build.yaml $(commondir)/ssh-agent.yaml
$(outdir)/deploy-git-flow.yaml $(outdir)/deploy.yaml: $(commondir)/deploy.yaml $(commondir)/ssh-agent.yaml

lint: lint-workflows

lint-workflows: $(ACTIONLINT)
	$(info $(_bullet) Lint <workflows>)
	actionlint

generate: generate-workflows

generate-workflows::
	$(info $(_bullet) Generating <workflows>)

generate-workflows:: $(YQ) $(outputs)

$(outdir)/%.yaml: $(srcdir)/%.yaml
	@echo $@
	@yq eval-all '. as $$item ireduce ({}; . *+ $$item )' $^ | \
	yq eval 'explode(.) | del (.fragments) | . headComment=""' - \
	> $@
