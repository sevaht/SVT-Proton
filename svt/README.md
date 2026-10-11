# SVT-Proton

Valve's [Proton](https://github.com/ValveSoftware/Proton) release, unchanged except for a small number of
fixes, under the same version number. Choose **SVT-Proton** in Steam wherever you would choose Proton.

Version `11.0-2e` of SVT-Proton is Proton `11.0-2e` plus our changes; its `version` file says
`proton-11.0-2e`. The tool is named for the Proton **series** it follows, `SVT-Proton-11.0`, so the choice you
make for a game in Steam keeps working across updates (`11.0-2e` -> `11.0-2f`), and several series can be
installed side by side (`SVT-Proton-10.0`, `SVT-Proton-11.0`).

## What is different

| Change | Where | What it does |
| --- | --- | --- |
| Early desktop setup | [SVT-wine](https://github.com/sevaht/SVT-wine), `dlls/win32u/class.c` | For the programs named in `PROTON_SVT_EAGER_DESKTOP` (file names such as `H1Z1.exe`; several separated by `:`, as in `H1Z1.exe:Other.exe`), Wine does its one-time desktop/driver/window-class setup while `user32` initializes instead of lazily on the first window operation. ROTK's patch library, which the ROTK launcher's game files load into Z1 Battle Royale, suspends the game's main thread during start-up; landing inside the lazy setup made the game hang forever. Without the variable nothing changes. |
| Version string | `Makefile.in` | The `version` file reports the nearest upstream release tag, not `<tag>-<commits>-g<hash>`. |
| Wine source | `.gitmodules` | The `wine` submodule is `../SVT-wine`. |

## Install

Download `SVT-Proton-<version>-x86_64.tar.xz` and `SHA256SUMS.txt` from the
[releases](https://github.com/sevaht/SVT-Proton/releases) page, then:

```
sha256sum --check SHA256SUMS.txt
mkdir -p ~/.local/share/Steam/compatibilitytools.d
tar -xJf SVT-Proton-<version>-x86_64.tar.xz -C ~/.local/share/Steam/compatibilitytools.d
```

Restart Steam, then pick **SVT-Proton-<series>** (for example `SVT-Proton-11.0`) under the game's Properties > Compatibility. A new Proton upgrades
the game's prefix, which Proton cannot undo; back it up first if that matters.

## Branches

Both repositories keep our work for each Proton series on a branch named `svt-<series>` (`svt-11.0`,
`svt-10.0`, ...). The default branch on GitHub should be the newest series.

- **SVT-wine** `svt-<series>`: the Wine commit the series' current release pins, plus our Wine commits.
- **SVT-Proton** `svt-<series>`: the series' current upstream release tag, plus our commits, plus one last commit,
  `svt: point wine at ...`, which sets the `wine` submodule to the SVT-wine tip and records the base in
  `svt/UPSTREAM` (including `SERIES`).

Valve's own branches (`proton_11.0`, ...) and tags are never committed to. Within a series we follow
**releases** (tags), not branch tips, and only the current release of each series is maintained. The scripts work
on whichever `svt-<series>` branch is checked out.

## Maintaining it

All of it runs only when you run it. One-time setup:

```
git -C SVT-wine   remote add upstream https://github.com/ValveSoftware/wine.git     # svt/update.sh does this too
git -C SVT-Proton remote add upstream https://github.com/ValveSoftware/Proton.git
```

and make `svt-11.0` the default branch of both repositories on GitHub. The scripts expect SVT-wine next to
SVT-Proton (`SVT_WINE_DIR` and the others in `svt/config.sh` override the paths).

**A new upstream release came out**

```
svt/update.sh --check     # is there one?
svt/update.sh             # replay our commits onto it, in SVT-wine and then SVT-Proton
svt/update.sh --push      # same, and push both (or push yourself, SVT-wine first)
```

It replays our commits onto the new tag, then rebuilds the pointer commit from scratch (never rebased:
Valve moves that pointer in almost every release). A conflict stops git in place; resolve it, `git rebase
--continue` (SVT-wine first, then SVT-Proton), then `svt/update.sh <new tag> --refresh`.

**Add another Proton series** (say Proton 10, while keeping 11)

```
svt/update.sh --new-series 10.0
```

From the current branch (`svt-11.0`) it creates `svt-10.0` in both repositories, replays our commits onto the
newest `proton-10.0-*` release and its Wine commit, and builds the pointer commit. If a commit does not apply
to that series' Wine it stops like any other conflict. Then build and release as usual: the tool is named
`SVT-Proton-10.0`, its releases `svt-10.0-<release>`. Series are independent after that: `svt/update.sh` on
each branch follows its own releases.

**You changed the Wine patch** (commit it in SVT-wine on `svt`): `svt/update.sh --refresh` re-points `wine` at
the new tip.

**Cut a release** (from a committed and pushed state):

```
svt/build.sh              # build in $SVT_BUILD_DIR (Docker; hours the first time)
# test it: pick it for a game and run it
svt/package.sh            # SVT-Proton-<version>-x86_64.tar.xz in $SVT_RELEASE_DIR
svt/release.sh            # GitHub release svt-<version>, with SHA256SUMS.txt
```

A rebuild of the same upstream version (a changed patch) takes `--rev 2` on `package.sh` and `release.sh`:
`SVT-Proton-11.0-2e-r2-x86_64.tar.xz`, tag `svt-11.0-2e-r2`.

## Release conventions (for tools that fetch it)

- Repository `sevaht/SVT-Proton`, tag `svt-<upstream version>[-r<N>]` (`svt-11.0-2e`, `svt-10.0-4b`); our tags
  never reuse Valve's `proton-*`. The series is the part of the version before the last `-`.
- Assets: `SVT-Proton-<version>[-r<N>]-<arch>.tar.xz` and `SHA256SUMS.txt` (`sha256sum --check` format). The
  architecture is in the name so a release can later carry more than one (only `x86_64` exists today, the same
  as Valve's Proton for desktop Linux); the tag is the same for all of them.
- The archive has a single top-level folder named for the tool, `SVT-Proton-<series>/`: extracting it into
  `compatibilitytools.d` is the whole installation. `compatibilitytool.vdf` inside names the tool the same.
- The upstream version is in the archive's `version` file, second field (`proton-11.0-2e`).
- To follow a series, take the newest release whose tag starts `svt-<series>-`.
