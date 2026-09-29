#!/usr/bin/env bash
# Toggle SDCIO paths in kpt packages via package-root .krmignore (kpt only honors
# .krmignore at a Kptfile root or nested subpackage — not arbitrary subdirs).
# Usage: configure-sdcio-kpt.sh <nok-kpt-dir> enabled|disabled
set -euo pipefail

NOK_KPT_DIR="${1:?usage: configure-sdcio-kpt.sh <nok-kpt-dir> enabled|disabled}"
MODE="${2:?usage: configure-sdcio-kpt.sh <nok-kpt-dir> enabled|disabled}"

if [[ ! -f "${NOK_KPT_DIR}/nok-base/Kptfile" ]]; then
  echo "Error: ${NOK_KPT_DIR} is not a kpt checkout — run 'make git-clone-kpt' first" >&2
  exit 1
fi

# Legacy nested ignores (ineffective); remove when toggling either way.
legacy_ignores=(
  nok-base/sdcio/.krmignore
  nok-bng/ndt-sdcio-visual/.krmignore
  nok-dia/ndt-sdcio-visual/.krmignore
  nok-cgnat/ndt-sdcio-visual/.krmignore
)
for f in "${legacy_ignores[@]}"; do
  rm -f "${NOK_KPT_DIR}/${f}"
done

# package:ignore_pattern (glob relative to package root)
entries=(
  "nok-base:sdcio/**"
  "nok-bng:ndt-sdcio-visual/**"
  "nok-dia:ndt-sdcio-visual/**"
  "nok-cgnat:ndt-sdcio-visual/**"
)

krmignore_file() {
  echo "${NOK_KPT_DIR}/$1/.krmignore"
}

remove_pattern() {
  local pkg="$1" pattern="$2"
  local f
  f="$(krmignore_file "$pkg")"
  [[ -f "$f" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  grep -vxF "$pattern" "$f" >"$tmp" || true
  if [[ -s "$tmp" ]]; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp" "$f"
  fi
}

add_pattern() {
  local pkg="$1" pattern="$2"
  local f
  f="$(krmignore_file "$pkg")"
  if [[ -f "$f" ]] && grep -qxF "$pattern" "$f"; then
    return 0
  fi
  echo "$pattern" >>"$f"
}

for entry in "${entries[@]}"; do
  pkg="${entry%%:*}"
  pattern="${entry#*:}"
  [[ -d "${NOK_KPT_DIR}/${pkg}" ]] || continue
  if [[ "$MODE" == "disabled" ]]; then
    add_pattern "$pkg" "$pattern"
  else
    remove_pattern "$pkg" "$pattern"
  fi
done

if [[ "$MODE" == "disabled" ]]; then
  echo "--> SDCIO: disabled — excluded from kpt apply (package-root .krmignore)"
  echo "    Warning: next kpt live apply may prune SDCIO resources (including config-server PVCs)."
else
  echo "--> SDCIO: enabled (platform + recipe exporters)"
fi
