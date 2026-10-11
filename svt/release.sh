#!/usr/bin/env bash
# Publish a packaged build as a GitHub release of SVT-Proton.
#
#   svt/release.sh            publish the archive svt/package.sh made for this version
#   svt/release.sh --rev 2    publish the -r2 rebuild of the same upstream version
#   svt/release.sh --draft    create it as a draft to look over first
#
# Release tag: svt-<upstream version> (svt-11.0-2e, svt-11.0-2e-r2). These are
# our own tags; Valve's proton-* tags are never reused. Assets: the archive (named
# with its architecture, SVT-Proton-<version>-x86_64.tar.xz) and
# SHA256SUMS.txt. Needs the GitHub CLI, logged in with push access.
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
svt_read_upstream

rev="" draft=()
while (($#)); do
    case "$1" in
        --rev) rev="${2:?--rev needs a number}"; shift 2 ;;
        --draft) draft=(--draft); shift ;;
        -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) svt_die "unknown argument $1" ;;
    esac
done

command -v gh >/dev/null || svt_die "the GitHub CLI (gh) is needed"
svt_require_branch "$SVT_ROOT"
svt_require_clean "$SVT_ROOT"

# What is released must be what is on GitHub.
git -C "$SVT_ROOT" fetch --quiet origin "$SVT_BRANCH"
[[ "$(git -C "$SVT_ROOT" rev-parse HEAD)" == "$(git -C "$SVT_ROOT" rev-parse "origin/$SVT_BRANCH")" ]] ||
    svt_die "this branch is not what origin/$SVT_BRANCH has; push it first"

version="$(svt_version_from_tag "$PROTON_TAG")"
name="SVT-Proton-$version${rev:+-r$rev}-$SVT_ARCH"
tag="svt-$version${rev:+-r$rev}"  # the release holds one archive per architecture
archive="$SVT_RELEASE_DIR/$name.tar.xz"
[[ -f "$archive" ]] || svt_die "no $archive; run svt/package.sh"
if gh release view "$tag" --repo "$SVT_GITHUB_REPO" >/dev/null 2>&1; then
    svt_die "release $tag already exists (a rebuild of the same version needs --rev N)"
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
notes="$staging/notes.md"
# The checksum file for exactly the archive being uploaded, in the form
# `sha256sum --check` (and the steam-utility-launcher) reads.
sums="$staging/SHA256SUMS.txt"
(cd "$SVT_RELEASE_DIR" && sha256sum "$name.tar.xz") >"$sums"
{
    echo "SVT-Proton $version: Valve's Proton $version with these changes."
    echo
    echo "Based on \`$PROTON_TAG\`. Changes in Proton:"
    git -C "$SVT_ROOT" log --format='- %s' --no-merges "$PROTON_TAG..HEAD" -- . ':!wine' | grep -v '^- svt: point wine' || true
    echo
    echo "Changes in Wine (on \`${WINE_COMMIT:0:12}\`):"
    git -C "$SVT_WINE_DIR" log --format='- %s' --no-merges "$WINE_COMMIT..$SVT_BRANCH"
    echo
    echo "## Install"
    echo
    echo "Extract it into Steam's compatibility tools folder and restart Steam:"
    echo
    echo '```'
    echo "mkdir -p ~/.local/share/Steam/compatibilitytools.d"
    echo "tar -xJf $name.tar.xz -C ~/.local/share/Steam/compatibilitytools.d"
    echo '```'
    echo
    echo "Then choose **$SVT_BUILD_NAME** under the game's Properties > Compatibility."
    echo "Verify the download with \`sha256sum --check SHA256SUMS.txt\`."
} >"$notes"

gh release create "$tag" "$archive" "$sums" \
    --repo "$SVT_GITHUB_REPO" \
    --target "$(git -C "$SVT_ROOT" rev-parse HEAD)" \
    --title "SVT-Proton $version${rev:+ (r$rev)}" \
    --notes-file "$notes" \
    "${draft[@]}"
echo "Released $tag"
