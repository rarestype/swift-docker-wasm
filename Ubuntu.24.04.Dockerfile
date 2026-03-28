FROM ubuntu:24.04
ENV DEBIAN_FRONTEND noninteractive
SHELL ["/bin/bash", "-c"]

ARG TARGETARCH
ARG SWIFT_VERSION='6.3'
ARG SWIFT_NIGHTLY=
ARG SWIFT_WASM_SDK_CHECKSUM='9fa4016ee632c7e9e906608ec3b55cf13dfc4dff44e47574c5af58064dc33fd9'
ARG UBUNTU_VERSION='ubuntu24.04'

ENV SWIFT_INSTALLATION="/usr/local/swift"
ENV PATH="$PATH:$SWIFT_INSTALLATION/usr/bin"

COPY aws.public.key aws.public.key
COPY swift.public.key swift.public.key
COPY nodesource.public.gpg /usr/share/keyrings/nodesource.gpg

# Squash the following RUN commands into a single command to reduce image size
RUN <<EOF

# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error.
# -o pipefail: specific for pipes; if 'curl' fails in 'curl | bash', the whole command fails.
set -euo pipefail

apt update
apt -y install curl

if [ "$TARGETARCH" = "arm64" ]; then
    echo "Configuring for aarch64..."
    SWIFT_PLATFORM="aarch64"
    SWIFT_PLATFORM_SUFFIX="-aarch64"
else
    echo "Configuring for x86_64..."
    SWIFT_PLATFORM="x86_64"
    SWIFT_PLATFORM_SUFFIX=""
fi

# Note: The Docker CLI does not print the correct URL to the console, but the actual
# interpolated string passed to `curl` is correct.
if [ -v SWIFT_NIGHTLY ]; then
    SWIFT_BRANCH="swift-${SWIFT_VERSION}-branch"
    SWIFT_TOOLCHAIN="${SWIFT_VERSION}-DEVELOPMENT-${SWIFT_NIGHTLY}"
else
    SWIFT_BRANCH="swift-${SWIFT_VERSION}-release"
    SWIFT_TOOLCHAIN="${SWIFT_VERSION}-RELEASE"
fi

SWIFT_TOOLCHAIN_URL="https://download.swift.org/${SWIFT_BRANCH}/\
${UBUNTU_VERSION//[.]/}${SWIFT_PLATFORM_SUFFIX}/\
swift-${SWIFT_TOOLCHAIN}/\
swift-${SWIFT_TOOLCHAIN}-${UBUNTU_VERSION}${SWIFT_PLATFORM_SUFFIX}.tar.gz"

echo "Downloading Swift toolchain from: $SWIFT_TOOLCHAIN_URL"
curl -fsSL "$SWIFT_TOOLCHAIN_URL.sig" -o toolchain.tar.gz.sig
curl -fsSL "$SWIFT_TOOLCHAIN_URL" -o toolchain.tar.gz

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
mkdir -p "$SWIFT_INSTALLATION"
gpg --import swift.public.key
gpg --verify toolchain.tar.gz.sig toolchain.tar.gz
tar --strip-components=1 -xf toolchain.tar.gz -C "$SWIFT_INSTALLATION"
rm toolchain.tar.gz
rm toolchain.tar.gz.sig
rm swift.public.key

# need to install a newer nodejs than is available by default
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
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
    sudo \
    xxd

# works because AWS uses 'aarch64' and 'x86_64' just like Swift
curl "https://awscli.amazonaws.com/awscli-exe-linux-${SWIFT_PLATFORM}.zip" -o "awscliv2.zip"
curl "https://awscli.amazonaws.com/awscli-exe-linux-${SWIFT_PLATFORM}.zip.sig" -o "awscliv2.zip.sig"

# import the AWS Public Key (key is public/static from AWS docs)
gpg --import aws.public.key
gpg --verify awscliv2.zip.sig awscliv2.zip

unzip awscliv2.zip
./aws/install

# clean up cached files
rm -rf aws awscliv2.zip awscliv2.zip.sig aws-public.key
rm -rf /var/lib/apt/lists/*

# verify installations
node -v
aws --version

EOF

WORKDIR /home/ubuntu

RUN passwd -d ubuntu
RUN usermod -aG sudo ubuntu

ENV SWIFT_WASM_SDK="${SWIFT_TOOLCHAIN}-wasm32-unknown-wasip1-threads"
ENV SWIFT_WASM_SDK_PATH='/usr/local/share/swift'

RUN swift sdk install \
    https://github.com/swiftwasm/swift/releases/download/swift-wasm-${SWIFT_VERSION}-${SWIFT_NIGHTLY}/swift-wasm-${SWIFT_VERSION}-${SWIFT_NIGHTLY}-wasm32-unknown-wasip1-threads.artifactbundle.zip \
    --checksum ${SWIFT_WASM_SDK_CHECKSUM} \
    --swift-sdks-path "$SWIFT_WASM_SDK_PATH"

# Switch back to the standard user for default execution
USER ubuntu
ENV HOME /home/ubuntu
CMD ["sleep", "infinity"]
