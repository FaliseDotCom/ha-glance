#!/usr/bin/env bash
# Updates the pins in glance/Dockerfile to the newest releases the app may use,
# bumps the app version everywhere it appears, adds a changelog entry and
# builds the image. It never commits or pushes; the Update workflow does that.
#
#   - The editor: the newest Glance Editor release, with the Glance and Node
#     images it pins.
#   - Glance: the newest release in the same minor series as the editor's own
#     pin (v0.8.x for v0.8.6), never an older one, and never a new minor or
#     major version before the editor supports it.
#   - Go: the newest patch release of the Go version in Glance's go.mod, to
#     build Glance with.
#   - Node: the newest image of the editor's Node major version, to run on.
#   - GLANCE_GO_UPDATES: security updates of Glance's Go modules. An update is
#     dropped once Glance itself requires that version or a newer one; new ones
#     are added by hand when scripts/check-security.sh asks for them.
#
# Usage: scripts/update-glance.sh [options] [version]
#   version         Glance Editor version such as 1.3.0. Defaults to the latest release.
#   --no-build      Skip building the image.
#   --summary FILE  Write a Markdown summary of the update to FILE, for a pull request.

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly CHANGELOG="$REPO_ROOT/glance/CHANGELOG.md"
readonly README="$REPO_ROOT/README.md"
readonly EDITOR_RELEASES_URL="https://github.com/$EDITOR_REPO/releases/tag"
readonly GLANCE_RELEASES_URL="https://github.com/$GLANCE_REPO/releases/tag"
readonly EDITOR_RAW_URL="https://raw.githubusercontent.com/$EDITOR_REPO"
readonly GLANCE_RAW_URL="https://raw.githubusercontent.com/$GLANCE_REPO"
readonly GO_RELEASES_API="https://go.dev/dl/?mode=json&include=all"
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
# The pins this script manages, in the order they appear in the Dockerfile.
readonly PINS=( EDITOR_VERSION EDITOR_COMMIT EDITOR_GLANCE_VERSION EDITOR_GLANCE_COMMIT EDITOR_GLANCE_IMAGE
  EDITOR_NODE_IMAGE GLANCE_VERSION GLANCE_COMMIT GLANCE_GO_UPDATES GO_IMAGE NODE_IMAGE )

BUILD=1
SUMMARY_FILE=""
TARGET=""

parse_arguments()
{
  while [ "$#" -gt 0 ]
  do
    case "$1" in
      --no-build)
        BUILD=0
        ;;
      --summary)
        SUMMARY_FILE="${2:-}"
        [ -n "$SUMMARY_FILE" ] || fatal "--summary needs a file name."
        shift
        ;;
      -*)
        fatal "Unknown option $1."
        ;;
      *)
        TARGET="$1"
        ;;
    esac
    shift
  done
}

# Prints the newest stable release tag (vX.Y.Z, no test releases) of a GitHub
# repository matching a tag pattern. Reads tags with git, which has no API
# rate limit.
latest_tag()
{
  git ls-remote --tags --refs "https://github.com/$1.git" "refs/tags/$2" \
    | sed 's|.*refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -n 1
}

latest_editor_release()
{
  local tag
  tag=$(latest_tag "$EDITOR_REPO" 'v*')
  echo "${tag#v}"
}

# Prints the newest stable Glance release in the minor series of version $1.
latest_glance_patch()
{
  latest_tag "$GLANCE_REPO" "v$(minor_series "$1").*"
}

# Prints the newest stable Go release in the minor series of version $1, such
# as 1.27.3 for 1.27.1.
latest_go_patch()
{
  curl -fsSL "$GO_RELEASES_API" \
    | grep -oE "\"version\": *\"go$(minor_series "$1" | sed 's/\./\\./g')\.[0-9]+\"" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -V | tail -n 1
}

# Prints image:tag@digest for the current build of an image tag.
pinned_image()
{
  local digest
  digest=$(index_digest "$1")
  [ -n "$digest" ] || fatal "Image $1 not found."
  check_image "$1@$digest"
  echo "$1@$digest"
}

# Prints the value of NAME=value from text on standard input.
pin()
{
  sed -n "s|^$1=\(.*\)$|\1|p" | head -n 1
}

# Reads the commit and pins of editor release $1 into EDITOR_*.
read_editor_release()
{
  EDITOR_VERSION="$1"
  EDITOR_COMMIT=$(tag_commit "$EDITOR_REPO" "v$1")
  [ -n "$EDITOR_COMMIT" ] || fatal "Glance Editor has no release tag v$1."

  local pins
  pins=$(curl -fsSL "$EDITOR_RAW_URL/$EDITOR_COMMIT/glance.version") || fatal "Could not read glance.version of v$1."
  EDITOR_GLANCE_VERSION=$(pin GLANCE_VERSION <<< "$pins")
  EDITOR_GLANCE_COMMIT=$(pin GLANCE_COMMIT <<< "$pins")
  EDITOR_GLANCE_IMAGE=$(pin GLANCE_IMAGE <<< "$pins")
  EDITOR_NODE_IMAGE=$(curl -fsSL "$EDITOR_RAW_URL/$EDITOR_COMMIT/Dockerfile" | pin "ARG NODE_IMAGE")

  if [ -z "$EDITOR_GLANCE_VERSION" ] || [ -z "$EDITOR_GLANCE_COMMIT" ] || [ -z "$EDITOR_GLANCE_IMAGE" ] || [ -z "$EDITOR_NODE_IMAGE" ]
  then
    fatal "Could not read the pins of v$1; the editor's build files have changed. Update the Dockerfile by hand."
  fi
}

# Picks the newest Glance patch release, or the editor's own pin.
choose_glance()
{
  local latest
  latest=$(latest_glance_patch "$EDITOR_GLANCE_VERSION")

  if [ -z "$latest" ] || ! version_gt "$latest" "$EDITOR_GLANCE_VERSION"
  then
    GLANCE_VERSION="$EDITOR_GLANCE_VERSION"
    GLANCE_COMMIT="$EDITOR_GLANCE_COMMIT"
    return
  fi

  GLANCE_VERSION="$latest"
  GLANCE_COMMIT=$(tag_commit "$GLANCE_REPO" "$latest")
  [ -n "$GLANCE_COMMIT" ] || fatal "Glance has no tag $latest."
}

# Picks the Go image to build Glance with, from the Go version in its go.mod,
# and drops module updates that Glance's go.mod already covers.
choose_go()
{
  local go_mod go_version latest
  go_mod=$(curl -fsSL "$GLANCE_RAW_URL/$GLANCE_COMMIT/go.mod") || fatal "Could not read Glance's go.mod."
  go_version=$(sed -n 's/^go \([0-9.]*\)$/\1/p' <<< "$go_mod")
  latest=$(latest_go_patch "$go_version")
  [ -n "$latest" ] || fatal "No Go release found for Go $go_version."
  GO_IMAGE=$(pinned_image "golang:$latest-alpine")

  local update module wanted required kept=()
  for update in $GLANCE_GO_UPDATES
  do
    module="${update%@*}"
    wanted="${update#*@}"
    required=$(awk -v module="$module" '$1 == module || ($1 == "require" && $2 == module) { print $NF; exit }' <<< "$go_mod")
    if [ -n "$required" ] && ! version_gt "$wanted" "$required"
    then
      echo "Dropping $update: Glance $GLANCE_VERSION requires $module $required."
      continue
    fi

    kept+=( "$update" )
  done
  GLANCE_GO_UPDATES="${kept[*]}"
}

# Picks the newest image of the editor's Node major version, such as the
# current node:24-slim for node:24-slim@sha256:...
choose_node()
{
  NODE_IMAGE=$(pinned_image "${EDITOR_NODE_IMAGE%@*}")
}

# Prints the next app version: the editor version after an editor update,
# otherwise the current version with its fourth segment raised.
next_app_version()
{
  local current="$1"

  if [ "$EDITOR_VERSION" != "$OLD_EDITOR_VERSION" ]
  then
    echo "$EDITOR_VERSION"
    return
  fi

  if [[ "$current" =~ $VERSION_PATTERN ]]
  then
    echo "$current.1"
    return
  fi

  echo "${current%.*}.$(( ${current##*.} + 1 ))"
}

set_arg()
{
  sed -i "s|^ARG $1=.*\$|ARG $1=$2|" "$DOCKERFILE"
}

update_files()
{
  local app_version="$1"
  local name

  for name in "${PINS[@]}"
  do
    set_arg "$name" "${!name}"
  done

  sed -i "s|^version: \".*\"\$|version: \"$app_version\"|" "$CONFIG"
  sed -i -E "s/Glance Editor [0-9.]+\]/Glance Editor $EDITOR_VERSION]/; s/Glance_Editor-[0-9.]+-/Glance_Editor-$EDITOR_VERSION-/" "$README"
  sed -i -E "s/\[Glance v[0-9.]+\]/[Glance $GLANCE_VERSION]/; s/badge\/Glance-v[0-9.]+-/badge\/Glance-$GLANCE_VERSION-/" "$README"
}

# Prints the changelog bullets for this update.
changelog_bullets()
{
  if [ "$EDITOR_VERSION" != "$OLD_EDITOR_VERSION" ]
  then
    echo "- Glance Editor $EDITOR_VERSION. See the [Glance Editor $EDITOR_VERSION release notes]($EDITOR_RELEASES_URL/v$EDITOR_VERSION)."
  fi

  if [ "$GLANCE_VERSION" != "$OLD_GLANCE_VERSION" ]
  then
    if [ "$GLANCE_VERSION" = "$EDITOR_GLANCE_VERSION" ]
    then
      echo "- Glance $GLANCE_VERSION. See the [Glance $GLANCE_VERSION release notes]($GLANCE_RELEASES_URL/$GLANCE_VERSION)."
    else
      echo "- Glance $GLANCE_VERSION, a newer patch release than the $EDITOR_GLANCE_VERSION the editor was released"
      echo "  with. See the [Glance $GLANCE_VERSION release notes]($GLANCE_RELEASES_URL/$GLANCE_VERSION)."
    fi
  fi

  if [ "$GO_IMAGE" != "$OLD_GO_IMAGE" ] || [ "$GLANCE_GO_UPDATES" != "$OLD_GLANCE_GO_UPDATES" ]
  then
    echo "- Glance is built with Go $(sed -E 's/^golang:([0-9.]+)-.*/\1/' <<< "$GO_IMAGE") and the latest security updates of its Go modules."
  fi

  if [ "$NODE_IMAGE" != "$OLD_NODE_IMAGE" ]
  then
    echo "- Security updates for Node.js and the system packages the app runs on."
  fi
}

# Inserts the new entry above the first existing release heading.
add_changelog_entry()
{
  local app_version="$1"
  local bullets="$2"
  local entry="## $app_version"$'\n\n'"$bullets"$'\n'

  ENTRY="$entry" awk '!done && /^## / { printf "%s\n", ENVIRON[ "ENTRY" ]; done = 1 } { print }' "$CHANGELOG" > "$CHANGELOG.tmp"
  mv "$CHANGELOG.tmp" "$CHANGELOG"
}

write_summary()
{
  local app_version="$1"
  local bullets="$2"

  [ -n "$SUMMARY_FILE" ] || return 0

  {
    echo "Updates the app to $app_version."
    echo
    echo "$bullets"
    echo
    if [ "$EDITOR_COMMIT" != "$OLD_EDITOR_COMMIT" ]
    then
      echo "Compare the editor's \`Dockerfile\` and \`image/\` folder with the previous release, and copy changes"
      echo "to its final stage into \`glance/Dockerfile\`:"
      echo "https://github.com/$EDITOR_REPO/compare/$OLD_EDITOR_COMMIT...$EDITOR_COMMIT"
      echo
    fi

    if [ "$GLANCE_COMMIT" != "$OLD_GLANCE_COMMIT" ]
    then
      echo "Check Glance's \`Dockerfile\` for build changes to copy into the \`glance\` stage:"
      echo "https://github.com/$GLANCE_REPO/compare/$OLD_GLANCE_COMMIT...$GLANCE_COMMIT"
      echo

      local docs_diff
      docs_diff=$(glance_docs_diff "$OLD_GLANCE_COMMIT" "$GLANCE_COMMIT")
      if [ -z "$docs_diff" ]
      then
        echo "Glance's configuration reference did not change."
      else
        echo "<details><summary>Changes to Glance's configuration reference</summary>"
        echo
        echo '```diff'
        echo "$docs_diff"
        echo '```'
        echo
        echo "</details>"
      fi
      echo
    fi

    echo "CI on this branch runs the editor's own tests against this Glance, the security checks, and a smoke"
    echo "test of the image on amd64 and arm64."
  } > "$SUMMARY_FILE"
}

# Keeps the current value of every pin in OLD_<name>, and loads it into <name>.
read_current_pins()
{
  local name value
  for name in "${PINS[@]}"
  do
    value=$(dockerfile_arg "$name")
    printf -v "OLD_$name" '%s' "$value"
    printf -v "$name" '%s' "$value"
  done
}

pins_changed()
{
  local name old
  for name in "${PINS[@]}"
  do
    old="OLD_$name"
    if [ "${!name}" != "${!old}" ]
    then
      return 0
    fi
  done

  return 1
}

main()
{
  parse_arguments "$@"
  read_current_pins

  if [ -z "$TARGET" ]
  then
    TARGET=$(latest_editor_release)
  fi

  if ! [[ "$TARGET" =~ $VERSION_PATTERN ]]
  then
    fatal "'$TARGET' is not a Glance Editor version such as 1.3.0."
  fi

  if version_gt "$OLD_EDITOR_VERSION" "$TARGET"
  then
    fatal "Glance Editor $TARGET is older than the current $OLD_EDITOR_VERSION; downgrades are not supported."
  fi

  if [ "$TARGET" != "$OLD_EDITOR_VERSION" ]
  then
    read_editor_release "$TARGET"
  fi

  choose_glance
  if version_gt "$OLD_GLANCE_VERSION" "$GLANCE_VERSION"
  then
    fatal "Glance $GLANCE_VERSION is older than the current $OLD_GLANCE_VERSION; downgrades are not supported."
  fi

  choose_go
  choose_node

  if ! pins_changed
  then
    echo "Up to date: Glance Editor $EDITOR_VERSION, Glance $GLANCE_VERSION, $GO_IMAGE, $NODE_IMAGE."
    exit 0
  fi

  local app_version new_version bullets
  app_version=$(sed -n 's/^version: "\(.*\)"$/\1/p' "$CONFIG")
  new_version=$(next_app_version "$app_version")
  bullets=$(changelog_bullets)

  echo "Updating $app_version -> $new_version:"
  echo "$bullets"
  update_files "$new_version"
  add_changelog_entry "$new_version" "$bullets"
  write_summary "$new_version" "$bullets"

  if [ "$BUILD" -eq 1 ]
  then
    echo "Building the image to check it still builds..."
    docker build -t local/glance-app "$REPO_ROOT/glance"
  fi

  cat <<EOF

$new_version prepared. Next:

  1. Read the release notes linked in glance/CHANGELOG.md.
  2. Run the checks: scripts/check-glance.sh, scripts/check-security.sh and scripts/smoke-test.sh.
  3. Review the diff and release:

       git diff
       git commit -am "Update to $new_version"
       git tag $new_version
       git push && git push --tags
EOF
}

main "$@"
