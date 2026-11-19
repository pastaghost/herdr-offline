# herdr-offline

Installs the [Herdr desktop app](https://github.com/herdrdev/herdr-app) and
[herdr-core](https://github.com/herdrdev/herdr-core) (`hc`) on an Apple Silicon
Mac that can't reach `releases.herdr.dev`. The release files are committed to
this repo, so a `git clone` is the only download.

| Package | Version | File |
|---|---|---|
| Herdr app | 0.1.16 | `app/0.1.16/herdr-app-macos-aarch64.tar.gz` |
| herdr-core | 0.1.21 | `core/0.1.21/herdr-core-macos-aarch64.tar.gz` |

Each file matches the SHA-256 published in the upstream manifest
(`app/upstream-latest.json`, `core/upstream-latest.json`). The app is signed
with Herdr, Inc.'s Developer ID and notarized by Apple.

There is no Intel Mac build of the app.

## Install

```sh
git clone <this repo> herdr-offline
cd herdr-offline
./install.sh               # or --app-only / --core-only
```

This puts `Herdr.app` in `~/Applications`. It puts `herdr-app`, `herdr-core`
and `hc` in `~/.local/bin`.

Open Herdr from Spotlight or `~/Applications`. If `~/.local/bin` isn't on your
PATH, the script prints the line to add to `~/.zshrc`.

## What the installer does

It does the same steps as the official installers
(`releases.herdr.dev/app/install.sh` and `.../core/install.sh`). It reads the
files from this repo instead of downloading them. Before installing, it:

1. Checks each file's SHA-256 against `SHA256SUMS`.
2. Checks that `Herdr.app` (`dev.herdr.app`) and `Herdr Core.app`
   (`dev.herdr.core`) are signed by Herdr's Apple team, `2W9652Q7QR`. The
   official app installer only checks that a signature is valid; this one also
   checks whose signature it is.
3. Installs the app without changing its signature. It refuses to run if Herdr
   is running from `~/Applications/Herdr.app`. Quit Herdr and run it again.

What it does with herdr-core depends on what is already installed:

| Already on the machine | What the installer does |
|---|---|
| No herdr-core | Installs it the same way the official installer does. |
| An older herdr-core in `~/.local/bin` | Updates it in place. Running terminals keep running. |
| The same or a newer herdr-core | Leaves it alone. |
| herdr-core somewhere else, e.g. from a package manager | Leaves it alone. |

The official app installer leaves updating the core to the app. Behind the VPN
the app can't download updates, so this script updates the core itself.

Files cloned with git aren't marked as downloaded from the internet, so macOS
won't show the "downloaded from the internet" warning when you first open the
app.

## Behind the VPN afterwards

- The app's update check and `hc update` reach `releases.herdr.dev`, so they
  fail there. To upgrade, pull this repo and run `./install.sh` again.
- Telemetry goes to `telemetry.herdr.dev` and is on by default. Turn it off in
  **Settings → Privacy**, or add `"telemetry": false` to
  `~/.config/herdr-app/settings.json`.
- The herdr terminal you already have checks `herdr.dev` too. To stop that, put
  these lines in `~/.config/herdr/config.toml`:

  ```toml
  [update]
  version_check = false
  manifest_check = false
  ```

## Updating this repo

On a machine with normal internet access:

```sh
./fetch.sh        # latest app + core for macOS arm64, checks the hashes
git add -A && git commit -m "Herdr app X.Y.Z, herdr-core A.B.C" && git push
```

Then on the VPN machine, run `git pull && ./install.sh`.

## License

Herdr and herdr-core are Apache-2.0, © Herdr, Inc. and contributors.
