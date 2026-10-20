#!/bin/bash
set -e

# Required Environment Variables:
# - GITHUB_PAT: Personal Access Token with 'repo' scope (to generate registration token)
# - GITHUB_OWNER: The repository owner (e.g., tayloraswift)
# - GITHUB_REPO: The repository name (e.g., swift-docker-wasm)
# - RUNNER_NAME: (Optional) Name of the runner
# - RUNNER_LABELS: (Optional) Comma-separated runner labels, defaulting to
#   self-hosted,ubuntu-24.04,swift-wasm

if [ -z "$GITHUB_PAT" ]; then
    echo "Error: GITHUB_PAT is not set."
    exit 1
fi

REG_URL="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners/registration-token"
echo "Requesting registration token from: $REG_URL"

# 1. Get the registration token using the PAT
PAYLOAD=$(curl -sX POST -H "Authorization: token ${GITHUB_PAT}" ${REG_URL})
RUNNER_TOKEN=$(echo $PAYLOAD | jq .token --raw-output)

if [ "$RUNNER_TOKEN" == "null" ]; then
    echo "Error: Failed to get registration token. Response: $PAYLOAD"
    exit 1
fi

# 2. Configure the runner
# --ephemeral: Runner will process one job and then unconfigure itself
# --unattended: Don't ask for user input
# --replace: Replace any existing runner with the same name
./config.sh \
    --url "https://github.com/${GITHUB_OWNER}" \
    --token "${RUNNER_TOKEN}" \
    --ephemeral \
    --unattended \
    --replace \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --labels "${RUNNER_LABELS:-self-hosted,ubuntu-24.04,swift-wasm}"

# 3. Run the runner
echo "Starting runner..."
./run.sh
