# This file has three stages. `base` has the toolchain and development tools.
# `runner` adds the GitHub Actions runner, and is published as `:runner`. The
# final stage, `workstation`, adds AI harnesses instead, and is published as
# `:master`; it is the image agents and humans work in.
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
# Without a UTF-8 locale, `docker exec` sessions fall back to ASCII, which
# garbles tmux and terminal UIs. C.UTF-8 is built in, so no locales package is
# needed.
ENV LANG=C.UTF-8
SHELL ["/bin/bash", "-c"]

ARG TARGETARCH
ARG WASMTIME_VERSION="v44.0.1"
ARG SWIFT_WASM_TRIPLE='wasm32-unknown-wasip1-threads'
ARG SWIFT_RELEASE='6.4.1'
ARG SWIFT_NIGHTLY=
ARG UBUNTU_VERSION='ubuntu24.04'


# these variables exported to the container
ENV SWIFT_VERSION="${SWIFT_RELEASE}-${SWIFT_NIGHTLY:-RELEASE}"
ENV SWIFT_WASM_SDK="${SWIFT_VERSION}-${SWIFT_WASM_TRIPLE}"
ENV SWIFT_WASM_SDK_PATH='/opt/swift/sdks'
ENV SWIFT_INSTALLATION="/opt/swift/usr"
ENV PATH="${PATH:+${PATH}:}${SWIFT_INSTALLATION}/bin"
# expose Swift's C++ and Block headers for libraries like IndexStoreDB
ENV CPLUS_INCLUDE_PATH="${CPLUS_INCLUDE_PATH:+${CPLUS_INCLUDE_PATH}:}\
${SWIFT_INSTALLATION}/lib/swift:\
${SWIFT_INSTALLATION}/lib/swift/Block"

# actually make pip usable in the container
# to compensate safety-wise, force pip to always use --user mode
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV PIP_USER=true
# ensure the bin folder that pip is now using is on the PATH
ENV PATH="/home/ubuntu/.local/bin${PATH:+:${PATH}}"

COPY PublicKeys/aws.public.key aws.public.key
COPY PublicKeys/swift.public.key swift.public.key
COPY PublicKeys/nodesource.public.gpg /usr/share/keyrings/nodesource.gpg

# Squash the following RUN commands into a single command to reduce image size
RUN <<EOF

set -euo pipefail

ARCHITECTURE="$TARGETARCH"
ARCHITECTURE="${ARCHITECTURE/arm64/aarch64}"
ARCHITECTURE="${ARCHITECTURE/amd64/x86_64}"

# Note: The Docker CLI does not print the correct URL to the console, but the actual
# interpolated string passed to `curl` is correct.
if [[ -v SWIFT_NIGHTLY && -n "$SWIFT_NIGHTLY" ]]; then
    SWIFT_BRANCH="swift-${SWIFT_RELEASE}-branch"
    SWIFT_TOOLCHAIN="${SWIFT_RELEASE}-DEVELOPMENT-${SWIFT_NIGHTLY}"
else
    SWIFT_BRANCH="swift-${SWIFT_RELEASE}-release"
    SWIFT_TOOLCHAIN="${SWIFT_VERSION}"
fi


apt update
apt -y install curl xz-utils


SWIFT_WASM_URL="https://github.com/rarestype/swift-sdk-wasm/releases/download/\
swift-${SWIFT_VERSION}/${SWIFT_WASM_SDK}.artifactbundle.zip"

echo "Downloading Swift WebAssembly SDK from: ${SWIFT_WASM_URL}"
curl -fsSL "${SWIFT_WASM_URL}" -o swift-wasm.artifactbundle.zip

# install wasmtime
WASMTIME_URL="https://github.com/bytecodealliance/wasmtime/releases/download/\
${WASMTIME_VERSION}/wasmtime-${WASMTIME_VERSION}-${ARCHITECTURE}-linux.tar.xz"

echo "Downloading Wasmtime from: ${WASMTIME_URL}"
curl -fsSL "${WASMTIME_URL}" -o wasmtime.tar.xz
tar -xf wasmtime.tar.xz
mv "wasmtime-${WASMTIME_VERSION}-${ARCHITECTURE}-linux/wasmtime" /usr/local/bin/
rm -rf wasmtime.tar.xz "wasmtime-${WASMTIME_VERSION}-${ARCHITECTURE}-linux"

# x86_64 is implicit in the Swift platform naming scheme
SWIFT_PLATFORM="${UBUNTU_VERSION}-${ARCHITECTURE}"
SWIFT_PLATFORM="${SWIFT_PLATFORM%-x86_64}"
SWIFT_TOOLCHAIN_URL="https://download.swift.org/${SWIFT_BRANCH}/${SWIFT_PLATFORM//[.]/}/\
swift-${SWIFT_TOOLCHAIN}/\
swift-${SWIFT_TOOLCHAIN}-${SWIFT_PLATFORM}.tar.gz"

echo "Downloading Swift toolchain from: ${SWIFT_TOOLCHAIN_URL}"
curl -fsSL "${SWIFT_TOOLCHAIN_URL}.sig" -o toolchain.tar.gz.sig
curl -fsSL "${SWIFT_TOOLCHAIN_URL}" -o toolchain.tar.gz

apt -y dist-upgrade

# Install dependencies of the Swift toolchain
apt update
apt -y install \
    binutils \
    git \
    gnupg2 \
    libc6-dev \
    libcurl4-openssl-dev \
    libedit2 \
    libgcc-13-dev \
    libncurses-dev \
    libsqlite3-0 \
    libstdc++-13-dev \
    libxml2-dev \
    libz3-dev \
    pkg-config \
    tzdata \
    unzip \
    zlib1g-dev

# needed for nodesource setup
apt -y install \
    lsb-release \
    ca-certificates

# Unpack the Swift toolchain to /usr/local/swift
SWIFT_INSTALLATION_DIRECTORY="${SWIFT_INSTALLATION%/*}"
mkdir -p "$SWIFT_INSTALLATION_DIRECTORY"
gpg --import swift.public.key
gpg --verify toolchain.tar.gz.sig toolchain.tar.gz
tar --strip-components=1 -xf toolchain.tar.gz -C "$SWIFT_INSTALLATION_DIRECTORY"
rm toolchain.tar.gz
rm toolchain.tar.gz.sig
rm swift.public.key

swift sdk install swift-wasm.artifactbundle.zip --swift-sdks-path "$SWIFT_WASM_SDK_PATH"

# need to install a newer nodejs than is available by default
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] \
https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

apt update
apt -y install \
    binaryen \
    fonts-liberation \
    gh \
    git-filter-repo \
    glslang-tools \
    jq \
    imagemagick \
    libgl1-mesa-dri \
    libjemalloc2 \
    libjemalloc-dev \
    liblz4-dev \
    libsqlite3-dev \
    libssl-dev \
    mesa-vulkan-drivers \
    nano \
    nodejs \
    passwd \
    pip \
    ripgrep \
    sudo \
    tmux \
    wabt \
    wget \
    xxd \
    zip

# Google Chrome Stable (available natively for amd64 and arm64)
DEB_ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"
curl -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_${DEB_ARCH}.deb" \
    -o chrome.deb
apt -y install ./chrome.deb
rm -f chrome.deb

# AWS uses 'aarch64' and 'x86_64'
curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCHITECTURE}.zip" \
    -o "awscliv2.zip"
curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCHITECTURE}.zip.sig" \
    -o "awscliv2.zip.sig"

# import the AWS Public Key (key is public/static from AWS docs)
gpg --import aws.public.key
gpg --verify awscliv2.zip.sig awscliv2.zip

unzip awscliv2.zip
./aws/install

# clean up cached files
rm -rf aws awscliv2.zip awscliv2.zip.sig aws.public.key
rm -rf /var/lib/apt/lists/*

# trust GitHub’s SSH host keys system-wide, so that CI can clone private
# dependencies over SSH. the keys come from GitHub’s API over HTTPS, so every
# image build picks up a rotation
curl -fsSL https://api.github.com/meta \
    | jq -r '.ssh_keys[] | "github.com " + .' > /etc/ssh/ssh_known_hosts

# verify installations
echo "NodeJS: $(node --version)"
echo "AWS CLI: $(aws --version)"
echo "Google Chrome: $(google-chrome --version)"
ssh-keygen -F github.com -f /etc/ssh/ssh_known_hosts
swift --version
swift sdk list --swift-sdks-path "$SWIFT_WASM_SDK_PATH"

EOF

WORKDIR /home/ubuntu

RUN passwd -d ubuntu
RUN usermod -aG sudo ubuntu
COPY Config/tmux/tmux.conf /etc/tmux.conf
COPY Config/sourcekit-lsp/config.json /etc/skel/.sourcekit-lsp/config.json
COPY Config/sourcekit-lsp/config.json /root/.sourcekit-lsp/config.json

# agents can’t answer a password prompt, even an empty one
RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' \
    > /etc/sudoers.d/ubuntu && chmod 440 /etc/sudoers.d/ubuntu

# Switch back to the standard user for default execution
USER ubuntu
ENV HOME=/home/ubuntu

COPY --chown=ubuntu:ubuntu \
    Config/sourcekit-lsp/config.json \
    /home/ubuntu/.sourcekit-lsp/config.json

CMD ["sleep", "infinity"]


FROM base AS runner

USER root

# Install GitHub Actions Runner dependencies
RUN apt update && apt install -y \
    curl \
    jq \
    libicu-dev \
    libdigest-sha-perl \
    && rm -rf /var/lib/apt/lists/*

# Switch back to the non-root user 'ubuntu' (created in the base stage)
USER ubuntu
WORKDIR /home/ubuntu

# https://github.com/actions/runner/releases
ARG RUNNER_VERSION="2.333.1"
# bring in the architecture argument (automatically set by Docker)
ARG TARGETARCH

RUN mkdir actions-runner && cd actions-runner \
    && if [ "$TARGETARCH" = "amd64" ]; then GH_ARCH="x64"; \
       elif [ "$TARGETARCH" = "arm64" ]; then GH_ARCH="arm64"; \
       else echo "Unsupported architecture: $TARGETARCH"; exit 1; fi \
    && echo "Downloading Runner for $GH_ARCH..." \
    && curl -o actions-runner.tar.gz -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${GH_ARCH}-${RUNNER_VERSION}.tar.gz" \
    && tar xzf ./actions-runner.tar.gz \
    && rm actions-runner.tar.gz

COPY --chown=ubuntu:ubuntu Scripts/runner-entrypoint.sh /home/ubuntu/actions-runner/entrypoint.sh
RUN chmod +x /home/ubuntu/actions-runner/entrypoint.sh

WORKDIR /home/ubuntu/actions-runner
ENTRYPOINT ["./entrypoint.sh"]


FROM base AS workstation

USER root
# `base` sets HOME for the ubuntu user, which root would otherwise inherit, and
# then leave root-owned caches in /home/ubuntu
ENV HOME=/root

# Harnesses are installed system-wide and only change when the image is rebuilt,
# so everyone runs the same versions. Pin a version by overriding these.
ARG CLAUDE_CODE_VERSION=latest
ARG QWEN_CODE_VERSION=latest
ENV DISABLE_AUTOUPDATER=1

# Claude Code’s postinstall links its native binary. Qwen Code’s audio capture
# helper is left disabled, since containers have no microphone.
RUN npm install -g --allow-scripts=@anthropic-ai/claude-code \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@qwen-code/qwen-code@${QWEN_CODE_VERSION}" \
    && npm cache clean --force \
    && claude --version \
    && qwen --version

# Install Antigravity CLI system-wide
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin

COPY --chmod=755 Scripts/team /usr/local/bin/team

# Managed settings live outside the home directory, so they reach existing home
# volumes when the image is updated, and take precedence over user settings.
COPY Config/claude-code/managed-settings.json /etc/claude-code/managed-settings.json

USER ubuntu
ENV HOME=/home/ubuntu

RUN mkdir -p /home/ubuntu/.gemini/antigravity-cli/conversations && \
    ln -sf /home/ubuntu/.gemini/antigravity-cli/conversations/conversation_summaries.db \
    /home/ubuntu/.gemini/antigravity-cli/conversation_summaries.db
COPY --chown=ubuntu:ubuntu \
    Config/antigravity-cli/settings.json \
    /home/ubuntu/.gemini/antigravity-cli/settings.json
