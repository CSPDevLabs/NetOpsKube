
#!/usr/bin/env bash
set -Eeuo pipefail

# Push BNG-specific IPFIX SDCIO manifests to Gitea.
#
# Destination:
#   sdcio/configs/<source-filename>

: "${GITEA_SSH_HOST:?GITEA_SSH_HOST must be set}"
: "${FLUX_SSH_KEY:?FLUX_SSH_KEY must be set}"
: "${FLUX_GIT_BRANCH:?FLUX_GIT_BRANCH must be set}"
: "${BNG_IPFIX_SDCIO_SOURCE_DIR:?BNG_IPFIX_SDCIO_SOURCE_DIR must be set}"
: "${BNG_IPFIX_SDCIO_CONFIG_FILES:?BNG_IPFIX_SDCIO_CONFIG_FILES must be set}"

GITEA_REPO_OWNER="${GITEA_REPO_OWNER:-nok}"
GITEA_REPO_NAME="${GITEA_REPO_NAME:-nok-bng-resources}"

# ------------------------------------------------------------------------------
# Validate prerequisites
# ------------------------------------------------------------------------------

[[ -d "$BNG_IPFIX_SDCIO_SOURCE_DIR" ]] || {
    echo "[ERROR] Source directory not found: $BNG_IPFIX_SDCIO_SOURCE_DIR" >&2
    exit 1
}

[[ -f "$FLUX_SSH_KEY" ]] || {
    echo "[ERROR] SSH key not found: $FLUX_SSH_KEY" >&2
    exit 1
}

for tool in git ssh; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "[ERROR] Required command not found: $tool" >&2
        exit 1
    }
done

read -r -a CONFIG_FILES <<< "$BNG_IPFIX_SDCIO_CONFIG_FILES"

[[ ${#CONFIG_FILES[@]} -gt 0 ]] || {
    echo "[ERROR] No SDCIO configuration files specified." >&2
    exit 1
}

# Validate all source files before cloning.
for file in "${CONFIG_FILES[@]}"; do
    if [[ "$file" == */* || "$file" == *".."* ]]; then
        echo "[ERROR] Invalid source filename: $file" >&2
        exit 1
    fi

    [[ -f "$BNG_IPFIX_SDCIO_SOURCE_DIR/$file" ]] || {
        echo "[ERROR] Source file not found: $BNG_IPFIX_SDCIO_SOURCE_DIR/$file" >&2
        exit 1
    }
done

# ------------------------------------------------------------------------------
# Clone repository
# ------------------------------------------------------------------------------

REPO_URL="ssh://git@${GITEA_SSH_HOST}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ipfix-sdcio.XXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT

printf -v SSH_KEY_QUOTED '%q' "$FLUX_SSH_KEY"
export GIT_SSH_COMMAND="ssh -i ${SSH_KEY_QUOTED} -o IdentitiesOnly=yes"

echo "--> SDCIO: Cloning ${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}"

git clone \
    --branch "$FLUX_GIT_BRANCH" \
    --single-branch \
    "$REPO_URL" \
    "$STAGING_DIR/repo"

cd "$STAGING_DIR/repo"

# ------------------------------------------------------------------------------
# Copy and stage manifests
# ------------------------------------------------------------------------------

DEST_DIR="sdcio/configs"

mkdir -p "$DEST_DIR"

for file in "${CONFIG_FILES[@]}"; do
    SOURCE_FILE="$BNG_IPFIX_SDCIO_SOURCE_DIR/$file"
    DEST_FILE="$DEST_DIR/$file"

    echo "--> SDCIO: Copying $file"

    install -m 0644 "$SOURCE_FILE" "$DEST_FILE"
    git add -- "$DEST_FILE"
done

# ------------------------------------------------------------------------------
# Check changes
# ------------------------------------------------------------------------------

if git diff --cached --quiet; then
    echo "--> SDCIO: No changes to push."
    exit 0
fi

git diff --cached --check
git diff --cached --stat

# ------------------------------------------------------------------------------
# Commit and push
# ------------------------------------------------------------------------------

if ! git var GIT_AUTHOR_IDENT >/dev/null 2>&1; then
    echo "[ERROR] Configure git user.name and git user.email before pushing." >&2
    exit 1
fi

git commit -m "Update SDCIO IPFIX configurations"

echo "--> SDCIO: Pushing to branch ${FLUX_GIT_BRANCH}"

git push origin "HEAD:${FLUX_GIT_BRANCH}"

echo "--> SDCIO: Push completed"
echo "    Repository: ${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}"
echo "    Branch:     ${FLUX_GIT_BRANCH}"
echo "    Files pushed:"

for file in "${CONFIG_FILES[@]}"; do
    echo "      - $file -> ${DEST_DIR}/$file"
done
