#!/usr/bin/env bash
# Build SVT-Proton from this checkout. The result is $SVT_BUILD_DIR/dist.
#
#   svt/build.sh
#
# Needs Docker (or Podman: SVT_CONTAINER_ENGINE=podman), git, and tens of GB of
# disk; the first build takes hours, later ones far less (ccache). The build
# must come from a committed, pushed state: the wine submodule has to exist on
# GitHub (push SVT-wine first), and a release should be reproducible.
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
svt_read_upstream

svt_require_branch "$SVT_ROOT"
svt_require_clean "$SVT_ROOT"

# The version recorded in the build is the nearest upstream release tag, so the
# tags must be here (a fork does not copy them; svt/update.sh fetches them).
version_tag="$(git -C "$SVT_ROOT" describe --tags --abbrev=0 --match 'proton-*' 2>/dev/null)" ||
    svt_die "no upstream release tags here: git -C $SVT_ROOT fetch upstream --tags"
[[ "$version_tag" == "$PROTON_TAG" ]] ||
    svt_die "the nearest upstream tag is $version_tag but svt/UPSTREAM says $PROTON_TAG; run svt/update.sh --refresh"

echo "Building $SVT_BUILD_NAME for $version_tag"
git -C "$SVT_ROOT" submodule sync --quiet --recursive
git -C "$SVT_ROOT" submodule update --init --recursive --jobs 8

mkdir -p "$SVT_BUILD_DIR"
cd "$SVT_BUILD_DIR"
if [[ ! -f Makefile ]]; then
    "$SVT_ROOT/configure.sh" --enable-ccache \
        --build-name="$SVT_BUILD_NAME" \
        --container-engine="$SVT_CONTAINER_ENGINE"
fi
make -j"$(nproc)"

echo
echo "Built: $SVT_BUILD_DIR/dist ($(cut -d' ' -f2 dist/version))"
echo "Next: svt/package.sh"
