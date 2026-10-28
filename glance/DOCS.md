# Glance

[Glance](https://github.com/glanceapp/glance) is a self-hosted dashboard that puts your feeds,
weather, calendars, bookmarks, service monitors and much more on one page. This app runs it on
your Home Assistant server together with the
[Glance Editor](https://github.com/gcarstoiu/glance-ui), a no-code editor that builds Glance's
`glance.yml` for you.

The app runs four things in one container:

- **your dashboard**, the Glance everyone looks at;
- **the editor**, where you build and change the dashboard;
- **a private preview Glance**, which the editor uses to show a draft before you save it;
- **a small gate** that would let the editor list Docker containers. Home Assistant does not
  give apps access to Docker, so it stays idle in this app.

## Requirements

- Home Assistant OS or a Supervised installation, version 2026.7 or later.
- A 64-bit system: `amd64` (most PCs and NUCs) or `aarch64` (Raspberry Pi 4 or 5, and
  most other ARM boards).
- An internet connection during installation and updates, to download the source code of
  the editor and Glance and the parts they are built from.

The first installation builds the app on your own device, including the editor and Glance.
Expect it to take several minutes, and longer on a Raspberry Pi. Building is the heaviest
moment in the app's life: if it fails on a device with little memory, stop other apps and try
again.

## Installation

1. Add this repository to Home Assistant. Go to **Settings** > **Apps** > **Install app**,
   open the three-dots menu in the top-right corner, select **Repositories**, then add:

   ```text
   https://github.com/FaliseDotCom/ha-glance
   ```

2. Find **Glance** in the app store and select **Install**.
3. On the **Info** tab, turn on **Watchdog**, and select **Start**.
4. Select **Open web UI** to open the editor, and continue with [First start](#first-start).

## First start

The dashboard has nothing to show until it has a `glance.yml`, so on a fresh install only the
editor is running. The log shows `waiting for /config/config/glance.yml` until then.

The editor opens on **Set up the editor**, with three ways to begin:

- **Upload your Glance folder:** a `.zip` of the folder that holds the `glance.yml` of a Glance
  you already run. Its include files, `assets/` folder and `.env` come with it.
- **Import glance.yml:** if you copied a `glance.yml` into the `config` folder of the app's
  [configuration folder](#files-and-folders) yourself.
- **Start empty:** one page with a layout you pick.

Build your page, use **Preview** to see it, and select **Save**. The editor checks the
configuration with Glance's own validator and only writes `glance.yml` when it passes. The
dashboard starts straight away and reloads on every later save.

Moving from a Glance you already run elsewhere? Keep it running, set this app up next to it on
another dashboard port, compare the two, then switch over.

## Opening the dashboard and the editor

The app publishes two ports, separate from the Home Assistant interface:

| Port   | What it is    | Address                                       |
| ------ | ------------- | --------------------------------------------- |
| `8080` | The dashboard | `http://<your-home-assistant-address>:8080`   |
| `8090` | The editor    | `http://<your-home-assistant-address>:8090`   |

**Open web UI** on the app's **Info** tab opens the editor. The editor can also add an **Edit**
link to the dashboard's own menu, which opens the editor on the page you are looking at; turn
it on in the editor's **Theme** screen.

### In the Home Assistant sidebar (optional)

This app does not use Home Assistant's built-in sidebar integration (called *ingress*),
because neither the editor nor the dashboard can run under the sub-path that ingress uses.
You can still add the dashboard to the sidebar with a **Webpage** dashboard:

1. Go to **Settings** > **Dashboards** and select **Add dashboard**.
2. Choose **Webpage** and enter the dashboard's address, for example
   `http://homeassistant.local:8080`.
3. Give it a title such as *Glance*, pick an icon such as `mdi:view-dashboard-variant`, and
   keep **Show in sidebar** turned on.

Two things to keep in mind:

- The browser loads Glance directly, so the sidebar entry only works where Glance's address
  is reachable, normally on your home network.
- If you open Home Assistant over `https://`, the address of the dashboard must use
  `https://` too, or the browser blocks the page. Use your [remote access](#remote-access)
  address in that case.

## The editor has no login

Anyone who can reach the editor's port can change your dashboard, and can read the values in
its `.env` file, such as API keys and passwords that widgets use. The editor is meant for your
home network only:

- Never make port 8090 reachable from the internet.
- Close the editor when you are not using it: on the **Configuration** tab, clear the editor's
  port in the **Network** section and restart the app. The dashboard keeps running. Fill the
  port in again, for example with `8090`, when you want to make changes.
- The dashboard itself can ask for a login with Glance's own
  [`auth` setting](https://github.com/glanceapp/glance/blob/main/docs/configuration.md#authentication),
  which you can add in the editor's YAML view.

## Configuration

The app has no options; everything about the dashboard is set in the editor. The
**Network** section of the **Configuration** tab sets the two ports:

- **Glance dashboard** (`8080`): change it if port 8080 is already in use on your server,
  for example by another Glance.
- **Glance editor** (`8090`): change it if port 8090 is in use, or clear it to close the
  editor (see [above](#the-editor-has-no-login)).

Restart the app after changing a port.

Glance listens on port 8080 inside the app. A `glance.yml` you import that sets
`server: port` to something else is not reachable; remove that setting in the editor.

### Values for `${VARIABLES}`

Widgets often need addresses, API keys or passwords. Glance takes these as `${VARIABLES}` in
`glance.yml`, and the editor keeps their values in a `.env` file next to it, out of
`glance.yml` and its history. Fill them in on the editor's **Values** screen, or when you add a
community widget. Glance restarts by itself when `.env` changes.

## Files and folders

The app keeps the dashboard in its own configuration folder, which you can reach with the
**Samba share** or **Studio Code Server** app. It is the `app_configs` share, in the folder
whose name ends in `_glance`:

| Path           | Contents                                                        |
| -------------- | --------------------------------------------------------------- |
| `config/`      | Your `glance.yml`, any include files, and `.env` with the values |
| `assets/`      | Glance's assets folder: icons, backgrounds and custom CSS       |
| `editor/`      | The editor's versions and settings                              |
| `preview/`     | The preview Glance's configuration, rewritten by the editor     |

You may edit `glance.yml` by hand. The editor notices the change, keeps it as its own version
and asks before saving over it.

### Backgrounds from your photos

The editor can use pictures from Home Assistant's **media** and **share** folders as
backgrounds: in the background settings, select **Add images**, then the **Server folder**
tab. The app can only read those folders; it never changes them.

## Backups

The app is included in Home Assistant backups, while it keeps running. A backup contains the
whole configuration folder: the dashboard, its `.env` values, the assets and the editor's
history. Restoring the app from a backup restores all of it.

Uninstalling the app can delete its configuration folder. Create a backup first if you might
want your dashboard back.

## Updates

The app's version number is the Glance Editor version it contains, with a fourth number for
updates of the app itself, such as `1.2.0.1`. The editor and the dashboard are always updated
together:

- Each editor release names the Glance version it was tested with.
- The app may run a newer Glance **patch** release than that, such as v0.8.7 for an editor
  tested with v0.8.6, but only after it passed the editor's own test suite. A new minor or
  major Glance version waits for an editor release that supports it.
- Updates also bring security fixes for Glance's building blocks, Node.js and the system
  packages the app runs on.

The [changelog](https://github.com/FaliseDotCom/ha-glance/blob/main/glance/CHANGELOG.md) lists
what each update contains; read it before you update. Updating builds the app again on your
device, like the first installation.

## Remote access

To use the dashboard away from home, put it behind a reverse proxy that provides HTTPS, such
as the **Cloudflared** or **NGINX Proxy Manager** app, and point the proxy at:

```text
http://<your-home-assistant-ip>:8080
```

Turn on Glance's [`auth` setting](https://github.com/glanceapp/glance/blob/main/docs/configuration.md#authentication)
first, and never point a proxy at the editor's port.

## What the app cannot do

- **Docker containers widget.** Home Assistant does not give apps access to Docker, so
  Glance's Docker containers widget and the editor's **Containers** section have nothing to
  list. A widget can still show containers of another server, through a read-only Docker
  socket proxy running there (`tcp://<server>:2375`).
- **Variables from the container.** In a plain Docker setup, `${VARIABLES}` can come from the
  container's environment. In this app they come from `.env`; see
  [Values](#values-for-variables).

## Troubleshooting

Start with the **Log** tab of the app. Each line starts with the part that wrote it:
`[start]`, `[editor]`, `[glance]` (your dashboard) or `[preview]`.

**The dashboard does not open, and the log says `waiting for /config/config/glance.yml`**
: There is no dashboard yet. Open the editor and save one; see [First start](#first-start).

**The editor does not load at `http://homeassistant.local:8090`, or the browser says the page
sent no data**
: Your browser reached the editor over IPv6, which it does not answer yet; the dashboard is not
  affected. Open the editor by your Home Assistant's IP address instead, for example
  `http://192.168.1.10:8090`. You find the address under **Settings** > **System** >
  **Network**. **Open web UI** has the same problem when you opened Home Assistant through
  `homeassistant.local`; open Home Assistant by its IP address too, or type the editor's
  address yourself.

**The app fails to start right after installation**
: Check that ports 8080 and 8090 are not used by another app, or pick different ports in the
  **Network** section.

**A Reddit widget with `search` shows no posts**
: Since Glance v0.8.7, Reddit's API only answers searches from a registered app. Add the
  widget's `app-auth` setting, as described in
  [Glance's Reddit widget documentation](https://github.com/glanceapp/glance/blob/main/docs/configuration.md#reddit),
  in the widget's YAML view. The editor does not warn about this yet.

**The editor says it cannot reach Glance after saving**
: Look for `[glance]` lines in the log. Glance stops on a configuration it cannot load and is
  started again a moment later; the line before that names the problem.

## Support

- Problems with this app: [open an issue](https://github.com/FaliseDotCom/ha-glance/issues).
- Questions about the editor: [Glance Editor issues](https://github.com/gcarstoiu/glance-ui/issues).
- Questions about Glance and its widgets:
  [Glance documentation](https://github.com/glanceapp/glance/blob/main/docs/configuration.md).
