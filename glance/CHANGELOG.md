# Changelog

All notable changes to this app are documented here. The version number is the Glance Editor
version the app contains; a fourth segment counts updates of the app itself, including newer
Glance patch releases and security updates. See the
[Glance Editor releases](https://github.com/gcarstoiu/glance-ui/releases) and the
[Glance releases](https://github.com/glanceapp/glance/releases) for changes in those.

## 1.5.1.2

- Glance v0.8.8, a newer patch release than the v0.8.6 the editor was released
  with. See the [Glance v0.8.8 release notes](https://github.com/glanceapp/glance/releases/tag/v0.8.8).
- Glance is built with Go 1.27.3 and the latest security updates of its Go modules.

## 1.5.1.1

- Glance is built with Go 1.27.3 and the latest security updates of its Go modules.
- `github.com/andybalholm/brotli` v1.2.7 instead of v1.2.3: fixes excessive memory use when
  decompressing crafted streams.
- `github.com/klauspost/compress` v1.20.2 instead of v1.20.0: fixes a panic on two-block frames.
- Security updates for Node.js and the system packages the app runs on.

## 1.5.1

- Glance Editor 1.5.1. See the [Glance Editor 1.5.1 release notes](https://github.com/gcarstoiu/glance-ui/releases/tag/v1.5.1).
- The editor answers over IPv6, so `http://homeassistant.local:8090` and **Open web UI** work
  without using the IP address.

## 1.5.0

- Glance Editor 1.5.0. See the [Glance Editor 1.5.0 release notes](https://github.com/gcarstoiu/glance-ui/releases/tag/v1.5.0).
- Glance is built with Go 1.27.3 and the latest security updates of its Go modules.
- Security updates for Node.js and the system packages the app runs on.

## 1.2.0.1

- Glance is built with Go 1.27.3 and the latest security updates of its Go modules.
- `golang.org/x/net` v0.62.0 instead of v0.60.0: fixes two vulnerabilities in HTML parsing
  and rendering that the RSS widget reaches when it reads a feed.

## 1.2.0

- First release: the Glance Editor 1.2.0 with Glance v0.8.7. See the
  [Glance Editor 1.2.0 release notes](https://github.com/gcarstoiu/glance-ui/releases/tag/v1.2.0)
  and the [Glance v0.8.7 release notes](https://github.com/glanceapp/glance/releases/tag/v0.8.7).
- Glance v0.8.7 is a newer patch release than the v0.8.6 the editor was released with. It
  passes the editor's own test suite, and its configuration format is the same, except that the
  Reddit widget's `search` option now needs `app-auth`.
- Glance is built with Go 1.27.3 and `golang.org/x/net` v0.60.0, which fix known
  vulnerabilities in its HTTP and certificate handling. The app runs on Node.js 24.22.1.
