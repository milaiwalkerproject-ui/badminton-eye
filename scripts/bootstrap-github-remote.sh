#!/usr/bin/env bash
# bootstrap-github-remote.sh
# One-shot bootstrap to create the GitHub repo, set origin, push every
# wanman/* feature branch, and open a PR per branch. Idempotent: safe to
# re-run after partial progress.
#
# Usage:
#   ./scripts/bootstrap-github-remote.sh <owner>/<repo>
# Example:
#   ./scripts/bootstrap-github-remote.sh milaiwalkerproject/badminton-eye
#
# Prerequisites:
#   1. gh CLI installed       (https://cli.github.com/)
#   2. gh auth login          (interactive; run once before this script)
#   3. git remote 'origin' may or may not already point at the target repo
#
# What it does:
#   1. Verifies gh authentication (fails fast with clear instructions)
#   2. Creates <owner>/<repo> on GitHub if it does not exist (private)
#   3. Sets/updates 'origin' to the canonical SSH or HTTPS URL gh returns
#   4. Pushes 'main' and every local 'wanman/*' branch
#   5. Opens a PR for each wanman/* branch against main, attaching the
#      capsule goal/acceptance from `wanman capsule list` when available
#   6. Prints a summary of created / existing / skipped PRs
#
# Exit codes:
#   0  - success (or nothing to do)
#   1  - usage error
#   2  - gh not installed
#   3  - gh not authenticated
#   4  - repo creation failed
#   5  - push failed for at least one branch

set -euo pipefail

REPO_SLUG="${1:-}"

if [[ -z "$REPO_SLUG" || "$REPO_SLUG" != */* ]]; then
  echo "Usage: $0 <owner>/<repo>" >&2
  echo "Example: $0 milaiwalkerproject/badminton-eye" >&2
  exit 1
fi

# Resolve repo root from this script's location (script lives in scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# 1. gh installed?
if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not installed. Install from https://cli.github.com/" >&2
  exit 2
fi

# 2. gh authenticated?
if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: gh is not authenticated.
Run interactively first:
    gh auth login
Pick GitHub.com -> HTTPS -> Login with a web browser, then re-run:
    $0 $REPO_SLUG
EOF
  exit 3
fi

echo "==> gh authenticated as: $(gh api user -q .login)"

# 3. Ensure the GitHub repo exists
if gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
  echo "==> Repo $REPO_SLUG already exists on GitHub"
else
  echo "==> Creating private repo $REPO_SLUG"
  if ! gh repo create "$REPO_SLUG" --private --description "Badminton scoring iOS app" --disable-issues=false --disable-wiki=false; then
    echo "ERROR: failed to create $REPO_SLUG" >&2
    exit 4
  fi
fi

# 4. Set origin remote
REMOTE_URL="$(gh repo view "$REPO_SLUG" --json sshUrl -q .sshUrl)"
if git remote get-url origin >/dev/null 2>&1; then
  CURRENT="$(git remote get-url origin)"
  if [[ "$CURRENT" != "$REMOTE_URL" ]]; then
    echo "==> Updating origin: $CURRENT -> $REMOTE_URL"
    git remote set-url origin "$REMOTE_URL"
  else
    echo "==> origin already set to $REMOTE_URL"
  fi
else
  echo "==> Adding origin = $REMOTE_URL"
  git remote add origin "$REMOTE_URL"
fi

# 5. Push main first so PRs have a base
echo "==> Pushing main"
git push -u origin main

# 6. Push every wanman/* branch
PUSH_FAILED=0
mapfile -t WANMAN_BRANCHES < <(git for-each-ref --format='%(refname:short)' refs/heads/wanman/)
if [[ ${#WANMAN_BRANCHES[@]} -eq 0 ]]; then
  echo "==> No wanman/* branches to push"
else
  for br in "${WANMAN_BRANCHES[@]}"; do
    echo "==> Pushing $br"
    if ! git push -u origin "$br"; then
      echo "WARN: push failed for $br" >&2
      PUSH_FAILED=1
    fi
  done
fi

# 7. Open PRs (skip if one already exists)
declare -a CREATED EXISTING
for br in "${WANMAN_BRANCHES[@]}"; do
  EXISTING_PR="$(gh pr list --head "$br" --base main --state open --json number -q '.[0].number' 2>/dev/null || true)"
  if [[ -n "$EXISTING_PR" ]]; then
    EXISTING+=("$br#$EXISTING_PR")
    continue
  fi

  TITLE="$(git log -1 --pretty=%s "$br")"
  # Pull the goal+acceptance from wanman capsule list when available
  CAPSULE_LINE=""
  if command -v wanman >/dev/null 2>&1; then
    CAPSULE_LINE="$(wanman capsule list 2>/dev/null | awk -v b="$br" 'index($0, b)' | head -1 || true)"
  fi
  BODY=$(cat <<EOF
## Summary
Branch: \`$br\`
Auto-opened by \`scripts/bootstrap-github-remote.sh\`.

## Capsule
${CAPSULE_LINE:-No capsule metadata found.}

## Test plan
- [ ] Tests pass in CI
- [ ] Coverage gate (>= 95%) holds on changed files
- [ ] Manual smoke if user-facing
EOF
)
  if PR_URL="$(gh pr create --base main --head "$br" --title "$TITLE" --body "$BODY" 2>&1)"; then
    CREATED+=("$br -> $PR_URL")
  else
    echo "WARN: failed to open PR for $br: $PR_URL" >&2
  fi
done

echo
echo "===================="
echo "Bootstrap summary"
echo "===================="
echo "Repo:         $REPO_SLUG"
echo "Origin:       $REMOTE_URL"
echo "Branches:     ${#WANMAN_BRANCHES[@]}"
echo "PRs created:  ${#CREATED[@]}"
for line in "${CREATED[@]:-}"; do
  [[ -n "$line" ]] && echo "  + $line"
done
echo "PRs existing: ${#EXISTING[@]}"
for line in "${EXISTING[@]:-}"; do
  [[ -n "$line" ]] && echo "  = $line"
done

if [[ $PUSH_FAILED -ne 0 ]]; then
  echo
  echo "WARN: at least one branch failed to push - re-run after resolving" >&2
  exit 5
fi
