# pi-sandbox

Container environment for the pi coding agent: the agent runs inside a dind netns, the
host executes nothing but its own code. Monorepo for two platforms - Fedora (docker) and
macOS (colima). Shared code lives in launch/, bin/, compose.yaml; per-platform layers in
platform/<plat>/.

## Layout

- bin/pi-run - cwd router and session orchestrator: launch roots (pi-mounts) run
  sandboxed, anything else runs host pi with a stderr notice; sets DOCKER_CONTEXT=colima
  on macOS.
- launch/lib.sh - shared helpers; resolves the platform into PI_SANDBOX_PLATFORM (uname:
  Linux -> fedora, Darwin -> macos, otherwise fail-loud; the env variable overrides it for
  tests) and provides compose(), which adds platform/<plat>/compose.override.yaml to every
  docker compose call.
- platform/<plat>/lib.sh - hooks: platform_deps, engine_ready, guard_checks, guard_probe,
  bind_preflight (fedora: systemctl/firewalld/nft checks, post-up traffic probe, bridge
  pinning; macos: colima VM bring-up and VM-mount sanity, guard hooks are no-ops).
- launch/steps/ - preflight (deps, engine, guard, dind up), sync (agent cache refresh),
  session (container run + reattach on connection loss).
- compose.yaml - platform-neutral base; platform/<plat>/compose.override.yaml adds
  network/ports/limits: fedora - pinet with pi-sbx0 bridge, loopback-published ports,
  pids/mem limits; macos - herdr-sock socat sidecar, wider port range.
- image/ - pi-agent-base image; tests/ - stub-based suite (no real docker/systemctl).

## Install (Fedora)

Requirements: docker-ce with the user in the docker group, firewalld, ~/dotfiles-fedora
and ~/credentials (sync sources - see launch/steps/sync.sh). From a session without the
docker group use sg docker -c 'cd ~/pi-sandbox && ./install.sh'. Idempotent: docker zone
target %%REJECT%%, pi-sandbox-guard nft unit, herdr-bridge user unit, image and seeds
(make image seeds). macOS install unification into this repo is the next step.

```sh
./install.sh
```

## Usage

- pi --unsafe - host pi without notice; config subcommands (update/mcp/auth/...) too.
- pi --session born outside the launch roots goes to host pi regardless of cwd.
- Test-stack ports: 127.0.0.1:8600-8699 (Fedora), 8600-8799 (macOS).
- Connection loss to a session container reattaches automatically; "orphaned session"
  (dind recreated) requires a pi restart.
- Agent credentials (kubectl/psql): kubeconfig / pgpass / pg_service.conf under
  ~/credentials/agents-credentials/; in-sandbox nuances live in the sandbox-environment
  skill delivered with the agent cache.

## Development

```sh
make lint   # bash -n + shellcheck over shell entry points
make test   # router/platform tests against stubs
```
