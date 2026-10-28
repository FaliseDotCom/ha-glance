---
repo: gcarstoiu/glance-ui
branch: fix/editor-host
title: fix(image): pass HOST to the editor so it can listen on IPv6
patch: 2026-10-28-editor-host-ipv6.patch
url: https://github.com/gcarstoiu/glance-ui/pull/41
---

## Summary

On a Docker network with IPv6, the editor can't be opened over IPv6. Its published port accepts the connection, then the browser gets an empty reply (`ERR_EMPTY_RESPONSE`). Browsers don't fall back to IPv4 when that happens, so a host name that resolves to an IPv6 address first, such as an mDNS `.local` name, never shows the editor. Opening it by IPv4 address works.

The cause: adapter-node listens on `HOST`, `0.0.0.0` by default, which is IPv4 only. `image/start.ts` passes only the variables in `PASS_TO_EDITOR` to the editor, and `HOST` isn't on that list, so it can't be changed. Docker forwards the IPv6 connection to the container's IPv6 address, where nothing listens.

This PR adds `HOST` to `PASS_TO_EDITOR` and documents it in the README's settings table. With `HOST=::`, the editor listens on IPv4 and IPv6. Without `HOST`, nothing changes, so existing installs are unaffected. Glance itself is not affected: it listens on `:8080`, which already includes IPv6.

Found while packaging the editor as a Home Assistant app. The Supervisor puts apps on a Docker network with IPv6, and `homeassistant.local` resolves to IPv6 first.

## UX changes (required)

none

Approved ADR(s): none needed; this is an opt-in container setting with no change to the editor itself.

## Generated config impact

none

## Data model / migration impact

none

## Testing

- Tested: the v1.2.0 image's `start.ts` with only this change, mounted over `/app/image/start.ts`, on a user-defined Docker network created with `--ipv6`. A second container on that network requested `/healthz`:

  | Container | Over IPv4 | Over IPv6 |
  | --- | --- | --- |
  | Unchanged, no `HOST` | 200 | no connection |
  | This change, `HOST=::` | 200 | 200 |

  The log line changes from `Listening on http://0.0.0.0:3000` to `Listening on http://[::]:3000`. With `HOST=::` on the default bridge network (no IPv6), the editor starts and the image's health check passes over `127.0.0.1`. On the IPv6 network, Glance's dashboard port answered over IPv6 without any change.
- Not tested: `scripts/test.sh` and `test/all-in-one.sh` against a freshly built image of this branch. A host booted with IPv6 turned off in the kernel (`ipv6.disable=1`), where `HOST=::` would fail to listen; that's why this PR leaves the default as is.

## Release notes entry

- **The editor can listen on IPv6.** Set `HOST=::` when the container's network has IPv6; before, browsers that connected over IPv6 got an empty reply.

## Checklist

- [ ] CI is green (tests + Glance smoke test against the pinned version)
- [x] No access to the live Glance instance or its config was needed or used
- [ ] `docs/handoff.md` updated; any new UX decision is an ADR with status "proposed" listed under "Needs user decision" (left to the maintainers, as the handoff records their own sessions)
- [ ] `docs/lessons.md` updated if something surprising was learned (suggested lesson: `PASS_TO_EDITOR` filters adapter-node's own settings too, so one it doesn't list, like `HOST` was, can't be set from the container)
