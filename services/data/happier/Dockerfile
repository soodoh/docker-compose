FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ARG NODE_VERSION=20.18.2
ARG BUN_VERSION=1.3.11
ARG UV_VERSION=0.11.5
ARG COMPOSE_VERSION=2.29.7
ARG HAPPIER_CLI_VERSION=0.2.1

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
    python-is-python3 \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    tini \
    golang-go \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    arm64) node_arch=linux-arm64; bun_arch=aarch64; uv_arch=aarch64; compose_arch=aarch64 ;; \
    amd64) node_arch=linux-x64; bun_arch=x64; uv_arch=x86_64; compose_arch=x86_64 ;; \
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  mkdir -p /usr/local/lib/nodejs /usr/local/lib/bun /usr/local/lib/uv /usr/local/lib/docker/cli-plugins /tmp/happier-build; \
  cd /tmp/happier-build; \
  node_tarball="node-v${NODE_VERSION}-${node_arch}.tar.xz"; \
  curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${node_tarball}"; \
  curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"; \
  awk -v file="${node_tarball}" '$2 == file { print $0 }' SHASUMS256.txt > node.sha256; \
  sha256sum -c node.sha256; \
  tar -xJf "${node_tarball}" -C /usr/local/lib/nodejs; \
  ln -sf "/usr/local/lib/nodejs/node-v${NODE_VERSION}-${node_arch}/bin/node" /usr/local/bin/node; \
  ln -sf "/usr/local/lib/nodejs/node-v${NODE_VERSION}-${node_arch}/bin/npm" /usr/local/bin/npm; \
  ln -sf "/usr/local/lib/nodejs/node-v${NODE_VERSION}-${node_arch}/bin/npx" /usr/local/bin/npx; \
  bun_zip="bun-linux-${bun_arch}.zip"; \
  curl -fsSLO "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${bun_zip}"; \
  curl -fsSLO "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt"; \
  awk -v file="${bun_zip}" '$2 == file { print $0 }' SHASUMS256.txt > bun.sha256; \
  sha256sum -c bun.sha256; \
  unzip -q "${bun_zip}" -d bun; \
  bun_bin="$(find bun -type f -name bun -perm -111 | head -n 1)"; \
  install -m 755 "${bun_bin}" /usr/local/bin/bun; \
  uv_tarball="uv-${uv_arch}-unknown-linux-gnu.tar.gz"; \
  curl -fsSLO "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${uv_tarball}"; \
  curl -fsSLO "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${uv_tarball}.sha256"; \
  sha256sum -c "${uv_tarball}.sha256"; \
  tar -xzf "${uv_tarball}" -C /usr/local/lib/uv; \
  uv_bin="$(find /usr/local/lib/uv -type f -name uv -perm -111 | head -n 1)"; \
  uvx_bin="$(find /usr/local/lib/uv -type f -name uvx -perm -111 | head -n 1)"; \
  install -m 755 "${uv_bin}" /usr/local/bin/uv; \
  install -m 755 "${uvx_bin}" /usr/local/bin/uvx; \
  compose_bin="docker-compose-linux-${compose_arch}"; \
  curl -fsSLO "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/${compose_bin}"; \
  curl -fsSLO "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/${compose_bin}.sha256"; \
  sha256sum -c "${compose_bin}.sha256"; \
  install -m 755 "${compose_bin}" /usr/local/lib/docker/cli-plugins/docker-compose; \
  ln -sf /usr/bin/docker /usr/local/bin/docker; \
  ln -sf /usr/bin/git /usr/local/bin/git; \
  ln -sf /usr/bin/gh /usr/local/bin/gh; \
  ln -sf /usr/bin/python3 /usr/local/bin/python; \
  ln -sf /usr/bin/python3 /usr/local/bin/python3; \
  ln -sf /usr/lib/go-1.19/bin/go /usr/local/bin/go

RUN useradd --home-dir /var/lib/happier --create-home --shell /bin/bash devbox \
  && usermod -aG docker devbox \
  && mkdir -p /workspace /var/lib/docker /var/log/happier /var/lib/happier \
  && chown -R devbox:devbox /workspace /var/log/happier /var/lib/happier

RUN npm install -g @happier-dev/cli@${HAPPIER_CLI_VERSION}
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
