#!/bin/bash

# Configuration
# We default the image, but we do NOT default the target repo.
IMAGE_NAME="${IMAGE_NAME:-tayloraswift/swiftwasm:runner}"
CONTAINER_NAME="${CONTAINER_NAME:-swift-wasm-runner-ephemeral}"

# 1. Validate PAT
if [ -z "$GH_RUNNER_PAT" ]; then
    echo "❌ Error: GH_RUNNER_PAT is not set."
    echo "   You must provide a Personal Access Token with 'repo' scope."
    exit 1
fi

# 2. Validate Target Repository
if [ -z "$GITHUB_OWNER" ]; then
    echo "❌ Error: GITHUB_OWNER is not set."
    echo "   This runner script is generic; you must tell it where to connect."
    echo "   "
    echo "   Usage Example:"
    echo "     export GITHUB_OWNER='my-org'"
    echo "     ./runner-start.sh"
    exit 1
fi

echo "🚀 Starting ephemeral runner loop..."
echo "   Target: $GITHUB_OWNER"
echo "   Image:  $IMAGE_NAME"

while true; do
    echo "------------------------------------------------"
    echo "Checking for updates to $IMAGE_NAME..."
    docker pull $IMAGE_NAME

    # Prune dangling images to prevent disk from filling up
    docker image prune -f

    echo "Launching runner..."
    # disable IPv6, to prevent long timeouts in buildings that lack IPv6 access
    # if your runners have IPv6 access, remove the `sysctl` lines
    docker run --rm \
        --sysctl net.ipv6.conf.all.disable_ipv6=1 \
        --sysctl net.ipv6.conf.default.disable_ipv6=1 \
        --name "$CONTAINER_NAME" \
        -e GITHUB_PAT="$GH_RUNNER_PAT" \
        -e GITHUB_OWNER="$GITHUB_OWNER" \
        -e RUNNER_NAME="${RUNNER_NAME:-runner-$(date +%s)}" \
        -e RUNNER_LABELS \
        $IMAGE_NAME

    echo "Runner exited. Restarting in 5 seconds..."
    sleep 5
done
