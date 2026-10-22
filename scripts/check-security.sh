#!/usr/bin/env bash
# Looks for known vulnerabilities that a fix exists for, in everything the app
# runs, and fails when it finds any:
#
#   - Glance's Go code and modules, as the app builds them (govulncheck: only
#     vulnerabilities Glance's code can actually reach).
#   - The editor's runtime dependencies (npm audit), which its build bundles.
#   - The app image: Debian packages, the Go binary and anything else Trivy
#     recognises, at high or critical severity.
#
# Vulnerabilities without a released fix are reported by Trivy's own output
# elsewhere but do not fail this check; there is nothing to update to.
#
# Usage: scripts/check-security.sh [image]
#   image  An app image to scan instead of building glance/.

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly GLANCE_BUILD_IMAGE=local/glance-app-glance
readonly EDITOR_BUILD_IMAGE=local/glance-app-build
readonly GOVULNCHECK=golang.org/x/vuln/cmd/govulncheck@v1.9.0
readonly TRIVY_IMAGE=aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c

failures=0

# Runs one check and counts it as failed when it does not succeed.
check()
{
  local name="$1"
  shift

  echo "== $name"
  if "$@"
  then
    echo "ok   $name"
    return
  fi

  echo "FAIL $name" >&2
  failures=$(( failures + 1 ))
}

govulncheck_glance()
{
  docker run --rm "$GLANCE_BUILD_IMAGE" sh -c "GOTOOLCHAIN=local go run $GOVULNCHECK ./..."
}

audit_editor()
{
  docker run --rm "$EDITOR_BUILD_IMAGE" npm audit --omit=dev --audit-level=high
}

scan_image()
{
  # The doubled slash keeps Git Bash on Windows from rewriting the socket path;
  # Linux reads it as the same path.
  docker run --rm -v //var/run/docker.sock:/var/run/docker.sock "$TRIVY_IMAGE" image \
    --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$1"
}

main()
{
  local image="${1:-}"

  docker build --target glance -t "$GLANCE_BUILD_IMAGE" "$REPO_ROOT/glance"
  docker build --target build -t "$EDITOR_BUILD_IMAGE" "$REPO_ROOT/glance"

  if [ -z "$image" ]
  then
    image=local/glance-app
    docker build -t "$image" "$REPO_ROOT/glance"
  fi

  check "Glance's Go code (govulncheck)" govulncheck_glance
  check "the editor's dependencies (npm audit)" audit_editor
  check "the app image (Trivy)" scan_image "$image"

  if [ "$failures" -gt 0 ]
  then
    fatal "$failures security check(s) found vulnerabilities with a fix available. See .docs/security.md."
  fi

  echo "== no known vulnerabilities with a fix available"
}

main "$@"
