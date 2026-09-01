#!/usr/bin/env bash
# Optional: rewrite a marked block in README.md with the badge plus a
# copy-pasteable `uses:` line, so the SHA is selectable text and not just pixels.
#
# Each attempt clones the target branch fresh rather than reusing the caller's
# checkout, so it works regardless of what ref the workflow checked out and a
# losing race simply retries against the new tip.
set -euo pipefail

SHA="${SHA:?SHA required}"
TAG="${TAG:?TAG required}"
BADGE_URL="${BADGE_URL:?BADGE_URL required}"
README_PATH="${README_PATH:-README.md}"
README_BRANCH="${README_BRANCH:?README_BRANCH required}"
LABEL="${LABEL:-release sha}"
TOKEN="${TOKEN:?TOKEN required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"

host="${SERVER_URL#https://}"
remote="https://x-access-token:${TOKEN}@${host}/${REPO}.git"

# Exit codes: 0 = done, 1 = retryable push rejection, 3 = nothing to do (the
# README or its markers are absent, which is a warning rather than a failure —
# the badge is already published by this point).
attempt_update() {
  local workdir
  workdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" RETURN

  git clone -q --depth=1 --branch "$README_BRANCH" "$remote" "${workdir}/repo"
  cd "${workdir}/repo"
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

  if [[ ! -f "$README_PATH" ]]; then
    echo "::warning::${README_PATH} not found on branch ${README_BRANCH}; skipping the copy-pasteable snippet. The badge itself is published." >&2
    return 3
  fi

  REPO="$REPO" SHA="$SHA" TAG="$TAG" BADGE_URL="$BADGE_URL" LABEL="$LABEL" \
  README_PATH="$README_PATH" python3 - <<'PY' || return 3
import os, re, sys

path = os.environ["README_PATH"]
start, end = "<!--sha-badge-->", "<!--/sha-badge-->"

block = (
    f'{start}\n'
    f'[![{os.environ["LABEL"]}]({os.environ["BADGE_URL"]})]'
    f'(https://github.com/{os.environ["REPO"]}/releases/tag/{os.environ["TAG"]})\n\n'
    '```yaml\n'
    f'uses: {os.environ["REPO"]}@{os.environ["SHA"]} # {os.environ["TAG"]}\n'
    '```\n'
    f'{end}'
)

with open(path, encoding="utf-8") as fh:
    content = fh.read()

pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
if not pattern.search(content):
    print(
        f"::warning::No '{start}' ... '{end}' block found in {path}; "
        "add the markers to get a copy-pasteable `uses:` line.",
        file=sys.stderr,
    )
    sys.exit(1)

updated = pattern.sub(lambda _: block, content, count=1)
if updated != content:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(updated)
PY

  git add -- "$README_PATH"
  if git diff --cached --quiet; then
    echo "${README_PATH} already up to date for ${TAG} (${SHA})."
    return 0
  fi

  git commit -q -m "docs: pin ${TAG} to ${SHA}"
  git push -q origin "HEAD:refs/heads/${README_BRANCH}" || return 1
  echo "Updated ${README_PATH} on ${README_BRANCH}."
}

for attempt in 1 2 3; do
  set +e
  (attempt_update)
  status=$?
  set -e
  case "$status" in
    0|3) exit 0 ;;
    *) echo "Push rejected (attempt ${attempt}); retrying against the new tip." >&2 ;;
  esac
  sleep $((attempt * 3))
done

echo "::error::Could not push ${README_PATH} to ${README_BRANCH} after 3 attempts" >&2
exit 1
