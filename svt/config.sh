# shellcheck shell=bash
# Shared settings for the svt/ scripts. Sourced, not run.
# Every value can be overridden from the environment.

SVT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The tool is named for the Proton series it follows, SVT-Proton-11.0: that is
# its folder in compatibilitytools.d, what Steam lists, and the internal name
# Steam stores your per-game choice under. The series (not the release) is in
# it, so the choice survives 11.0-2e -> 11.0-2f yet SVT-Proton-10.0 and
# SVT-Proton-11.0 can be installed side by side. Both it and the branch name
# (svt-<series>) are filled in by svt_read_upstream; set them to override.

# Where the release is published.
SVT_GITHUB_REPO="${SVT_GITHUB_REPO:-sevaht/SVT-Proton}"

# Valve's repositories, which the two forks are kept in step with.
SVT_UPSTREAM_PROTON="${SVT_UPSTREAM_PROTON:-https://github.com/ValveSoftware/Proton.git}"
SVT_UPSTREAM_WINE="${SVT_UPSTREAM_WINE:-https://github.com/ValveSoftware/wine.git}"

# Your clone of SVT-wine, where the Wine changes are made and committed.
# (The wine/ folder inside this repo is only the copy a build checks out.)
SVT_WINE_DIR="${SVT_WINE_DIR:-$SVT_ROOT/../SVT-wine}"

# Build and release output live in svt/out, which git ignores.
SVT_BUILD_DIR="${SVT_BUILD_DIR:-$SVT_ROOT/svt/out/build}"
SVT_RELEASE_DIR="${SVT_RELEASE_DIR:-$SVT_ROOT/svt/out/release}"
SVT_CONTAINER_ENGINE="${SVT_CONTAINER_ENGINE:-docker}"

# The architecture the build targets (what configure.sh builds by default),
# which release archives carry in their name: SVT-Proton-11.0-2e-x86_64.tar.xz.
# A release is one tag with one archive per architecture.
SVT_ARCH="${SVT_ARCH:-x86_64}"

svt_die() {
    echo "${0##*/}: $*" >&2
    exit 1
}

# Reads SERIES, PROTON_TAG and WINE_COMMIT from svt/UPSTREAM, and from the series
# works out SVT_BUILD_NAME and SVT_BRANCH.
svt_read_upstream() {
    # shellcheck source=UPSTREAM
    source "$SVT_ROOT/svt/UPSTREAM"
    [[ -n "${SERIES:-}" && -n "${PROTON_TAG:-}" && -n "${WINE_COMMIT:-}" ]] ||
        svt_die "svt/UPSTREAM is incomplete"
    SVT_BUILD_NAME="${SVT_BUILD_NAME:-SVT-Proton-$SERIES}"
    SVT_BRANCH="${SVT_BRANCH:-svt-$SERIES}"  # the branch both repositories keep our changes on
}

# The newest release tag of the series, e.g. proton-11.0-2e: proton-<series>-<n><letters>,
# so not the -beta and -rc tags.
svt_latest_release_tag() {
    git -C "$SVT_ROOT" tag --list "proton-${SERIES}-*" |
        grep -E "^proton-${SERIES//./\\.}-[0-9]+[a-z]*$" |
        sort -V | tail -n 1
}

# The version of the Proton an SVT build is based on, e.g. 11.0-2e.
svt_version_from_tag() {
    echo "${1#proton-}"
}

svt_require_clean() {
    local dir="$1"
    [[ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ]] ||
        svt_die "$dir has uncommitted changes; commit or stash them first"
}

svt_require_branch() {
    local dir="$1" branch
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
    [[ "$branch" == "$SVT_BRANCH" ]] ||
        svt_die "$dir is on '$branch', expected '$SVT_BRANCH'"
}
