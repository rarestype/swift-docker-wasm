FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

ARG TARGETARCH
ARG SWIFT_WASM_TRIPLE='wasm32-unknown-wasip1-threads'
ARG SWIFT_RELEASE='6.3.1'
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
apt -y install curl


SWIFT_WASM_URL="https://github.com/rarestype/swift-sdk-wasm/releases/download/\
swift-${SWIFT_VERSION}/${SWIFT_WASM_SDK}.artifactbundle.zip"

echo "Downloading Swift WebAssembly SDK from: ${SWIFT_WASM_URL}"
curl -fsSL "${SWIFT_WASM_URL}" -o swift-wasm.artifactbundle.zip

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
    gh \
    git-filter-repo \
    jq \
    imagemagick \
    libjemalloc2 \
    libjemalloc-dev \
    liblz4-dev \
    libsqlite3-dev \
    libssl-dev \
    nodejs \
    passwd \
    pip \
    sudo \
    wabt \
    xxd

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
rm -rf aws awscliv2.zip awscliv2.zip.sig aws-public.key
rm -rf /var/lib/apt/lists/*

# verify installations
echo "NodeJS: $(node --version)"
echo "AWS CLI: $(aws --version)"
swift --version
swift sdk list --swift-sdks-path "$SWIFT_WASM_SDK_PATH"

EOF

WORKDIR /home/ubuntu

RUN passwd -d ubuntu
RUN usermod -aG sudo ubuntu

# Switch back to the standard user for default execution
USER ubuntu
ENV HOME=/home/ubuntu
CMD ["sleep", "infinity"]
