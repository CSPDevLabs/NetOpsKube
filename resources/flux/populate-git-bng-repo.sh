#!/bin/bash

# --- Configuration ---
REMOTE_URL="ssh://git@172.18.0.102/nok/nok-bng-resources.git"
REPO_DIR="nok-bng-resources"
BRANCH="main"
SSH_KEY="$HOME/.ssh/id_ed25519"

# Double-check this base URL in your browser to ensure it's public/accessible
BASE_RAW_URL="https://raw.githubusercontent.com/CSPDevLabs/kpt/refs/heads/mau_gnmi_operator/nok-bng"

# Mapping: "Local Path" -> "Remote File Path (Relative to BASE_RAW_URL)"
declare -A FILES_TO_DOWNLOAD=(
    ["gnmic-metrics/gnmi-metrics-pipe.yaml"]="gnmic-metrics/gnmi-metrics-pipe.yaml"
    ["gnmic-metrics/gnmi-state-pipe.yaml"]="gnmic-state/gnmic-state-pipe.yaml"
    ["sdcio-targets/targets.yaml"]="targets/targets.yaml"
    ["additional-targets/targets.yaml"]="additonal-targets/bngt-bngblaster.yaml"
)

# --- Safety ---
set -euo pipefail

log_error() { echo -e "\e[31m[ERROR]\e[0m $1" >&2; }
log_info()  { echo -e "\e[34m[INFO]\e[0m $1"; }

# --- Execution ---

# 1. Setup local environment
log_info "Initializing local repository..."
mkdir -p "$REPO_DIR" && cd "$REPO_DIR"
[ ! -d ".git" ] && git init -b "$BRANCH"

# Force Git to use the specific SSH key for this repository
git config core.sshCommand "ssh -i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

log_info "Downloading resources from GitHub..."
for LOCAL_PATH in "${!FILES_TO_DOWNLOAD[@]}"; do
    REMOTE_PART="${FILES_TO_DOWNLOAD[$LOCAL_PATH]}"
    FULL_URL="$BASE_RAW_URL/$REMOTE_PART"
    
    mkdir -p "$(dirname "$LOCAL_PATH")"
    
    # Check if the file exists on the server first to provide a better error
    HTTP_CODE=$(curl -o /dev/null -sL -w "%{http_code}" "$FULL_URL")
    
    if [ "$HTTP_CODE" -ne 200 ]; then
        log_error "File not found (HTTP $HTTP_CODE): $FULL_URL"
        log_error "Please verify the branch name and folder structure in the source repo."
        exit 1
    fi

    curl -sL -o "$LOCAL_PATH" "$FULL_URL"
    log_info "Retrieved: $LOCAL_PATH"
done

# Ensure empty directories are tracked
mkdir -p conf-snipets
touch conf-snipets/.gitkeep

# Push to your private Flux repo
log_info "Syncing to $REMOTE_URL..."
git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"
git add .

if ! git diff-index --quiet HEAD --; then
    git commit -m "Automated update: $(date +'%Y-%m-%d %H:%M:%S')"
    git push -u origin "$BRANCH" --force
else
    log_info "No changes detected. Repository is up to date."
fi
