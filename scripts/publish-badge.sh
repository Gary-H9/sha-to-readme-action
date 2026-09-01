#!/usr/bin/env bash
# Publish a shields.io "endpoint" JSON file to a dedicated badge branch.
#
# The README markup never changes: it points at a fixed endpoint URL, and only
# the JSON behind it is rewritten. That avoids rewriting tracked files on the
# default branch, so there are no push races and no self-triggering commits.
set -euo pipefail

SHA="${SHA:?SHA required}"
TAG="${TAG:?TAG required}"
BRANCH="${BRANCH:?BRANCH required}"
FILENAME="${FILENAME:?FILENAME required}"
LABEL="${LABEL:-release sha}"
COLOR="${COLOR:-blue}"
SHORT="${SHORT:-false}"
CACHE_SECONDS="${CACHE_SECONDS:-300}"
TOKEN="${TOKEN:?TOKEN required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"

message="$SHA"
if [[ "$SHORT" == "true" ]]; then
  message="${SHA:0:7}"
fi

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

jq -n \
  --arg label "$LABEL" \
  --arg message "$message" \
  --arg color "$COLOR" \
  --arg tag "$TAG" \
  --arg sha "$SHA" \
  --argjson cache "$CACHE_SECONDS" \
  '{schemaVersion: 1, label: $label, message: $message, color: $color,
    cacheSeconds: $cache, tag: $tag, sha: $sha}' >"${workdir}/payload.json"

repo_dir="${workdir}/repo"
mkdir -p "$repo_dir"
cd "$repo_dir"

host="${SERVER_URL#https://}"
remote="https://x-access-token:${TOKEN}@${host}/${REPO}.git"

git init -q .
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git remote add origin "$remote"

# Base on the existing badge branch when there is one, so other badge files on
# that branch survive the force-push below.
if git fetch -q --depth=1 origin "$BRANCH" 2>/dev/null; then
  git checkout -q FETCH_HEAD
  git checkout -q -B "$BRANCH"
else
  git checkout -q -b "$BRANCH"
fi

mkdir -p "$(dirname "$FILENAME")"
cp "${workdir}/payload.json" "$FILENAME"
git add -- "$FILENAME"

if git diff --cached --quiet; then
  echo "Badge JSON already up to date for ${TAG} (${SHA})."
else
  git commit -q -m "chore: release ${TAG} points at ${SHA}"
  # Force-push: this branch is a data store, not history worth preserving, and
  # forcing keeps concurrent releases from failing on a non-fast-forward.
  git push -q --force origin "HEAD:refs/heads/${BRANCH}"
  echo "Published badge JSON for ${TAG} (${SHA})."
fi

raw_url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${FILENAME}"
if [[ "$host" != "github.com" ]]; then
  raw_url="${SERVER_URL}/${REPO}/raw/${BRANCH}/${FILENAME}"
fi
badge_url="https://img.shields.io/endpoint?url=$(jq -rn --arg u "$raw_url" '$u|@uri')"

{
  echo "json-url=${raw_url}"
  echo "badge-url=${badge_url}"
} >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
