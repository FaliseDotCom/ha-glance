#!/usr/bin/env bash
# Builds the app image and runs it the way the Supervisor does, then checks
# the path every user takes: the editor answers, a dashboard started empty is
# saved, Glance serves it, the health check passes and the app stops cleanly.
#
# Usage: scripts/smoke-test.sh [image]
#   image  An image to test instead of building glance/.

set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly CONTAINER="glance-smoke-$$"
readonly DASHBOARD_PORT=18080
readonly EDITOR_PORT=18090
readonly EDITOR_URL="http://127.0.0.1:$EDITOR_PORT"
readonly DASHBOARD_URL="http://127.0.0.1:$DASHBOARD_PORT"
readonly WAIT_SECONDS=60
readonly STOP_SECONDS=10

# shellcheck disable=SC2329 # Invoked through the trap set in main.
cleanup()
{
  docker rm -f "$CONTAINER" > /dev/null 2>&1 || true
}

fail()
{
  echo "FAIL: $*" >&2
  echo "--- container log" >&2
  docker logs "$CONTAINER" >&2 2>&1 || true
  exit 1
}

# Waits until a command succeeds, or fails the test after WAIT_SECONDS.
wait_for()
{
  local what="$1"
  shift

  local waited=0
  until "$@" > /dev/null 2>&1
  do
    if [ "$waited" -ge "$WAIT_SECONDS" ]
    then
      fail "$what did not happen within $WAIT_SECONDS seconds."
    fi

    sleep 1
    waited=$(( waited + 1 ))
  done
  echo "ok   $what"
}

# Sends a change to the editor the way its own page does: JSON, with an Origin
# matching the host, which the editor requires for every change.
editor_post()
{
  curl -fsS -X POST "$EDITOR_URL$1" \
    -H "Origin: $EDITOR_URL" -H "Content-Type: application/json" -d "$2"
}

healthy()
{
  [ "$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER")" = healthy ]
}

check_glance_version()
{
  local expected header
  expected=$(dockerfile_arg GLANCE_VERSION)
  # Through sh -c, so Git Bash on Windows does not rewrite the container path.
  header=$(docker exec "$CONTAINER" sh -c 'head -n 1 /config/config/glance.yml')

  if [[ "$header" != *"for Glance $expected."* ]]
  then
    fail "glance.yml was written for another Glance than $expected: $header"
  fi
  echo "ok   glance.yml written for Glance $expected"
}

check_stop()
{
  local started stopped
  started=$(date +%s)
  docker stop --time "$STOP_SECONDS" "$CONTAINER" > /dev/null
  stopped=$(date +%s)

  if [ "$(( stopped - started ))" -ge "$STOP_SECONDS" ]
  then
    fail "The app did not stop within $STOP_SECONDS seconds."
  fi

  if ! docker logs "$CONTAINER" 2>&1 | grep -q '\[start\] stopping'
  then
    fail "The app was killed instead of stopping."
  fi
  echo "ok   stopped cleanly in $(( stopped - started )) s"
}

main()
{
  local image="${1:-}"

  if [ -z "$image" ]
  then
    image=local/glance-app
    docker build -t "$image" "$REPO_ROOT/glance"
  fi

  trap cleanup EXIT
  docker run -d --init --name "$CONTAINER" -e TZ=Europe/Amsterdam \
    -p "127.0.0.1:$DASHBOARD_PORT:8080" -p "127.0.0.1:$EDITOR_PORT:3000" "$image" > /dev/null

  wait_for "editor answers" curl -fsS "$EDITOR_URL/healthz"
  curl -fsS "$EDITOR_URL/healthz" | grep -q '"glanceBinaryPresent":true' || fail "The editor cannot find the Glance binary."
  echo "ok   Glance binary present"

  editor_post /api/start-empty '{"pageName":"Smoke test","layout":"small-full-small"}' > /dev/null || fail "Start empty was refused."
  editor_post /api/save '{}' | grep -q '"status":"saved"' || fail "Save was refused."
  echo "ok   dashboard started empty and saved"

  wait_for "Glance serves the dashboard" sh -c "curl -fsS '$DASHBOARD_URL/' | grep -q 'Smoke test'"
  check_glance_version
  wait_for "health check passes" healthy
  check_stop
  echo "== smoke test passed"
}

main "$@"
