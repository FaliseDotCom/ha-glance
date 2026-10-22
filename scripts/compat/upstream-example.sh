#!/usr/bin/env bash
# Stands in for the editor's test/upstream-example.sh inside the compatibility
# image, which has no Docker or curl. Validates Glance's own example
# configuration, downloaded when the image was built, with the app's Glance.
#
# Usage: test/upstream-example.sh [--print-path]

set -euo pipefail

readonly EXAMPLE=/opt/upstream-example/glance.yml

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$EXAMPLE" "$work/glance.yml"

if ! glance --config "$work/glance.yml" config:validate > /dev/null
then
  echo "Glance's example configuration does not pass config:validate." >&2
  exit 1
fi

if [ "${1:-}" = "--print-path" ]
then
  echo "$EXAMPLE"
fi
