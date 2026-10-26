# gh-runner

A container image for a self-hosted GitHub Actions runner registered with an organisation, published as `ghcr.io/spomky-labs/gh-runner`. The image holds the Docker CLI: with the host's Docker socket mounted, the jobs run `docker` commands against the host's daemon.

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

## Jobs that run in containers

With the host's Docker socket, the containers of a job (`container:`, `services:`, `docker run -v`) are created by the host's daemon, which reads on the host every path it is asked to mount. By default, the runner lives in `/actions-runner` inside its own container, a path the host does not have: a job with `container:` fails at its first action, and `docker run -v "$PWD:/project"` mounts an empty directory.

`RUNNER_DIR` names a host directory mounted at the same path in the container. On every start the directory is emptied, the runner is copied into it (about 700 MB) and runs from there. The directory must exist on every node the service can run on, and holds one runner only.

The runner runs as the `docker` user, uid 1001, with or without `RUNNER_DIR`. It is the uid of the runners GitHub hosts, which the images made for container jobs run as (`USER 1001`): what such a job writes in the workspace belongs to the runner, and the next checkout removes it. A job container that runs as root and writes in the workspace leaves files the runner cannot remove until it starts again and `RUNNER_DIR` is emptied.

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
