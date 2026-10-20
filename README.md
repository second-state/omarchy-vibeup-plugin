# VibeUp — Omarchy shell plugin

A bar icon for the [vibe](https://vibekeys.dev) hardware family: it shows
whether your VibeKeys keyboard is connected over Bluetooth, lets you install
the [`vibeup`](https://github.com/second-state/vibeup) CLI with one click,
lists the companion packages vibeup manages (vibetty / vibekeys) with their
latest versions, and opens the vibeup TUI for device configuration (Wi-Fi,
ASR, key remaps — keyboard and watch).

## What it shows

- **Keyboard connected** — the mascot lights up; clicking it opens a panel
  with the device name (and battery percentage, when the device reports one
  over the standard Bluetooth battery service).
- **Keyboard paired but not connected** — the mascot is dimmed.
- **vibeup CLI not installed** — the panel offers an **Install vibeup** button.
- **Packages (vibeup)** — installed vs. latest version for each companion
  package, refreshed every time the panel opens.

## Install

```bash
omarchy plugin add https://github.com/second-state/omarchy-vibeup-plugin --enable
```

The vibeup CLI itself is optional; the widget works without it and offers to
install it (see below). If you prefer to install it yourself:

```bash
curl -fsSL https://raw.githubusercontent.com/second-state/omarchy-vibeup-plugin/main/install.sh | bash
```

## Use

- Click the bar icon to open the panel; press `Esc`, click outside the panel,
  or use **Close** to dismiss it.
- **Open vibeup TUI** launches `vibeup tui` in a new terminal
  (via `omarchy-launch-terminal`).
- **Install vibeup** runs the installer stored in this repository
  (`install.sh`, a vendored copy of the upstream
  [`second-state/vibeup`](https://github.com/second-state/vibeup) installer)
  inside the panel with every line of output visible. Nothing is downloaded or
  executed until you click the button, and the CLI lands in `~/.cargo/bin` as
  upstream `install.sh` does. When upstream's installer changes, the vendored
  copy is updated in a new plugin commit.

## Remove

```bash
omarchy plugin remove io.github.second-state.vibeup
```

This removes only the bar widget. An installed `vibeup` CLI and your VibeKeys
pairing are untouched; uninstall the CLI with `vibeup uninstall self` (or
remove `~/.cargo/bin/vibeup*`).

## Dependencies and privileges

- Runs unsandboxed inside the Omarchy shell, with your user's permissions, like
  every Omarchy plugin.
- Reads paired-device state from the system Bluetooth stack (BlueZ) — a
  powered Bluetooth adapter is required for the connection status.
- The install button shells out to `curl` and `bash` (both preinstalled on
  Omarchy). No daemon, no systemd services, no udev rules, no root.
- The plugin never writes configuration files. The upstream installer writes
  only to `~/.cargo/bin` and (when you approve it in an interactive terminal)
  your shell rc PATH line.

## Development

```bash
omarchy plugin validate ./            # manifest + entry point checks
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.second-state.vibeup
omarchy plugin enable io.github.second-state.vibeup right
```

Files under `~/.config/omarchy/plugins/` hot-reload on save, so the bar picks
up edits immediately. `omarchy plugin remove io.github.second-state.vibeup`
unlinks the symlink when you're done.

## License

[MIT](LICENSE)
