# nics — Nix Package Manager CLI & Setup for Arch Linux

`nics` is a lightweight, intuitive, and modern CLI wrapper for the **Nix package manager** on Arch Linux. It provides seamless management of packages using **Nix Flakes** and **user profiles**, featuring simultaneous access to both **`unstable`** and **`stable`** channels.

---

## Features

- ⚡ **Zero-Fuss Automated Setup:** Installs Nix, configures multi-user build daemons, and sets up shell integration in one command.
- 🔀 **Dual-Channel Freedom:** Effortlessly install bleeding-edge packages from `unstable` or rock-solid packages from `stable` with a simple `-s` / `--stable` flag.
- 📊 **Download & Install Size Previews:** Transparent Pacman-style confirmation table showing compressed download and installed sizes before downloading.
- 🔍 **Update Checking:** Safely inspect available updates and upstream Flake commit advances (`nics check`) before applying changes.
- ⏪ **Instant Rollback:** Atomic profile generations mean you can inspect history (`nics history`) and revert any upgrade immediately with `nics rollback`.
- 🎮 **Opt-in GPU Acceleration:** Graphical apps (OpenGL/EGL/Vulkan) are supported on-demand via `nics gl <app>` with explicit user opt-in.
- 📦 **Modern Flakes & Profile Backend:** Uses `nix profile` and Flakes under the hood for atomic installs, fast rollbacks, and reproducible environments.
- 🚀 **Ephemeral Run & Shell:** Try tools without installing them using `nics run` or drop into interactive dev environments with `nics shell`.
- 🖥️ **Desktop App Integration:** Automatically configures `XDG_DATA_DIRS` so GUI apps installed via Nix appear in your desktop launcher (GNOME, KDE, Rofi, etc.).
- 🩺 **Built-in Diagnostic Doctor:** Quickly verify daemon health, socket permissions, and PATH integration with `nics doctor`.

---

## Quick Start

### 1. Run Setup Script

Run the automated installer from the `nics` directory:

```bash
cd ~/nics
./setup.sh
```

*(The installer will request `sudo` permissions when configuring `/etc/nix/nix.conf` and `nix-daemon.service`)*

### 2. Activate Your Shell

Reload your shell configuration:

```bash
source ~/.bashrc
```

*(or restart your terminal)*

### 3. Verify Health

```bash
nics doctor
```

---

## Command Reference

### Package Management

| Command | Description | Example |
| :--- | :--- | :--- |
| `nics install <pkg...>` | Install package(s) with size confirmation table | `nics install ripgrep fzf bat` |
| `nics install -y <pkg...>` | Install package(s) skipping confirmation prompt | `nics install -y btop` |
| `nics install --stable <pkg>` | Install package(s) from **stable** channel | `nics install --stable nodejs` |
| `nics remove <pkg...>` | Uninstall package(s) | `nics remove ripgrep` |
| `nics update [pkg...]` | Upgrade all (or specific) packages & channels | `nics update ripgrep` |
| `nics check` / `outdated` | Check for available package & channel updates | `nics check` |
| `nics list` | List all installed packages | `nics list` |
| `nics search <query>` | Search available packages in nixpkgs | `nics search btop` |
| `nics search --stable <query>` | Search available packages in stable | `nics search --stable neovim` |
| `nics info <pkg>` | Display package metadata and description | `nics info git` |

### Graphical & GPU Acceleration

| Command | Description | Example |
| :--- | :--- | :--- |
| `nics gl <app> [-- args]` | Launch GUI applications with GPU hardware acceleration (opt-in) | `nics gl localsend_app` |
| `nics setup-gpu` | Permanently install `nixGL` GPU bridge into profile | `nics setup-gpu` |

### History & Instant Rollback

| Command | Description | Example |
| :--- | :--- | :--- |
| `nics history` | View atomic profile generations history | `nics history` |
| `nics rollback` | Revert to the previous working profile generation | `nics rollback` |

### Ephemeral Execution & Development Shells

| Command | Description | Example |
| :--- | :--- | :--- |
| `nics run <pkg> [-- args]` | Run an application ephemerally without installing | `nics run cowsay -- "Hello Arch!"` |
| `nics shell <pkg...>` | Open a temporary subshell with packages available | `nics shell python3 poetry gcc` |

### Maintenance & Channels

| Command | Description | Example |
| :--- | :--- | :--- |
| `nics channel list` | Show configured channels and flake registries | `nics channel list` |
| `nics channel update` | Update channels and flake registry caches | `nics channel update` |
| `nics channel set-default <stable\|unstable>` | Change default channel for `nics install` | `nics channel set-default stable` |
| `nics gc [--all]` | Free disk space and optimize store hardlinks | `nics gc --all` |
| `nics doctor` | Run installation health diagnostics | `nics doctor` |

---

## Checking for Updates & Upgrading

To inspect if your packages have upstream updates:
```bash
nics check
```

To upgrade all installed packages and refresh channels:
```bash
nics update
```

If an upgrade ever introduces an unwanted change, undo it instantly:
```bash
nics rollback
```

---

## Stable vs. Unstable Channels

`nics` configures both channels side-by-side:

- **Unstable (`nixpkgs` / `nixpkgs-unstable`):** Tracks the latest packages from the NixOS master branch. Ideal for tools where you want the newest releases.
- **Stable (`nixpkgs-stable` / `nixos-24.11`):** Tracks the official verified stable release branch.

You can specify the channel per-command:
```bash
# Bleeding edge (default):
nics install fastfetch

# Rock-solid stable:
nics install -s postgresql
```

To change the global default channel for `nics`:
```bash
nics channel set-default stable
# or
nics channel set-default unstable
```

Configuration is stored in `~/.config/nics/config`.

---

## Project Structure

```
~/nics/
├── bin/
│   └── nics        # The nics CLI wrapper script
├── setup.sh        # Automated Arch Linux installer & daemon setup
└── README.md       # Documentation and user guide
```
