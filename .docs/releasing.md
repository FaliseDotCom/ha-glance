# Releasing

The app version always equals the Glance Editor version it contains, so users see the editor
version in Home Assistant. Each editor release pins the Glance version it was tested with;
the app never changes Glance on its own.

## Updating to a new Glance Editor release

This repository does not contain the editor's or Glance's source code. The Dockerfile
downloads the editor's source at a pinned commit and copies Glance from its official image, so
updating means changing those pins.

### With the update script

From the repository root, in Git Bash or any other Bash shell, with Docker running:

```bash
scripts/update-glance.sh          # latest Glance Editor release
scripts/update-glance.sh 1.3.0    # a specific release
```

The script finds the release's commit, reads the Glance and Node images it pins, checks that
those exist for both architectures, refuses downgrades, updates the version in all files, adds
a changelog entry and builds the image. It does not commit anything. Then do steps 2, 3, 6 and
7 below.

### By hand

1. Find the commit of the release tag, for example `v1.3.0`:

   ```bash
   git ls-remote https://github.com/gcarstoiu/glance-ui.git 'refs/tags/v1.3.0^{}'
   ```

2. Read the [Glance Editor release notes](https://github.com/gcarstoiu/glance-ui/releases),
   and the [Glance release notes](https://github.com/glanceapp/glance/releases) when the
   Glance version changes.
3. Compare the editor's `Dockerfile` and `image/` folder with the previous release. Copy any
   change to the final stage of its Dockerfile into `glance/Dockerfile`, and check that
   `image/start.ts` still takes `DATA_DIR` and `SERVER_FOLDERS`.
4. Update the `ARG` lines at the top of `glance/Dockerfile`: `EDITOR_VERSION`,
   `EDITOR_COMMIT`, and `GLANCE_VERSION`, `GLANCE_COMMIT`, `GLANCE_IMAGE` from the editor's
   `glance.version`, and `NODE_IMAGE` from its `Dockerfile`. The build fails when these do not
   match the editor's own files.
5. Update `version` in `glance/config.yaml` and the badges in `README.md`, and add an entry
   at the top of `glance/CHANGELOG.md` that links to the editor's release notes.
6. Test as described in [Development](development.md). Always test an upgrade from the
   previous release, not only a fresh install: start the old version with a saved dashboard,
   then the new version on the same `test/` folders, and check that the editor still lists
   the old versions under **History**.
7. Commit, tag the commit with the version (`git tag 1.3.0`), and push both. Home Assistant
   offers the update to users the next time it checks the repository.

## App-only changes

For a change to the app itself without a new editor release, add a fourth version segment:
`1.2.0` becomes `1.2.0.1`, then `1.2.0.2`. The next editor release resets it.

## Changes to watch for

- **The editor publishes multi-architecture images.** Then the Dockerfile can start
  `FROM ghcr.io/gcarstoiu/glance-editor:<version>` and keep only the Home Assistant settings;
  see the design decisions in [Development](development.md#design-decisions).
- **A new data layout in `start.ts`.** The app relies on `DATA_DIR` placing everything under
  `/config`. A rename there would start users on an empty dashboard.
- **A new Node major version.** The editor runs its TypeScript entry point directly with Node,
  which needs Node 24 or later.
- **Supervisor changes.** Check the
  [app configuration reference](https://developers.home-assistant.io/docs/apps/configuration)
  for deprecations, and watch the Supervisor log for warnings about this app.
