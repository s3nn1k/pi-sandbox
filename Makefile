SHELL := /bin/sh
UNAME_S := $(shell uname -s)
.PHONY: image seeds seed-go test lint install

ifeq ($(UNAME_S),Linux)
IMAGE_NET := --network=host
endif

image:
	docker build $(IMAGE_NET) --build-arg AGENT_HOME_PATH=$(HOME) --build-arg AGENT_UID=$(shell id -u) --build-arg AGENT_GID=$(shell id -g) -t pi-agent-base -f image/Dockerfile image/

seeds: seed-go
seed-go:
	docker run --rm -v pi-agent_gomodcache:/dst -v $(HOME)/go/pkg/mod:/src:ro alpine \
	  sh -c 'cp -a /src/. /dst/ && chown -R $(shell id -u):$(shell id -g) /dst'

test:
	bash tests/test-pi-run.sh

lint:
	for script in bin/pi-run bin/pi launch/lib.sh launch/steps/*.sh image/entrypoint.sh scripts/install.sh tests/test-pi-run.sh platform/macos/sandbox-sync platform/fedora/lib.sh platform/macos/lib.sh platform/fedora/install/*.sh platform/macos/install/*.sh; do bash -n "$$script" || exit 1; done
	shellcheck bin/pi-run bin/pi launch/lib.sh launch/steps/*.sh image/entrypoint.sh scripts/install.sh tests/test-pi-run.sh platform/macos/sandbox-sync platform/fedora/lib.sh platform/macos/lib.sh platform/fedora/install/*.sh platform/macos/install/*.sh

install:
	bash ./scripts/install.sh
