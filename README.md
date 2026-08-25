# NixOS configuration

Personal NixOS configuration for an ASUS laptop running Niri and a customized
Clavis/Quickshell desktop.

## Stack

- NixOS unstable with Flakes and Home Manager
- Niri on Wayland with Xwayland Satellite
- Clavis/Quickshell built from pinned Qt 6/QML sources
- NVIDIA open kernel modules and Intel platform support
- greetd, NetworkManager, Fcitx 5, Flatpak and systemd user services
- ASUS power profiles, GPU screen recording, OCR and Wayland desktop tools

## Layout

```text
.
├── flake.nix                    # Inputs and host entry point
├── hosts/ODT/
│   ├── default.nix             # Host module imports
│   ├── system.nix              # Boot, networking, locale and users
│   ├── hardware.nix            # GPU configuration
│   ├── hardware-configuration.nix
│   ├── laptop.nix              # ASUS power and firmware services
│   ├── desktop.nix             # Niri and desktop applications
│   ├── niri-config.kdl         # Niri behavior and key bindings
│   ├── clavis.nix              # Quickshell integration and user services
│   ├── home.nix                # Home Manager configuration
│   ├── proxy.nix               # Clash Verge
│   └── openssh.nix             # Opt-in, key-only SSH server
└── packages/
    ├── clavis-core.nix         # Native Clavis Qt module
    ├── clavis-config.nix       # Patched Clavis configuration
    └── patches/                # Local integration patches
```

## Usage

The `ODT` configuration is the only host currently exported. Before reusing it,
change `hostname` and `username` in `flake.nix`, then replace the generated
hardware configuration and display settings for the target machine.

Run the helper commands from anywhere inside the Git worktree. Alternatively,
set `NIXOS_CONFIG_DIR` to the repository path.

```bash
# Evaluate NixOS and validate the Niri configuration.
nixos-check

# Build without activating the result.
nixos-build

# Build and activate the new generation.
nixos-switch

# Return to the previous NixOS generation.
nixos-rollback
```

On an existing NixOS system, the equivalent standard command is:

```bash
sudo nixos-rebuild switch --flake .#ODT
```

## Fresh installation

For a fresh installation, install the flake and provision the local user password
before rebooting:

```bash
sudo nixos-install --flake .#ODT
sudo nixos-enter --root /mnt -c 'passwd ODT'
```

The password is entered interactively and is never stored in this repository or
the Nix store. SSH and its firewall rule are disabled by default. To use remote
access, provision an SSH public key out of band first, then set
`enableRemoteAccess = true` in `flake.nix`. Password and root SSH login remain
disabled.

## Machine-specific data

`hosts/ODT/hardware-configuration.nix` contains filesystem UUIDs generated for
this machine. They are required for boot and are not credentials, but forks must
replace the file with output from `nixos-generate-config` on their own hardware.

The repository intentionally excludes private keys, environment files, proxy
subscriptions, tokens and application state. Secrets must be provisioned outside
the Nix store. Do not add plaintext credentials to Nix expressions because Nix
store contents are readable by local users and may be copied to binary caches.

`clavis-effects.kdl` and `dms/cursor.kdl` are committed as safe initial values.
Home Manager copies them as writable files on first activation; Clavis owns and
may replace the runtime copies under `~/.config/niri`.

## Updating

Update one input at a time and verify the resulting generation before proceeding:

```bash
nix flake lock --update-input nixpkgs
nixos-build
```

Clavis is pinned to a specific upstream revision because the patches in
`packages/patches` target that source tree.
