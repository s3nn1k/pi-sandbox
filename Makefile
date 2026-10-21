SHELL := /bin/sh
.PHONY: image seeds seed-go seed-whisper

image:
	docker build --build-arg AGENT_HOME_PATH=$(HOME) --build-arg AGENT_UID=$(shell id -u) --build-arg AGENT_GID=$(shell id -g) -t pi-agent-base -f image/Dockerfile image/

seeds: seed-go seed-whisper
seed-go:
	docker run --rm -v pi-agent_gomodcache:/dst -v $(HOME)/go/pkg/mod:/src:ro alpine \
	  sh -c 'cp -a /src/. /dst/ && chown -R $(shell id -u):$(shell id -g) /dst'
seed-whisper:
	docker run --rm -v pi-agent_whisper:/dst -v $(HOME)/.local/share/whisper:/src:ro alpine \
	  sh -c 'cp -a /src/. /dst/ && chown -R $(shell id -u):$(shell id -g) /dst'
