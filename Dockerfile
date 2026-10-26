FROM ubuntu:26.04

ARG RUNNER_VERSION
ENV DEBIAN_FRONTEND=noninteractive

LABEL Author="Florent Morselli"
LABEL Email="florent.morselli@spomky-labs.com"
LABEL GitHub="https://github.com/Spomky"
LABEL BaseImage="ubuntu:26.04"
LABEL RunnerVersion=${RUNNER_VERSION}

# 1. Update base system and create the user the runner runs as, uid 1001 like the runners GitHub hosts
RUN apt-get update -y && \
    apt-get upgrade -y && \
    useradd -m -u 1001 -s /bin/bash docker

# 2. Install core system packages (including gnupg for keyring management)
RUN apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    nodejs \
    sudo \
    wget \
    unzip \
    vim \
    git \
    jq \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3 \
    python3-venv \
    python3-dev \
    python3-pip

# 3. Clean APT cache to reduce image size
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# 4. Passwordless sudo for the runner user, as on the runners GitHub hosts: actions such as setup-php
#    install packages with it on a self-hosted runner
RUN echo 'docker ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/docker && \
    chmod 0440 /etc/sudoers.d/docker && \
    visudo -cf /etc/sudoers.d/docker

# 5. Add Docker’s official GPG key
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 6. Add Docker’s APT repository
RUN echo "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
    > /etc/apt/sources.list.d/docker.list

# 7. Add the APT repository of the GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=arm64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list

# 8. Install Docker with its Compose and Buildx plugins, and the GitHub CLI. The daemon runs only when no socket
#    of the host is mounted (scripts/start.sh)
RUN apt-get update && \
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin gh

# 9. Download GitHub Actions runner (an unknown version fails here, not in tar)
RUN mkdir -p /actions-runner && \
    curl -fL https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz \
    -o /actions-runner/runner.tar.gz && \
    tar -xzf /actions-runner/runner.tar.gz -C /actions-runner && \
    rm /actions-runner/runner.tar.gz

# 10. Install runner dependencies
RUN /actions-runner/bin/installdependencies.sh

# 11. Copy script
COPY scripts/start.sh /start.sh
RUN chmod +x /start.sh

# 12. Use root so we can `su docker` in the entrypoint
USER root

ENTRYPOINT ["/start.sh"]
