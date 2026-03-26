FROM tayloraswift/swiftwasm:master

USER root

# Install GitHub Actions Runner dependencies
RUN apt update && apt install -y \
    curl \
    jq \
    libicu-dev \
    libdigest-sha-perl \
    && rm -rf /var/lib/apt/lists/*

# Switch back to the non-root user 'ubuntu' (created in base image)
USER ubuntu
WORKDIR /home/ubuntu

# https://github.com/actions/runner/releases
ARG RUNNER_VERSION="2.333.0"
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
