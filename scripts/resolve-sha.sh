#!/usr/bin/env bash
# Resolve a tag name to the commit SHA that `actions/checkout` would check out.
# Lightweight tags point straight at a commit; annotated tags point at a tag
# object that has to be dereferenced one more hop.
set -euo pipefail

TAG="${1:?tag name required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"

if ! ref_json="$(gh api "repos/${REPO}/git/ref/tags/${TAG}" 2>&1)"; then
  echo "::error::Tag '${TAG}' not found in ${REPO}: ${ref_json}" >&2
  exit 1
fi

object_type="$(jq -r '.object.type' <<<"$ref_json")"
object_sha="$(jq -r '.object.sha' <<<"$ref_json")"

if [[ "$object_type" == "tag" ]]; then
  object_sha="$(gh api "repos/${REPO}/git/tags/${object_sha}" --jq '.object.sha')"
fi

if [[ ! "$object_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Resolved an unexpected value for tag '${TAG}': ${object_sha}" >&2
  exit 1
fi

printf '%s\n' "$object_sha"
