# gh-runner

A container image for a self-hosted GitHub Actions runner registered with an organisation, published as `ghcr.io/spomky-labs/gh-runner`. The image holds Docker with its Compose and Buildx plugins, and the GitHub CLI. The jobs run `docker`, `docker compose` and `docker buildx` commands against the host's daemon when its socket is mounted, or against a daemon of the container's own otherwise (see below), and `gh` with the token a workflow gives it.

The runner is named `runner-` followed by six random characters. It registers when the container starts and removes its registration when the container stops.

## Configuration

| Variable | | |
|---|---|---|
| `GH_OWNER` | required | The organisation the runner registers with. |
| `GH_TOKEN` | required, or `GH_TOKEN_FILE` | A token allowed to manage the organisation's self-hosted runners: a fine-grained token whose resource owner is the organisation, with the organisation permission "Self-hosted runners" in read and write, or a classic token with the `admin:org` scope. |
| `GH_TOKEN_FILE` | optional | A file holding the token, such as a Swarm or Compose secret. It is read when `GH_TOKEN` is empty. |
| `GH_LABELS` | optional | Labels added to the default ones (`self-hosted`, `Linux`, `ARM64`), comma-separated. |
| `RUNNER_DIR` | optional | A host directory mounted at the same path, for the jobs that run in containers. See below. |

The runner and its jobs are started without `GH_TOKEN` in their environment. A job with access to the Docker socket is still root on the host: keep such a runner away from public repositories.

Swarm and Compose stop a container with SIGTERM and kill it 10 seconds later. The runner stops, then its registration is removed. If a job may be running when the container stops, give it more time with `stop_grace_period`.

## The host's Docker daemon, or one of its own

With the host's socket mounted at `/var/run/docker.sock`, the jobs drive the host's daemon. They share its containers, networks, volumes and ports with everything else on the host: a port a job publishes fails when a service of the host holds it already, and a job is root on the host.

Without that socket, the container starts a Docker daemon of its own before the runner registers, and stops it after the runner is removed. What the jobs create, containers, networks, volumes and published ports, stays in the container: a job reaches what it publishes on `localhost`, and nothing it does meets the host or another runner. A container may run a daemon only under a runtime that allows it without `--privileged`, such as [Sysbox](https://github.com/nestybox/sysbox) (`sysbox-runc`), installed on the host; Sysbox CE publishes packages for amd64 and arm64, and its documentation lists the distributions it supports. Without such a runtime, the daemon stops at once and the container says so.

Docker Swarm cannot choose the runtime of a service, so a runner with a daemon of its own runs with Docker Compose, or `docker run --runtime=sysbox-runc`, on each node. A volume at `/var/lib/docker` keeps the images it pulled from one start to the next.

```yaml
services:
  github-runner:
    image: ghcr.io/spomky-labs/gh-runner:latest
    runtime: sysbox-runc
    restart: always
    environment:
      GH_OWNER: my-organisation
      GH_TOKEN_FILE: /run/secrets/gh_token
      GH_LABELS: isolated
    secrets:
      - gh_token
    volumes:
      - docker-data:/var/lib/docker
    stop_grace_period: 1m

volumes:
  docker-data:

secrets:
  gh_token:
    file: ./gh_token
```

## Jobs that run in containers, with the host's daemon

With the host's Docker socket, the containers of a job (`container:`, `services:`, `docker run -v`) are created by the host's daemon, which reads on the host every path it is asked to mount. By default, the runner lives in `/actions-runner` inside its own container, a path the host does not have: a job with `container:` fails at its first action, and `docker run -v "$PWD:/project"` mounts an empty directory. A daemon of the container's own reads the container's paths, and needs no `RUNNER_DIR`.

`RUNNER_DIR` names a host directory mounted at the same path in the container. On every start the directory is emptied, the runner is copied into it (about 700 MB) and runs from there. The directory must exist on every node the service can run on, and holds one runner only.

The runner runs as the `docker` user, uid 1001, with or without `RUNNER_DIR`. It is the uid of the runners GitHub hosts, which the images made for container jobs run as (`USER 1001`): what such a job writes in the workspace belongs to the runner, and the next checkout removes it. Like the runners GitHub hosts, that user has passwordless `sudo`, which actions such as `shivammathur/setup-php` need on a self-hosted runner to install packages; a job that can reach the Docker socket is root on the host already. A job container that runs as root and writes in the workspace leaves files the runner cannot remove until it starts again and `RUNNER_DIR` is emptied.

```yaml
services:
  github-runner:
    image: ghcr.io/spomky-labs/gh-runner:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /srv/gh-runner:/srv/gh-runner
    user: "0:0"
    environment:
      GH_OWNER: my-organisation
      GH_TOKEN_FILE: /run/secrets/gh_token
      GH_LABELS: swarm
      RUNNER_DIR: /srv/gh-runner
    secrets:
      - gh_token
    stop_grace_period: 1m
    deploy:
      replicas: 1
      placement:
        max_replicas_per_node: 1

secrets:
  gh_token:
    external: true
```
