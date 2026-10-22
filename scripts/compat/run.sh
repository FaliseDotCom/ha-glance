#!/usr/bin/env bash
# Runs the editor's own checks against the Glance in this image. The command
# of the compatibility image (scripts/compat/Dockerfile).

set -euo pipefail

cd /src

readonly SOURCE_DATA=packages/model/src/glance-source.generated.ts
# Tests left out, by name. "matches the pins" checks that the community widget
# snapshot records the Glance version of glance.version, which this image
# changes on purpose; the test after it validates every addable community
# widget with the app's Glance, which is the part that matters here.
readonly TEST_FILTER='^(?!.*matches the pins: community-widgets\.version and glance\.version)'

failures=0

# Prints a generated source data file without the Glance version and commit
# it names in its comments, which always differ between Glance versions.
strip_version()
{
  sed -E 's/glanceapp\/glance@[0-9a-f]+ \([^)]*\)/glanceapp\/glance@COMMIT (VERSION)/; s/Glance v[0-9.]+/Glance VERSION/g' "$1"
}

# Regenerates the editor's catalogue of widget types and themes from the
# Glance source, compares it with the one the editor was built with, and puts
# the editor's own file back.
check_source_data()
{
  local shipped
  shipped=$(mktemp)
  cp "$SOURCE_DATA" "$shipped"

  node scripts/glance-source-data.ts > /dev/null

  if ! diff -u <(strip_version "$shipped") <(strip_version "$SOURCE_DATA")
  then
    cp "$shipped" "$SOURCE_DATA"
    echo "Glance's widget types or themes differ from the editor's catalogue (diff above)." >&2
    exit 1
  fi

  cp "$shipped" "$SOURCE_DATA"
  echo "widget types and themes match the editor's catalogue"
}

# Runs config:validate on one fixture and reports whether it behaved as
# expected: "pass" fixtures must validate, "fail" fixtures must not.
check_fixture()
{
  local fixture="$1"
  local expect="$2"
  local work result

  work=$(mktemp -d)
  cp "$fixture" "$work/glance.yml"
  if glance --config "$work/glance.yml" config:validate > /dev/null 2>&1
  then
    result=pass
  else
    result=fail
  fi
  rm -rf "$work"

  if [ "$result" = "$expect" ]
  then
    echo "ok   $expect  $(basename "$fixture")"
    return
  fi

  echo "BAD  expected $expect, got $result: $(basename "$fixture")"
  failures=$(( failures + 1 ))
}

# The editor's fixtures: configurations Glance must accept or refuse. The
# placeholder fixture needs environment variables and secret files set up by
# the editor's Docker harness; the unit tests cover placeholders.
check_fixtures()
{
  local fixture

  for fixture in test/fixtures/valid/*.yml
  do
    if [ "$(basename "$fixture")" = placeholders.yml ]
    then
      continue
    fi

    check_fixture "$fixture" pass
  done

  for fixture in test/fixtures/invalid/*.yml
  do
    check_fixture "$fixture" fail
  done
}

main()
{
  echo "== Glance $(sed -n 's/^GLANCE_VERSION=//p' glance.version) against the editor's checks"

  echo "== widget types and themes (glance-source-data)"
  check_source_data

  echo "== unit and Glance tests (vitest)"
  npx vitest run --testNamePattern "$TEST_FILTER"

  echo "== fixtures (config:validate)"
  check_fixtures

  if [ "$failures" -gt 0 ]
  then
    echo "$failures fixture(s) did not behave as expected." >&2
    exit 1
  fi

  echo "== all checks passed"
}

main "$@"
