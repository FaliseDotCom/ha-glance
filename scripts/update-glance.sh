#!/usr/bin/env bash
# Updates the app to a new Glance Editor release: reads the commit and the
# Glance and Node images that release pins, writes them into the Dockerfile,
# bumps the version everywhere it appears, adds a changelog entry and builds
# the image. It never commits or pushes; it prints the git commands to run
# afterwards.
#
# Usage: scripts/update-glance.sh [version]
#   version  Glance Editor version such as 1.3.0. Defaults to the latest release.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
readonly DOCKERFILE="$REPO_ROOT/glance/Dockerfile"
readonly CONFIG="$REPO_ROOT/glance/config.yaml"
readonly CHANGELOG="$REPO_ROOT/glance/CHANGELOG.md"
readonly README="$REPO_ROOT/README.md"
readonly EDITOR_REPO=gcarstoiu/glance-ui
readonly EDITOR_GIT="https://github.com/$EDITOR_REPO.git"
readonly RELEASES_API="https://api.github.com/repos/$EDITOR_REPO/releases/latest"
readonly RELEASES_URL="https://github.com/$EDITOR_REPO/releases/tag"
readonly RAW_URL="https://raw.githubusercontent.com/$EDITOR_REPO"
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

fatal()
{
  echo "ERROR: $*" >&2
  exit 1
}

latest_release()
{
  curl -fsSL "$RELEASES_API" | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n 1
}

# Prints the value of one ARG in the app's Dockerfile.
dockerfile_arg()
{
  sed -n "s|^ARG $1=\(.*\)$|\1|p" "$DOCKERFILE"
}

# Prints the commit a release tag points to. An annotated tag is listed twice;
# its peeled (^{}) line, which names the commit itself, is listed last.
tag_commit()
{
  git ls-remote "$EDITOR_GIT" "refs/tags/v$1" "refs/tags/v$1^{}" | tail -n 1 | cut -f 1
}

# Prints the value of NAME=value from text on standard input.
pin()
{
  sed -n "s|^$1=\(.*\)$|\1|p" | head -n 1
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

set_arg()
{
  sed -i "s|^ARG $1=.*\$|ARG $1=$2|" "$DOCKERFILE"
}

update_files()
{
  local old="$1"
  local new="$2"

  set_arg EDITOR_VERSION "$new"
  set_arg EDITOR_COMMIT "$COMMIT"
  set_arg GLANCE_VERSION "$GLANCE_VERSION"
  set_arg GLANCE_COMMIT "$GLANCE_COMMIT"
  set_arg GLANCE_IMAGE "$GLANCE_IMAGE"
  set_arg NODE_IMAGE "$NODE_IMAGE"
  sed -i "s|^version: \".*\"\$|version: \"$new\"|" "$CONFIG"
  sed -i "s|Glance Editor $old|Glance Editor $new|; s|Glance_Editor-$old-|Glance_Editor-$new-|" "$README"
  sed -i "s|Glance $OLD_GLANCE_VERSION|Glance $GLANCE_VERSION|; s|Glance-$OLD_GLANCE_VERSION-|Glance-$GLANCE_VERSION-|" "$README"
}

# Inserts the new entry above the first existing release heading.
add_changelog_entry()
{
  local new="$1"
  local entry="## $new\n\n- Glance Editor $new with Glance $GLANCE_VERSION. See the [Glance Editor $new release notes]($RELEASES_URL/v$new).\n"

  awk -v entry="$entry" '!done && /^## / { printf "%s\n", entry; done = 1 } { print }' "$CHANGELOG" > "$CHANGELOG.tmp"
  mv "$CHANGELOG.tmp" "$CHANGELOG"
}

main()
{
  local new="${1:-}"

  if [ -z "$new" ]
  then
    new=$(latest_release)
  fi

  if ! [[ "$new" =~ $VERSION_PATTERN ]]
  then
    fatal "'$new' is not a Glance Editor version such as 1.3.0."
  fi

  local old
  old=$(dockerfile_arg EDITOR_VERSION)

  if [ "$old" = "$new" ]
  then
    echo "Already on Glance Editor $new."
    exit 0
  fi

  if [ "$(printf '%s\n' "$old" "$new" | sort -V | tail -n 1)" = "$old" ]
  then
    fatal "Glance Editor $new is older than the current $old; downgrades are not supported."
  fi

  local old_commit
  old_commit=$(dockerfile_arg EDITOR_COMMIT)
  OLD_GLANCE_VERSION=$(dockerfile_arg GLANCE_VERSION)

  COMMIT=$(tag_commit "$new")
  if [ -z "$COMMIT" ]
  then
    fatal "Glance Editor has no release tag v$new."
  fi

  echo "Updating Glance Editor $old -> $new (commit $COMMIT)"

  local pins
  pins=$(curl -fsSL "$RAW_URL/$COMMIT/glance.version") || fatal "Could not read glance.version of v$new."
  GLANCE_VERSION=$(pin GLANCE_VERSION <<< "$pins")
  GLANCE_COMMIT=$(pin GLANCE_COMMIT <<< "$pins")
  GLANCE_IMAGE=$(pin GLANCE_IMAGE <<< "$pins")
  NODE_IMAGE=$(curl -fsSL "$RAW_URL/$COMMIT/Dockerfile" | pin "ARG NODE_IMAGE")

  if [ -z "$GLANCE_VERSION" ] || [ -z "$GLANCE_COMMIT" ] || [ -z "$GLANCE_IMAGE" ] || [ -z "$NODE_IMAGE" ]
  then
    fatal "Could not read the pinned images of v$new; the editor's build files have changed. Update the Dockerfile by hand."
  fi

  check_image "$GLANCE_IMAGE"
  check_image "$NODE_IMAGE"
  update_files "$old" "$new"
  add_changelog_entry "$new"

  echo "Building the image to check it still builds..."
  docker build -t local/glance-app "$REPO_ROOT/glance"

  cat <<EOF

Glance Editor $old -> $new prepared (Glance $OLD_GLANCE_VERSION -> $GLANCE_VERSION). Next:

  1. Read the release notes: $RELEASES_URL/v$new
  2. Compare the editor's Dockerfile and image/ folder with the previous release, and copy
     changes to its final stage into glance/Dockerfile:
       https://github.com/$EDITOR_REPO/compare/$old_commit...$COMMIT
  3. Test an upgrade on existing data (see .docs/development.md).
  4. Review the diff and release:

       git diff
       git commit -am "Update Glance Editor to $new"
       git tag $new
       git push && git push --tags
EOF
}

main "$@"
