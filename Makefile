YQ_VERSION ?= 4.16.2
ACTIONLINT_VERSION ?= 1.6.8

SHELL := env PATH=$(abspath bin):$(shell echo $$PATH) /bin/bash

_bullet := $(shell printf "\033[34;1m▶\033[0m")

srcdir := templates
commondir := $(srcdir)/common
outdir := .github/workflows

srcs := $(wildcard $(srcdir)/*.yaml)
outputs := $(patsubst $(srcdir)/%.yaml,$(outdir)/%.yaml,$(srcs))

os ?= $(shell uname -s | tr [:upper:] [:lower:])
arch ?= $(shell uname -m)

ifeq ($(arch),x86_64)
	arch = amd64
endif

binary = $(os)_$(arch)

yq := bin/yq-$(YQ_VERSION)/yq
actionlint := bin/actionlint-$(ACTIONLINT_VERSION)/actionlint

.PHONY: all lint generate tools lint-workflows generate-workflows

.PHONY: $(srcs)

all: lint generate

tools: $(yq) $(actionlint)

# install yq
$(yq):
	$(info $(_bullet) Installing <yq>)
	@mkdir -p $(dir $(yq))
	@curl -s -L https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_$(binary).tar.gz | \
    tar xz -C $(dir $(yq)) ./yq_$(binary) && \
    mv $(dir $(yq))/yq_$(binary) $(yq)
	ln -s $(subst bin/,,$(yq)) bin/yq

# install actionlint
$(actionlint):
	$(info $(_bullet) Installing <actionlint>)
	@mkdir -p $(dir $(actionlint))
	@curl -s -L https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_${binary}.tar.gz | \
    tar xz -C $(dir $(actionlint)) actionlint
	ln -s $(subst bin/,,$(actionlint)) bin/actionlint

# define workflow dependencies
$(outdir)/build-go.yaml $(outdir)/build-python.yaml: $(commondir)/ssh-agent.yaml
$(outdir)/deploy-git-flow.yaml $(outdir)/deploy.yaml: $(commondir)/deploy.yaml $(commondir)/ssh-agent.yaml

lint: lint-workflows

lint-workflows: $(actionlint)
	$(info $(_bullet) Lint <workflows>)
	actionlint

generate: generate-workflows

generate-workflows::
	$(info $(_bullet) Generating <workflows>)

generate-workflows:: $(yq) $(outputs)

_yq_merge_files := yq eval-all '. as $$item ireduce ({}; . *+ $$item )'
_yq_explode := yq eval 'explode(.) | del (.fragments) | . headComment=""'

$(outdir)/%.yaml: $(srcdir)/%.yaml
	@echo $@
	@if (( $(words $^) != 1 )); \
	then \
		$(_yq_merge_files) $^ | \
		$(_yq_explode) - \
		> $@; \
	else \
		$(_yq_explode) $^ \
		> $@; \
	fi