#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: release.sh <version>  (e.g. 1.2.0)}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: version must be MAJOR.MINOR.PATCH (got '$VERSION')" >&2
	exit 1
fi

TAG="v$VERSION"

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || { echo "error: must be on main (on '$branch')" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean" >&2; exit 1; }

git fetch origin main --tags --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
	|| { echo "error: local main not in sync with origin/main" >&2; exit 1; }

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
	|| git ls-remote --exit-code origin "refs/tags/$TAG" >/dev/null 2>&1; then
	echo "error: tag $TAG already exists" >&2
	exit 1
fi

echo "==> tagging $TAG"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

remote_url="$(git remote get-url origin)"
slug="$(echo "$remote_url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
echo
echo "Pushed $TAG. CI is now building and publishing the release:"
echo "  https://github.com/$slug/actions"
echo "  https://github.com/$slug/releases"
