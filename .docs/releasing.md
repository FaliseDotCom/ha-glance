# Releasing

The app version is the Glance Editor version it contains, so users see the editor version in
Home Assistant. A fourth segment counts updates of the app itself: `1.2.0` becomes
`1.2.0.1`, then `1.2.0.2`, and the next editor release resets it. Running a newer Glance patch
release, or picking up security updates, are such app updates.

This repository does not contain the editor's or Glance's source code. The Dockerfile
downloads both at pinned commits and builds them, so updating means moving the pins
described in [Development](development.md#pins).

## Automatic update pull requests

The **Update** workflow (`.github/workflows/update.yml`) runs every Monday, and on demand
from the **Actions** tab. It runs `scripts/update-glance.sh`, and when any pin moved:

1. commits the change to the `update/glance` branch, replacing what was there;
2. opens a pull request, or refreshes the open one, with a summary: what changed, links to
   the release notes, the upstream comparisons to review, and the changes to Glance's
   configuration reference;
3. starts **CI** on the branch. A pull request opened by a workflow does not start other
   workflows, so the workflow starts CI itself; its results show on the pull request.

To release, review the pull request (see [the checklist](#reviewing-an-update)), merge it,
then tag the merge commit with the version and push the tag:

```bash
git pull
git tag 1.2.0.1
git push --tags
```

Home Assistant offers the update to users the next time it checks the repository.

**Dependabot** (`.github/dependabot.yml`) only keeps the actions used by the workflows up to
date. The editor, Glance, Go and Node pins depend on each other, which Dependabot cannot
follow, so the Update workflow handles them.

### Repository settings

- **Settings** > **Actions** > **General** > **Workflow permissions:** turn on **Allow GitHub
  Actions to create and approve pull requests**. Without it the Update workflow cannot open
  its pull request.
- **Settings** > **Branches:** protect `main` and require the CI checks, so an update can
  only be merged once they pass.
- GitHub emails the repository owner when a scheduled run fails, which is how a new
  vulnerability found by the weekly CI run gets noticed.

## Updating by hand

From the repository root, in Git Bash or any other Bash shell, with Docker running:

```bash
scripts/update-glance.sh          # newest of everything
scripts/update-glance.sh 1.3.0    # a specific Glance Editor release
```

The script finds the release's commit and pins, picks the Glance, Go and Node versions by
the rules in [Development](development.md#pins), checks that each image exists for both
architectures, refuses downgrades, updates the version in all files, adds a changelog entry
and builds the image. It does not commit anything. Then run the checks from
[Development](development.md#testing-a-change), review as below, commit, tag and push.

## Reviewing an update

1. Read the release notes linked in the new changelog entry.
2. **New editor release:** compare the editor's `Dockerfile` and `image/` folder with the
   previous release (the pull request links the comparison). Copy changes to its final stage
   into `glance/Dockerfile`, and check that `image/start.ts` still takes `DATA_DIR` and
   `SERVER_FOLDERS`.
3. **New Glance release:** check Glance's `Dockerfile` for build changes to copy into the
   `glance` stage, and read the changes to its configuration reference. A changed or removed
   option may need an editor release first; then hold the update back by pinning the older
   Glance by hand.
4. All CI checks pass. When the security check fails, see [Security](security.md).
5. Test an upgrade, not only a fresh install: start the previous version with a saved
   dashboard, then the new version on the same data, and check that the editor still lists
   the old versions under **History**.

## Changes to watch for

- **The editor publishes multi-architecture images.** Then the editor stages could be
  replaced by its image; the Glance and Node updates would need another way in.
- **A new data layout in `start.ts`.** The app relies on `DATA_DIR` placing everything under
  `/config`. A rename there would start users on an empty dashboard.
- **A new Node major version in the editor.** `NODE_IMAGE` follows the editor's major
  version, so it moves along automatically; check the release notes.
- **Supervisor changes.** Check the
  [app configuration reference](https://developers.home-assistant.io/docs/apps/configuration)
  for deprecations, and watch the Supervisor log for warnings about this app.
