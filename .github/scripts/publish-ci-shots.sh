#!/usr/bin/env bash
# Force-push a directory (index.md, screenshots, logs) to the ci-shots branch as one fresh commit.
# Needs GH_TOKEN (github.token). Never prints the token or Authorization header.
set -eo pipefail
: "${GH_TOKEN:?GH_TOKEN is required}"
dir="${1:-tmp/ci-shots}"

cd "$dir"
rm -rf .git
git init --initial-branch=ci-shots
git add -A -- .
git -c user.name='github-actions[bot]' \
    -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit -m "CI result for $GITHUB_SHA"
basic="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0=http.extraHeader \
GIT_CONFIG_VALUE_0="Authorization: Basic $basic" \
    git push --force "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY.git" HEAD:refs/heads/ci-shots
