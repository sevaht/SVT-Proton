#!/usr/bin/env bash
# Move SVT-Proton and SVT-wine onto a new upstream Proton release.
#
#   svt/update.sh --check          fetch Valve's repositories and say whether there is a new release
#   svt/update.sh                  move to the newest release of the series in svt/UPSTREAM
#   svt/update.sh proton-11.0-2f   move to a specific upstream release tag
#   svt/update.sh --refresh        stay on the same upstream release but re-point wine at
#                                  the current tip of SVT-wine (after you changed a Wine patch)
#   svt/update.sh --new-series 10.0
#                                  start following another Proton series (branch svt-10.0 in
#                                  both repositories, from the current branch's changes, on the
#                                  newest proton-10.0-* release); the current series stays as it is
#   add --push to also push both branches (SVT-wine first, then SVT-Proton)
#
# It runs only when you run it. What it does:
#   1. SVT-wine: replay our Wine commits onto the Wine commit the new tag pins.
#   2. SVT-Proton: replay our own commits onto the new tag, then add one fresh
#      commit "svt: point wine at ..." that sets the wine submodule to the
#      SVT-wine tip (and records the new base in svt/UPSTREAM). That pointer
#      commit is always rebuilt, never rebased: Valve moves the same pointer
#      in nearly every release, so rebasing it would conflict every time.
# If a replay conflicts, git stops where it is: fix it and `git rebase --continue`
# in that repository (SVT-wine first, then SVT-Proton), then finish with
#   svt/update.sh <the new tag> --refresh
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

check_only=0 refresh=0 push=0 target="" new_series=""
while (($#)); do
    case "$1" in
        --check) check_only=1 ;;
        --refresh) refresh=1 ;;
        --push) push=1 ;;
        --new-series) new_series="${2:?--new-series needs a series such as 10.0}"; shift ;;
        -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
        -*) svt_die "unknown option $1" ;;
        *) target="$1" ;;
    esac
    shift
done
((!(refresh && ${#new_series}))) || svt_die "--refresh and --new-series don't go together"

svt_read_upstream
[[ -d "$SVT_WINE_DIR/.git" ]] || svt_die "no SVT-wine clone at $SVT_WINE_DIR (set SVT_WINE_DIR)"

ensure_upstream() { # repository, url
    git -C "$1" remote get-url upstream >/dev/null 2>&1 ||
        git -C "$1" remote add upstream "$2"
}
ensure_upstream "$SVT_ROOT" "$SVT_UPSTREAM_PROTON"
ensure_upstream "$SVT_WINE_DIR" "$SVT_UPSTREAM_WINE"
echo "Fetching Valve's repositories..."
git -C "$SVT_ROOT" fetch --quiet --tags --no-recurse-submodules upstream
git -C "$SVT_WINE_DIR" fetch --quiet --tags upstream

latest="$(svt_latest_release_tag)"
if ((check_only)); then
    echo "based on:  $PROTON_TAG"
    echo "newest:    $latest"
    [[ "$latest" == "$PROTON_TAG" ]] && echo "up to date" || echo "a new release is available: svt/update.sh"
    exit 0
fi

svt_require_branch "$SVT_ROOT"
svt_require_branch "$SVT_WINE_DIR"
svt_require_clean "$SVT_ROOT"
svt_require_clean "$SVT_WINE_DIR"

if [[ -n "$new_series" ]]; then
    [[ "$new_series" =~ ^[0-9]+\.[0-9]+$ ]] || svt_die "a series looks like 10.0"
    [[ "$new_series" != "$SERIES" ]] || svt_die "already following Proton $SERIES"
    new_branch="svt-$new_series"
    for repo in "$SVT_ROOT" "$SVT_WINE_DIR"; do
        git -C "$repo" show-ref -q --verify "refs/heads/$new_branch" &&
            svt_die "$repo already has a branch $new_branch"
    done
    SERIES="$new_series"
    latest="$(svt_latest_release_tag)"
    [[ -n "$latest" ]] || svt_die "no proton-$new_series-* release tags in $SVT_ROOT"
    echo "Starting Proton $new_series from the current branch's changes; newest release is $latest"
    git -C "$SVT_ROOT" checkout -q -b "$new_branch"
    git -C "$SVT_WINE_DIR" checkout -q -b "$new_branch"
    SVT_BRANCH="$new_branch"
fi

# --refresh never replays anything: it only rebuilds the pointer commit, for
# the current base or (after resolving a conflict by hand) for the given tag.
if ((refresh)); then
    tag="${target:-$PROTON_TAG}"
else
    tag="${target:-$latest}"
fi
git -C "$SVT_ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null || svt_die "no such upstream tag: $tag"
new_wine="$(git -C "$SVT_ROOT" ls-tree "$tag" wine | awk '{print $3}')"
[[ -n "$new_wine" ]] || svt_die "$tag does not pin a wine commit"
git -C "$SVT_WINE_DIR" cat-file -e "$new_wine^{commit}" 2>/dev/null ||
    svt_die "SVT-wine does not have $new_wine (git -C $SVT_WINE_DIR fetch upstream)"

if ((!refresh)) && [[ "$tag" == "$PROTON_TAG" ]]; then
    echo "Already based on $tag; nothing to do (use --refresh to re-point wine)."
    exit 0
fi
# A new tag is only recorded (in svt/UPSTREAM) once its pointer commit exists.

# The pointer commit from last time goes away, wherever it is (a commit added
# on top of it is fine); it is rebuilt below. The base is where this branch
# sits now: the old tag, or (after resolving a conflict by hand) the new one.
# Commits before the first pointer commit are left exactly as they are; the
# ones after it are cherry-picked back, minus the pointer commits.
drop_pointer_commits() { # the commit the branch sits on
    local base="$1" c new_top="$1" seen=0 all=() replay=()
    mapfile -t all < <(git -C "$SVT_ROOT" rev-list --reverse "$base..HEAD")
    for c in "${all[@]}"; do
        if [[ "$(git -C "$SVT_ROOT" log -1 --format=%s "$c")" == "svt: point wine"* ]]; then
            seen=1
        elif ((seen)); then
            replay+=("$c")
        else
            new_top="$c"
        fi
    done
    ((seen)) || return 0
    git -C "$SVT_ROOT" reset --hard --quiet "$new_top"
    for c in "${replay[@]}"; do
        git -C "$SVT_ROOT" cherry-pick "$c" >/dev/null
    done
}
if ((refresh)); then drop_pointer_commits "$tag"; else drop_pointer_commits "$PROTON_TAG"; fi

if [[ -n "$new_series" ]]; then
    sed -i -E "s/^SERIES=.*/SERIES=$new_series/" "$SVT_ROOT/svt/UPSTREAM"
    git -C "$SVT_ROOT" add svt/UPSTREAM
    git -C "$SVT_ROOT" commit --quiet -m "svt: follow Proton $new_series"
fi

if ((!refresh)) && [[ "$tag" != "$PROTON_TAG" ]]; then
    echo "SVT-wine: replaying our commits onto $new_wine"
    git -C "$SVT_WINE_DIR" rebase --onto "$new_wine" "$WINE_COMMIT" "$SVT_BRANCH"
    echo "SVT-Proton: replaying our commits onto $tag"
    git -C "$SVT_ROOT" rebase --onto "$tag" "$PROTON_TAG" "$SVT_BRANCH"
fi

wine_tip="$(git -C "$SVT_WINE_DIR" rev-parse "$SVT_BRANCH")"
git -C "$SVT_ROOT" update-index --add --cacheinfo "160000,$wine_tip,wine"
sed -i -E "s/^PROTON_TAG=.*/PROTON_TAG=$tag/; s/^WINE_COMMIT=.*/WINE_COMMIT=$new_wine/" "$SVT_ROOT/svt/UPSTREAM"
git -C "$SVT_ROOT" add svt/UPSTREAM
git -C "$SVT_ROOT" commit --quiet -m "svt: point wine at SVT-wine ${wine_tip:0:12} (Proton $tag)"

echo
echo "SVT-Proton is now $tag plus our changes, with wine at SVT-wine ${wine_tip:0:12}."
if ((push)); then
    git -C "$SVT_WINE_DIR" push --force-with-lease origin "$SVT_BRANCH"
    git -C "$SVT_ROOT" push --force-with-lease origin "$SVT_BRANCH"
else
    echo "Push SVT-wine first, then SVT-Proton (a build needs the wine commit on GitHub):"
    echo "  git -C '$SVT_WINE_DIR' push --force-with-lease origin $SVT_BRANCH"
    echo "  git -C '$SVT_ROOT' push --force-with-lease origin $SVT_BRANCH"
    echo "Then: svt/build.sh, svt/package.sh, svt/release.sh"
fi
