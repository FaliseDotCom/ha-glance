# shellcheck shell=bash
# shellcheck disable=SC2034 # The constants are used by the scripts that source this file.
# Helpers shared by the scripts in this folder. Source this file; do not run it.

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
readonly DOCKERFILE="$REPO_ROOT/glance/Dockerfile"
readonly CONFIG="$REPO_ROOT/glance/config.yaml"
readonly EDITOR_REPO=gcarstoiu/glance-ui
readonly GLANCE_REPO=glanceapp/glance

fatal()
{
  echo "ERROR: $*" >&2
  exit 1
}

# Prints the value of one top-level ARG in the app's Dockerfile.
dockerfile_arg()
{
  sed -n "s|^ARG $1=\(.*\)$|\1|p" "$DOCKERFILE"
}

# Prints the commit a tag of a GitHub repository points to. An annotated tag
# is listed twice; its peeled (^{}) line, which names the commit, comes last.
tag_commit()
{
  local repo="$1"
  local tag="$2"

  git ls-remote "https://github.com/$repo.git" "refs/tags/$tag" "refs/tags/$tag^{}" | tail -n 1 | cut -f 1
}

# Succeeds when version $1 is newer than version $2. A leading "v" is ignored.
version_gt()
{
  [ "${1#v}" != "${2#v}" ] && [ "$(printf '%s\n' "${1#v}" "${2#v}" | sort -V | tail -n 1)" = "${1#v}" ]
}

# Prints the major.minor part of a version such as v0.8.6.
minor_series()
{
  local version="${1#v}"

  echo "${version%.*}"
}

# The Supervisor architectures amd64 and aarch64 need linux/amd64 and linux/arm64.
check_image()
{
  local manifest
  manifest=$(docker buildx imagetools inspect "$1") || fatal "Image $1 not found."

  local platform
  for platform in linux/amd64 linux/arm64
  do
    if ! grep -q "Platform: *$platform" <<< "$manifest"
    then
      fatal "Image $1 has no $platform build."
    fi
  done
}

# Prints the digest of an image's multi-architecture index.
index_digest()
{
  docker buildx imagetools inspect "$1" | sed -n 's/^Digest: *//p' | head -n 1
}

# Prints a unified diff of Glance's configuration reference between two
# commits, or nothing when it did not change.
glance_docs_diff()
{
  local from="$1"
  local to="$2"
  local raw="https://raw.githubusercontent.com/$GLANCE_REPO"
  local old new

  old=$(curl -fsSL "$raw/$from/docs/configuration.md") || fatal "Could not read Glance's configuration reference at $from."
  new=$(curl -fsSL "$raw/$to/docs/configuration.md") || fatal "Could not read Glance's configuration reference at $to."
  diff -u --label "configuration.md@${from:0:7}" --label "configuration.md@${to:0:7}" \
    <(echo "$old") <(echo "$new") || true
}
