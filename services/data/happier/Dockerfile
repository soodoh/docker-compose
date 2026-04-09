FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV NODE_VERSION=20.18.2

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    docker.io \
    git \
    gh \
    gnupg \
    jq \
    lsb-release \
    make \
    openssh-client \
    pipx \
    python-is-python3 \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    tini \
    golang-go \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://bun.sh/install | env BUN_INSTALL=/usr/local bash
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh

RUN ln -sf /usr/bin/docker /usr/local/bin/docker \
  && ln -sf /usr/bin/git /usr/local/bin/git \
  && ln -sf /usr/bin/gh /usr/local/bin/gh \
  && ln -sf /usr/bin/python3 /usr/local/bin/python \
  && ln -sf /usr/bin/python3 /usr/local/bin/python3 \
  && ln -sf /usr/lib/go-1.19/bin/go /usr/local/bin/go

RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    arm64) node_arch=linux-arm64 ;; \
    amd64) node_arch=linux-x64 ;; \
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  mkdir -p /usr/local/lib/nodejs; \
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${node_arch}.tar.xz" \
    | tar -xJ -C /usr/local/lib/nodejs; \
  ln -sf "/usr/local/lib/nodejs/node-v${NODE_VERSION}-${node_arch}/bin/node" /usr/local/bin/node; \
  ln -sf "/usr/local/lib/nodejs/node-v${NODE_VERSION}-${node_arch}/bin/npm" /usr/local/bin/npm; \
  ln -sf "/usr/local/lib/nodejs/node-v${NODE_VERSION}-${node_arch}/bin/npx" /usr/local/bin/npx

RUN useradd --home-dir /var/lib/happier --create-home --shell /bin/bash devbox \
  && usermod -aG docker devbox \
  && mkdir -p /workspace /var/lib/docker /var/log/happier /var/lib/happier \
  && chown -R devbox:devbox /workspace /var/log/happier /var/lib/happier

RUN npm install -g @happier-dev/cli@0.2.1
RUN ln -sf "$(npm root -g)/@happier-dev/cli/bin/happier.mjs" /usr/local/bin/happier \
  && chmod +x "$(npm root -g)/@happier-dev/cli/bin/happier.mjs" \
  && chmod +x /usr/local/bin/happier

COPY services/data/happier/bootstrap-ssh.sh /usr/local/bin/bootstrap-ssh
COPY services/data/happier/healthcheck.sh /usr/local/bin/happier-healthcheck
COPY services/data/happier/entrypoint.sh /usr/local/bin/happier-entrypoint
COPY services/data/happier/github_known_hosts /usr/local/share/happier/github_known_hosts

RUN chmod +x \
  /usr/local/bin/bootstrap-ssh \
  /usr/local/bin/happier-healthcheck \
  /usr/local/bin/happier-entrypoint \
  /usr/local/share/happier/github_known_hosts

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/happier-entrypoint"]
