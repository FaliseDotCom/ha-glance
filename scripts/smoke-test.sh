#!/usr/bin/env bash
# Builds the app image and runs it the way the Supervisor does, then checks
# the path every user takes: the editor answers, a dashboard started empty is
# saved, Glance serves it, the health check passes and the app stops cleanly.
#
# When the Docker host has AppArmor (Linux, as in CI), the app runs under its
# own profile, glance/apparmor.txt, as the Supervisor runs it, and the test
# fails on anything the profile refused. Loading the profile needs root, so
# the script uses sudo when it is not run as root.
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
readonly APPARMOR_FILE="$REPO_ROOT/glance/apparmor.txt"
readonly APPARMOR_PROFILE="glance-smoke-$$"

apparmor=false

# shellcheck disable=SC2329 # Invoked through the trap set in main.
cleanup()
{
  docker rm -f "$CONTAINER" > /dev/null 2>&1 || true

  if [ "$apparmor" = true ]
  then
    as_root apparmor_parser -R "$(apparmor_profile_file)" > /dev/null 2>&1 || true
  fi
}

# Runs a command as root, through sudo unless the script already runs as root.
as_root()
{
  if [ "$(id -u)" -eq 0 ]
  then
    "$@"
    return
  fi

  sudo -n "$@"
}

# Succeeds when the Docker host can confine containers with AppArmor, and this
# script can load a profile there.
apparmor_available()
{
  docker info --format '{{json .SecurityOptions}}' | grep -q 'name=apparmor' \
    && command -v apparmor_parser > /dev/null
}

# Prints the path of the app's profile, renamed for this test the way the
# Supervisor renames it to the app's slug.
apparmor_profile_file()
{
  echo "${TMPDIR:-/tmp}/$APPARMOR_PROFILE.apparmor"
}

load_apparmor()
{
  if ! apparmor_available
  then
    echo "skip AppArmor: the Docker host does not support it; CI tests the profile"
    return
  fi

  local file
  file=$(apparmor_profile_file)
  sed "s/^profile [^ ]*/profile $APPARMOR_PROFILE/" "$APPARMOR_FILE" > "$file"
  as_root apparmor_parser -r -W "$file" || fatal "The AppArmor profile does not load."
  apparmor=true
  echo "ok   AppArmor profile loaded"
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
  # Through Node, the only program the AppArmor profile lets run, and with the
  # path inside the script, so Git Bash on Windows does not rewrite it.
  header=$(docker exec "$CONTAINER" node -e \
    'process.stdout.write(require("fs").readFileSync("/config/config/glance.yml", "utf8").split("\n")[0])')

  if [[ "$header" != *"for Glance $expected."* ]]
  then
    fail "glance.yml was written for another Glance than $expected: $header"
  fi
  echo "ok   glance.yml written for Glance $expected"
}

# Checks that the profile confines the app: it is applied, and a process in it
# cannot start a program the profile does not list. Docker applies the profile
# as it starts a docker exec command, so that command itself always runs; the
# check is what it can start in turn.
check_apparmor_applied()
{
  if [ "$apparmor" = false ]
  then
    return
  fi

  local applied
  applied=$(docker inspect --format '{{.AppArmorProfile}}' "$CONTAINER")
  [ "$applied" = "$APPARMOR_PROFILE" ] || fail "The app runs under AppArmor profile '$applied' instead of $APPARMOR_PROFILE."

  if docker exec "$CONTAINER" node -e 'require("child_process").execFileSync("sh", [ "-c", "true" ])' > /dev/null 2>&1
  then
    fail "The AppArmor profile let the app start a shell."
  fi
  echo "ok   AppArmor profile applied"
}

# Fails when the kernel logged anything the profile refused during the test,
# including refusals the path above did not notice.
check_apparmor_denials()
{
  if [ "$apparmor" = false ]
  then
    return
  fi

  local denials
  denials=$(as_root dmesg | grep 'apparmor="DENIED"' | grep -F "profile=\"$APPARMOR_PROFILE\"" || true)
  if [ -n "$denials" ]
  then
    echo "$denials" >&2
    fail "The AppArmor profile refused the access above."
  fi
  echo "ok   AppArmor refused nothing"
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
  load_apparmor

  local security=()
  if [ "$apparmor" = true ]
  then
    security=( --security-opt "apparmor=$APPARMOR_PROFILE" )
  fi

  docker run -d --init --name "$CONTAINER" -e TZ=Europe/Amsterdam "${security[@]}" \
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
  check_apparmor_applied
  check_stop
  check_apparmor_denials
  echo "== smoke test passed"
}

main "$@"
