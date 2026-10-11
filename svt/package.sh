#!/usr/bin/env bash
# Package the build for release: $SVT_RELEASE_DIR/SVT-Proton-<version>-<arch>.tar.xz
# (svt/release.sh adds the SHA256SUMS.txt that goes with it).
#
#   svt/package.sh            first build of an upstream version: SVT-Proton-11.0-2e-x86_64.tar.xz
#   svt/package.sh --rev 2    a rebuild of the same upstream version: SVT-Proton-11.0-2e-r2-x86_64.tar.xz
#
# The archive has one top-level folder, named for the tool (SVT-Proton-11.0), so extracting it inside
# Steam's compatibilitytools.d is the whole installation. The version in the
# name is the upstream Proton version the build is based on.
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
svt_read_upstream

rev=""
while (($#)); do
    case "$1" in
        --rev) rev="${2:?--rev needs a number}"; shift 2 ;;
        -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) svt_die "unknown argument $1" ;;
    esac
done
[[ -z "$rev" || "$rev" =~ ^[0-9]+$ ]] || svt_die "--rev takes a number"

dist="$SVT_BUILD_DIR/dist"
[[ -f "$dist/version" ]] || svt_die "no build at $dist; run svt/build.sh"
tag="$(cut -d' ' -f2 "$dist/version")"
[[ "$tag" == proton-* ]] || svt_die "unexpected version '$tag' in $dist/version"
version="$(svt_version_from_tag "$tag")"
name="SVT-Proton-$version${rev:+-r$rev}-$SVT_ARCH"

mkdir -p "$SVT_RELEASE_DIR"
archive="$SVT_RELEASE_DIR/$name.tar.xz"
[[ ! -e "$archive" ]] || svt_die "$archive already exists (a rebuild of the same version needs --rev N)"

echo "Packaging $name (this takes a few minutes)..."
XZ_OPT="${XZ_OPT:--T0 -6}" tar -C "$dist" \
    --transform "s,^\.,$SVT_BUILD_NAME," \
    --owner=0 --group=0 --numeric-owner \
    -cJf "$archive" .

echo "$archive ($(du -h "$archive" | cut -f1))"
(cd "$SVT_RELEASE_DIR" && sha256sum "$name.tar.xz")
echo "Next: svt/release.sh${rev:+ --rev $rev}"
