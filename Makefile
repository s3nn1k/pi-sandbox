SHELL := /bin/sh
.PHONY: image seeds seed-go test lint

image:
	docker build --network=host --build-arg AGENT_HOME_PATH=$(HOME) --build-arg AGENT_UID=$(shell id -u) --build-arg AGENT_GID=$(shell id -g) -t pi-agent-base -f image/Dockerfile image/

seeds: seed-go
seed-go:
	docker run --rm -v pi-agent_gomodcache:/dst -v $(HOME)/go/pkg/mod:/src:ro alpine \
	  sh -c 'cp -a /src/. /dst/ && chown -R $(shell id -u):$(shell id -g) /dst'

test:
	bash tests/test-pi-run.sh

lint:
	for script in bin/pi-run bin/pi launch/lib.sh launch/steps/*.sh image/entrypoint.sh install.sh tests/test-pi-run.sh; do bash -n "$$script" || exit 1; done
	shellcheck bin/pi-run bin/pi launch/lib.sh launch/steps/*.sh image/entrypoint.sh install.sh tests/test-pi-run.sh
