#!/usr/bin/env bash
# Checks that the Glance the app runs works with the Glance Editor it ships,
# without changing the editor: runs the editor's own checks against that
# Glance, inside a throwaway image (scripts/compat/).
#
#   - The widget types and themes in Glance's source must match the editor's
#     catalogue, so the editor offers every widget and theme Glance has.
#   - The editor's unit and Glance tests, community widgets included, must pass
#     with the app's Glance binary.
#   - The editor's fixtures must still be accepted or refused by Glance.
#
# When the app runs a newer Glance than the editor's own pin, it also prints
# what changed in Glance's configuration reference, for a person to review.
#
# Usage: scripts/check-glance.sh [--summary FILE]
#   --summary FILE  Append a Markdown report to FILE, such as $GITHUB_STEP_SUMMARY.

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly GLANCE_BUILD_IMAGE=local/glance-app-glance
readonly BUILD_IMAGE=local/glance-app-build
readonly COMPAT_IMAGE=local/glance-compat

SUMMARY_FILE=""

parse_arguments()
{
  while [ "$#" -gt 0 ]
  do
    case "$1" in
      --summary)
        SUMMARY_FILE="${2:-}"
        [ -n "$SUMMARY_FILE" ] || fatal "--summary needs a file name."
        shift
        ;;
      *)
        fatal "Unknown argument $1."
        ;;
    esac
    shift
  done
}

summary()
{
  if [ -n "$SUMMARY_FILE" ]
  then
    echo "$*" >> "$SUMMARY_FILE"
  fi
}

# The app may run ahead of the editor only within the editor's minor series.
check_policy()
{
  if [ "$(minor_series "$GLANCE_VERSION")" != "$(minor_series "$EDITOR_GLANCE_VERSION")" ]
  then
    fatal "Glance $GLANCE_VERSION is not in the $EDITOR_GLANCE_VERSION series the editor supports."
  fi

  if version_gt "$EDITOR_GLANCE_VERSION" "$GLANCE_VERSION"
  then
    fatal "Glance $GLANCE_VERSION is older than the $EDITOR_GLANCE_VERSION the editor pins."
  fi
}

run_editor_checks()
{
  echo "Building Glance and the editor's build stage..."
  docker build --target glance -t "$GLANCE_BUILD_IMAGE" "$REPO_ROOT/glance"
  docker build --target build -t "$BUILD_IMAGE" "$REPO_ROOT/glance"

  echo "Building the compatibility image with Glance $GLANCE_VERSION..."
  docker build -t "$COMPAT_IMAGE" \
    --build-arg "BASE=$BUILD_IMAGE" \
    --build-arg "GLANCE_BUILD=$GLANCE_BUILD_IMAGE" \
    --build-arg "GLANCE_VERSION=$GLANCE_VERSION" \
    --build-arg "GLANCE_COMMIT=$GLANCE_COMMIT" \
    "$REPO_ROOT/scripts/compat"

  docker run --rm "$COMPAT_IMAGE"
}

report_docs_diff()
{
  if [ "$GLANCE_VERSION" = "$EDITOR_GLANCE_VERSION" ]
  then
    return
  fi

  local docs_diff
  docs_diff=$(glance_docs_diff "$(dockerfile_arg EDITOR_GLANCE_COMMIT)" "$GLANCE_COMMIT")

  if [ -z "$docs_diff" ]
  then
    echo "Glance's configuration reference is the same in $EDITOR_GLANCE_VERSION and $GLANCE_VERSION."
    summary "Glance's configuration reference is the same in $EDITOR_GLANCE_VERSION and $GLANCE_VERSION."
    return
  fi

  echo "Glance's configuration reference changed between $EDITOR_GLANCE_VERSION and $GLANCE_VERSION; review:"
  echo "$docs_diff"
  summary "<details><summary>Glance's configuration reference changed between $EDITOR_GLANCE_VERSION and $GLANCE_VERSION</summary>"
  summary ""
  summary '```diff'
  summary "$docs_diff"
  summary '```'
  summary ""
  summary "</details>"
}

main()
{
  parse_arguments "$@"

  EDITOR_GLANCE_VERSION=$(dockerfile_arg EDITOR_GLANCE_VERSION)
  GLANCE_VERSION=$(dockerfile_arg GLANCE_VERSION)
  GLANCE_COMMIT=$(dockerfile_arg GLANCE_COMMIT)

  echo "Glance Editor $(dockerfile_arg EDITOR_VERSION) (pins Glance $EDITOR_GLANCE_VERSION), app runs Glance $GLANCE_VERSION"
  check_policy
  run_editor_checks
  summary "### Glance $GLANCE_VERSION passes the checks of Glance Editor $(dockerfile_arg EDITOR_VERSION)"
  summary ""
  report_docs_diff
}

main "$@"
