#!/bin/bash

set -e

GH_OWNER=$GH_OWNER
GH_TOKEN=$GH_TOKEN

RUNNER_NAME="runner-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
export RUNNER_NAME

# Ensure /actions-runner is accessible and owned
chown -R docker:docker /actions-runner

# Get Docker socket GID and allow docker user to access it
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
groupadd -g "$DOCKER_GID" docker-host || true
usermod -aG docker-host docker

# Switch to docker user for config and execution
su docker <<EOF
cd /actions-runner

if [ ! -f .runner ]; then
  REG_TOKEN=\$(curl -sX POST \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token ${GH_TOKEN}" \
    https://api.github.com/orgs/${GH_OWNER}/actions/runners/registration-token | jq -r .token)

  ./config.sh --unattended --url https://github.com/${GH_OWNER} --token "\$REG_TOKEN" --name "\$RUNNER_NAME"
fi


cleanup() {
  echo "Removing runner..."
  ./config.sh remove --unattended --token "\$REG_TOKEN"
}
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh
EOF
