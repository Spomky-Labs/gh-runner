FROM ubuntu:24.04

ARG RUNNER_VERSION
ENV DEBIAN_FRONTEND=noninteractive

LABEL Author="Florent Morselli"
LABEL Email="florent.morselli@spomky-labs.com"
LABEL GitHub="https://github.com/Spomky"
LABEL BaseImage="ubuntu:24.04"
LABEL RunnerVersion=${RUNNER_VERSION}

# 1. Update base system and create a non-root user
RUN apt-get update -y && \
    apt-get upgrade -y && \
    useradd -m -s /bin/bash docker

# 2. Install core system packages (including gnupg for keyring management)
RUN apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    nodejs \
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

# 4. Add Docker’s official GPG key
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 5. Add Docker’s APT repository (for CLI only)
RUN echo "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
    > /etc/apt/sources.list.d/docker.list

# 6. Install Docker CLI only (no daemon)
RUN apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli

# 7. Download GitHub Actions runner
RUN mkdir -p /actions-runner && \
    curl -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz \
    -o /actions-runner/runner.tar.gz && \
    tar -xzf /actions-runner/runner.tar.gz -C /actions-runner && \
    rm /actions-runner/runner.tar.gz

# 8. Install runner dependencies
RUN /actions-runner/bin/installdependencies.sh

# 9. Copy script
COPY scripts/start.sh /start.sh
RUN chmod +x /start.sh

# 10. Use root so we can `su docker` in the entrypoint
USER root

ENTRYPOINT ["/start.sh"]
