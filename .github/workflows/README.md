# Continuous integration

| Workflow | Runs on | What it is for |
|---|---|---|
| `validate.yml` | GitHub-hosted, minutes | Manifests, configuration files and scripts parse; every pinned project and revision still exists; the patches in `libcamera/patches/` and `patches/` still apply to the revisions the manifest pins. This is what breaks when an upstream moves. |
| `kernel.yml` | GitHub-hosted (arm64), ~30 min | Builds `Image.gz`, the modules and the gtowifi DTB from the pinned kernel branch with the configuration layering of `BoardConfig.mk`, and checks that every module in `modprobe/modules.load.*` was built. Uses the distribution's GCC: it proves source and configuration, not the binary of a release, which the Android build makes with AOSP's clang. |
| `images.yml` | **self-hosted**, hours | The full image set. Needs about 250 GB and does not fit on a hosted runner. |
| `release.yml` | GitHub-hosted | Publishes the images of an `images.yml` run as a release, with the checksums that build computed. |

## Caches

- `kernel.yml` keeps its ccache (about 1 GB) in GitHub's cache, keyed on the kernel revision.
- `validate.yml` keeps the pristine libcamera clone, keyed on the pinned revision.
- `images.yml` keeps the LineageOS tree, its ccache (30 GB) and the output on the runner's own disk,
  outside the workspace, so a device-tree change is an incremental build of a few minutes.
  GitHub's cache is capped at 10 GB per repository and cannot hold any of that.

## A runner for `images.yml`

Any machine or cloud instance with at least 300 GB free, 16 GB RAM and the LineageOS build
dependencies, registered as a repository runner with the labels `self-hosted` and `lineage-build`,
and `repo` and `ccache` on its PATH. `LINEAGE_HOME` (a repository variable, default `/mnt/lineage`)
is where the tree, the ccache and the output live between runs. Do not register a machine you do
not own.

## Releases and accounts

`release.yml` authenticates with `GITHUB_TOKEN`, which belongs to this repository. Releases are
created by the repository, not by a maintainer's personal account, and nobody has to have a
command-line tool logged in anywhere.
