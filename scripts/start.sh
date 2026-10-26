#!/bin/bash

set -eu

# The token comes from GH_TOKEN, or from the file GH_TOKEN_FILE names (a Swarm or Compose secret)
if [ -z "${GH_TOKEN:-}" ] && [ -n "${GH_TOKEN_FILE:-}" ]; then
  GH_TOKEN=$(<"$GH_TOKEN_FILE")
fi
: "${GH_OWNER:?GH_OWNER is required}"
: "${GH_TOKEN:?GH_TOKEN or GH_TOKEN_FILE is required}"

RUNNER_NAME="runner-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
export RUNNER_NAME

# Prints a registration or a remove token for the organisation's runners
runner_token() {
  local response
  response=$(curl -fsS -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token ${GH_TOKEN}" \
    "https://api.github.com/orgs/${GH_OWNER}/actions/runners/$1-token") || return 1
  jq -er .token <<<"$response"
}

# Neither the runner nor its jobs get the token in their environment. The listener stops on SIGINT,
# which a command started in the background ignores unless it is given back its default action.
runner_env=(env --default-signal=INT -u GH_TOKEN -u GH_TOKEN_FILE)

if [ -z "${RUNNER_DIR:-}" ]; then
  RUNNER_DIR=/actions-runner
else
  # The host's Docker daemon reads on the host every path the runner mounts into a job's containers
  # ("_work", "externals"). RUNNER_DIR is a host directory mounted at the same path: it is emptied and
  # the runner is copied there on every start, which also clears what the jobs of the previous run left.
  case "$RUNNER_DIR" in
    / | /actions-runner | /actions-runner/* | [!/]*)
      echo "RUNNER_DIR must be an absolute path other than / and /actions-runner" >&2
      exit 1
      ;;
  esac
  if ! mountpoint -q "$RUNNER_DIR"; then
    echo "RUNNER_DIR (${RUNNER_DIR}) must be a host directory mounted at the same path" >&2
    exit 1
  fi
  find "$RUNNER_DIR" -mindepth 1 -delete
  cp -a /actions-runner/. "$RUNNER_DIR"
fi

# The runner runs as the docker user, uid 1001: the uid of the runners GitHub hosts, which the images made
# for container jobs run as, so that what a job container writes in the workspace belongs to the runner.
chown -R docker:docker "$RUNNER_DIR"

# Without the host's socket, the container runs a Docker daemon of its own, which the jobs drive: their
# containers, networks, volumes and published ports stay in this container. A container may run one only
# under a runtime that allows it, such as Sysbox.
dockerd_pid=
if [ ! -S /var/run/docker.sock ]; then
  dockerd >/var/log/dockerd.log 2>&1 &
  dockerd_pid=$!
  for _ in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$dockerd_pid" 2>/dev/null; then
      cat /var/log/dockerd.log >&2
      echo "The Docker daemon of this container stopped: mount the host's socket, or run the container under a runtime such as Sysbox" >&2
      exit 1
    fi
    sleep 1
  done
  if ! docker info >/dev/null 2>&1; then
    echo "The Docker daemon of this container did not answer within 60 seconds" >&2
    exit 1
  fi
fi

# Give the docker user the group of the Docker socket, whatever its name in the image
if [ -S /var/run/docker.sock ]; then
  DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
  DOCKER_GROUP=$(getent group "$DOCKER_GID" | cut -d: -f1)
  if [ -z "$DOCKER_GROUP" ]; then
    DOCKER_GROUP=docker-host
    groupadd -g "$DOCKER_GID" "$DOCKER_GROUP"
  fi
  usermod -aG "$DOCKER_GROUP" docker
fi

as_runner=(setpriv --reuid=docker --regid=docker --init-groups
  "${runner_env[@]}" HOME=/home/docker USER=docker LOGNAME=docker SHELL=/bin/bash)
cd "$RUNNER_DIR"

# A container restarted in place still holds the registration of its previous run
if [ -f .runner ]; then
  "${as_runner[@]}" ./config.sh remove --unattended --token "$(runner_token remove)" ||
    rm -f .runner .credentials .credentials_rsaparams
fi

REG_TOKEN=$(runner_token registration) || {
  echo "No registration token for ${GH_OWNER}: GH_TOKEN must be allowed to manage its self-hosted runners" >&2
  exit 1
}
config=(--unattended --url "https://github.com/${GH_OWNER}" --token "$REG_TOKEN" --name "$RUNNER_NAME")
if [ -n "${GH_LABELS:-}" ]; then
  config+=(--labels "$GH_LABELS")
fi
"${as_runner[@]}" ./config.sh "${config[@]}"

# Swarm and Compose stop a container with SIGTERM. RUNNER_MANUALLY_TRAP_SIG makes run.sh pass it to the
# listener as an interruption; once the runner has stopped, its registration is removed, with a token of
# its own since the registration token expires within the hour.
"${as_runner[@]}" RUNNER_MANUALLY_TRAP_SIG=1 ./run.sh &
runner_pid=$!
trap 'kill -TERM "$runner_pid" 2>/dev/null || true' TERM INT

# wait returns as soon as a trapped signal arrives: wait again until the runner has exited
status=0
while kill -0 "$runner_pid" 2>/dev/null; do
  wait "$runner_pid" && status=0 || status=$?
done

echo "Removing runner..."
remove_token=$(runner_token remove) && "${as_runner[@]}" ./config.sh remove --unattended --token "$remove_token" ||
  echo "${RUNNER_NAME} could not be removed: GitHub removes an offline runner after 14 days" >&2

# The daemon of the container stops its containers before it exits
if [ -n "$dockerd_pid" ]; then
  kill -TERM "$dockerd_pid" 2>/dev/null || true
  wait "$dockerd_pid" || true
fi

exit "$status"
