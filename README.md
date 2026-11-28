# pi-sandbox

Container environment for the pi coding agent: the agent runs inside a dind netns, the
host executes nothing but its own code. Two platforms - Fedora (docker) and macOS
(colima) - share launch/, bin/ and compose.yaml; platform/<plat>/ holds the layers.

## Install

```sh
make install
```

Idempotent; runs platform/<plat>/install/ steps. Fedora needs docker-ce with the user in
the docker group and firewalld - from a session without the group use
`sg docker -c 'cd ~/pi-sandbox && make install'`. macOS needs colima (vz/virtiofs) and
brew.

## Usage

- `pi` inside the launch roots (pi-mounts) runs sandboxed; elsewhere - host pi with a
  stderr notice. `pi --unsafe` - host pi without notice; config subcommands (update, mcp,
  auth, ...) always go to the host pi.
- A `--session` born outside the launch roots resumes on the host regardless of cwd.
- Connection loss to a session container reattaches automatically; an "orphaned session"
  (dind recreated) requires a pi restart.
- Test-stack ports: 127.0.0.1:8600-8699 (Fedora), 8600-8799 (macOS).
- Agent credentials (kubectl/psql) come from ~/credentials/agents-credentials/; in-sandbox
  nuances are in the sandbox-environment skill shipped with the agent cache.

## Development

```sh
make lint   # bash -n + shellcheck over shell entry points, py_compile over the bridge
make test   # stub-based bash suite + herdr-bridge unit tests
```
