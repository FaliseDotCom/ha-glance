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
# The refusals the test caused on purpose.
apparmor_expected=0

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

# Succeeds when the Docker host can confine containers with AppArmor.
apparmor_supported()
{
  docker info --format '{{json .SecurityOptions}}' | grep -q 'name=apparmor'
}

# Prints the path of the app's profile, renamed for this test the way the
# Supervisor renames it to the app's slug.
apparmor_profile_file()
{
  echo "${TMPDIR:-/tmp}/$APPARMOR_PROFILE.apparmor"
}

load_apparmor()
{
  if ! apparmor_supported
  then
    # CI is where the profile is tested, so there a skip is an error.
    [ "${CI:-}" != true ] || fatal "The CI host does not support AppArmor, so the profile cannot be tested."
    echo "skip AppArmor: the Docker host does not support it; CI tests the profile"
    return
  fi

  # A host with AppArmor must test the profile, so a missing loader is an
  # error rather than a reason to run the app unconfined.
  command -v apparmor_parser > /dev/null \
    || fatal "The Docker host supports AppArmor, but apparmor_parser is not installed to load the profile."

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

# Prints what the kernel logged as refused by the test's profile so far, or
# nothing when it refused nothing. Fails when the kernel log cannot be read,
# so a check never passes without having seen the log.
apparmor_denials()
{
  local log
  log=$(as_root dmesg) || fatal "The kernel log cannot be read to check what AppArmor refused."

  # grep exits 1 when nothing matches, which is the good outcome here; any
  # other failure is an error.
  grep 'apparmor="DENIED"' <<< "$log" | grep -F "profile=\"$APPARMOR_PROFILE\"" || [ "$?" -eq 1 ]
}

# Prints the number of lines in $1, 0 when it is empty.
line_count()
{
  if [ -z "$1" ]
  then
    echo 0
    return
  fi

  wc -l <<< "$1"
}

# Fails with the refusals given, when there are any.
fail_on_denials()
{
  if [ -n "$1" ]
  then
    echo "$1" >&2
    fail "The AppArmor profile refused the access above $2."
  fi
}

# Checks that the profile confines the app without getting in its way: it is
# applied, it refused nothing on the path above, including refusals the path
# did not notice, and a process in it cannot start a program the profile does
# not list. That last check is refused on purpose, so it comes after the first.
# Docker applies the profile as it starts a docker exec command, so that
# command itself always runs; the check is what it can start in turn.
check_apparmor()
{
  if [ "$apparmor" = false ]
  then
    return
  fi

  local applied
  applied=$(docker inspect --format '{{.AppArmorProfile}}' "$CONTAINER")
  [ "$applied" = "$APPARMOR_PROFILE" ] || fail "The app runs under AppArmor profile '$applied' instead of $APPARMOR_PROFILE."
  echo "ok   AppArmor profile applied"

  local denials
  denials=$(apparmor_denials) || fail "AppArmor's refusals could not be read."
  fail_on_denials "$denials" "while the app ran"
  echo "ok   AppArmor refused nothing while the app ran"

  if docker exec "$CONTAINER" node -e 'require("child_process").execFileSync("sh", [ "-c", "true" ])' > /dev/null 2>&1
  then
    fail "The AppArmor profile let the app start a shell."
  fi
  denials=$(apparmor_denials) || fail "AppArmor's refusals could not be read."
  apparmor_expected=$(line_count "$denials")
  echo "ok   the app cannot start a shell"
}

# Fails when the profile refused anything while the app stopped.
check_apparmor_stop()
{
  if [ "$apparmor" = false ]
  then
    return
  fi

  local denials
  denials=$(apparmor_denials) || fail "AppArmor's refusals could not be read."
  fail_on_denials "$(tail -n +$(( apparmor_expected + 1 )) <<< "$denials")" "while the app stopped"
  echo "ok   AppArmor refused nothing while the app stopped"
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
  check_apparmor
  check_stop
  check_apparmor_stop
  echo "== smoke test passed"
}

main "$@"
