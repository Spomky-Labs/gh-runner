#!/bin/bash
set -e

# Vérifs variables
if [ -z "$GH_OWNER" ] || [ -z "$GH_TOKEN" ]; then
  echo "GH_OWNER et GH_TOKEN doivent être définis"
  exit 1
fi

RUNNER_NAME="runner-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
export RUNNER_NAME

# Permissions / groupe docker
chown -R docker:docker /actions-runner
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
groupadd -g "$DOCKER_GID" docker-host || true
usermod -aG docker-host docker

# Création du token
REG_TOKEN=$(curl -sX POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token ${GH_TOKEN}" \
  https://api.github.com/orgs/${GH_OWNER}/actions/runners/registration-token | jq -r .token)

# Configurer le runner
sudo -u docker /actions-runner/config.sh \
  --unattended \
  --url "https://github.com/${GH_OWNER}" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME"

# Cleanup à l’arrêt
cleanup() {
  echo "Suppression du runner..."
  sudo -u docker /actions-runner/config.sh remove --unattended --token "$REG_TOKEN"
}
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Lancer en foreground (PID 1)
exec sudo -u docker /actions-runner/run.sh
