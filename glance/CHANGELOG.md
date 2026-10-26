# Changelog

All notable changes to this app are documented here. The version number is the Glance Editor
version the app contains; a fourth segment counts updates of the app itself, including newer
Glance patch releases and security updates. See the
[Glance Editor releases](https://github.com/gcarstoiu/glance-ui/releases) and the
[Glance releases](https://github.com/glanceapp/glance/releases) for changes in those.

## 1.2.0.1

- Glance is built with Go 1.27.3 and the latest security updates of its Go modules.

## 1.2.0

- First release: the Glance Editor 1.2.0 with Glance v0.8.7. See the
  [Glance Editor 1.2.0 release notes](https://github.com/gcarstoiu/glance-ui/releases/tag/v1.2.0)
  and the [Glance v0.8.7 release notes](https://github.com/glanceapp/glance/releases/tag/v0.8.7).
- Glance v0.8.7 is a newer patch release than the v0.8.6 the editor was released with. It
  passes the editor's own test suite, and its configuration format is the same, except that the
  Reddit widget's `search` option now needs `app-auth`.
- Glance is built with Go 1.27.3 and `golang.org/x/net` v0.60.0, which fix known
  vulnerabilities in its HTTP and certificate handling. The app runs on Node.js 24.22.1.
