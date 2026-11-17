# moqs

A minimal [Quickshell](https://quickshell.org) shell for Hyprland. Black frame around the screen, thicker on top where the bar lives. Panels grow out of the frame instead of floating above it. The layout is inspired by [Caelestia](https://github.com/caelestia-dots/shell).

## What's in it

**Bar**
- Workspaces as dots on the left. 1–5 are always shown, the rest only when they have windows or are active. A white dot slides to the active workspace.
- Clock in the middle. Clicking it opens the control centre.
- CPU and RAM bars plus a battery icon on the right.

**Corners and panels**

| Where | What | How to open |
|---|---|---|
| Top right | Notification popups and the notification centre | Popups appear on their own; push the pointer into the corner for the centre |
| Top centre | Control centre: Wi-Fi, Bluetooth, AirDrop and power profile tiles with lists, volume, brightness, now playing | Click the clock |
| Bottom left | Navidrome music player, playing through mpv | Push the pointer into the corner |
| Bottom right | Matrix client with end-to-end encryption through gomuks | Push the pointer into the corner |

- **Notifications:** action buttons, history in the notification centre, and timers that pause while hovered.
- **AirDrop** (via [Owly](https://github.com/t4t5/owly)):
  - Receive on/off.
  - Accept/decline prompts for incoming transfers.
  - A nearby-devices list. Clicking a device opens a drop zone; files dropped there get sent to it.
- **Wi-Fi:** connect and disconnect from the list, with a password field for new secured networks.
- **Bluetooth:** connect, disconnect and pair.
- **Music:** search, album lists (new, random, most played), queueing a whole album from any track, seeking. Plays are reported back to Navidrome.
- **Matrix:** room list with avatars and unread counts, conversations, sending with Markdown, older history on scroll.

Panels close once the pointer leaves them.

## Install with Nix

The flake has a Home Manager module and a NixOS wrapper around it, both configured under `services.moqs`.

### Home Manager

```nix
{
  inputs.moqs = {
    url = "github:MoDevIO/moqs";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

```nix
# in your Home Manager configuration
{
  imports = [ inputs.moqs.homeManagerModules.default ];

  services.moqs = {
    enable = true;

    navidrome = {
      enable = true;
      url = "https://music.example.com";
      username = "me";
      passwordFile = "/run/secrets/navidrome"; # or: passwordCommand = "pass show navidrome";
    };

    matrix = {
      enable = true;
      username = "gomuks"; # the gomuks web login, not your Matrix account
      passwordCommand = "pass show gomuks";
    };
  };
}
```

### NixOS

This needs the Home Manager NixOS module as well. The settings are passed on to the named user's Home Manager configuration.

```nix
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.moqs.nixosModules.default
  ];

  services.moqs = {
    enable = true;
    user = "alice";
    # navidrome = { … }; matrix = { … }; as above
  };
}
```

Don't put `homeManagerModules.default` in a NixOS module list. It stops with an error telling you to use `nixosModules.default` instead.

### What the module does

- Turns on `programs.quickshell`, started from `hyprland-session.target`. Change the target with `services.moqs.systemdTarget`.
- Installs the shell to `~/.config/quickshell`, together with `navidrome.json` and `matrix.json` generated from your settings.
- Installs the programs the shell runs:
  - always: `brightnessctl`, `curl` and `libnotify`
  - with Navidrome enabled: `mpv`
  - with Matrix enabled: `gomuks-web`, plus a user service to run it (turn the service off with `matrix.gomuks.enable = false`)

Passwords never go into the Nix store. Give exactly one of `passwordFile` (read at runtime) or `passwordCommand` (its first output line is used).

### Options

| Option | Default | |
|---|---|---|
| `enable` | `false` | Enable the shell |
| `systemdTarget` | `"hyprland-session.target"` | Target that starts it |
| `user` | (none) | NixOS module only: whose Home Manager gets the shell |
| `navidrome.enable` | `false` | Configure the music panel |
| `navidrome.url` | (none) | Navidrome server URL |
| `navidrome.username` | (none) | Navidrome username |
| `navidrome.passwordFile` / `passwordCommand` | `null` | Where the password comes from |
| `matrix.enable` | `false` | Configure the Matrix panel |
| `matrix.url` | `"http://localhost:29325"` | gomuks web address |
| `matrix.username` | (none) | gomuks web username |
| `matrix.passwordFile` / `passwordCommand` | `null` | gomuks web password |
| `matrix.gomuks.enable` | `true` | Run gomuks-web as a user service |

## Requirements the module doesn't cover

- **System services:** PipeWire (volume), BlueZ (Bluetooth), NetworkManager (Wi-Fi), UPower (battery) and power-profiles-daemon (the Power tile) are NixOS settings, so turn them on in your system configuration.
- **Font:** the shell uses **JetBrainsMono Nerd Font** (`nerd-fonts.jetbrains-mono`) for text and icons.
- **Other notification daemons:** swaync, mako or dunst would take the notification service from the shell, so disable them.
- **AirDrop:** install [Owly](https://github.com/t4t5/owly) with its own NixOS module (`services.owly`). Your Wi-Fi card has to be one Owly supports; `owly doctor` tells you.

## First-time setup for Matrix

The Matrix panel talks to a local [gomuks](https://github.com/gomuks/gomuks) backend. gomuks does sync and encryption; the shell is only the interface.

1. Run `gomuks-web` once in a terminal. It asks for a username and password for its own web login; those go into `services.moqs.matrix`.
2. Open <http://localhost:29325>, log into your Matrix account and verify the session.
3. To read messages from before this login, restore your key backup in gomuks's settings. Without it they show as "Unable to decrypt".

After that the user service keeps gomuks running and the panel connects on its own.

## Developing

Run the shell straight from a checkout; Quickshell reloads it when files change:

```sh
qs -p ./shell.qml
```

Without the Nix module, put the panel settings next to `shell.qml`. Both files are gitignored:

```jsonc
// navidrome.json
{ "url": "https://music.example.com", "username": "me", "password": "…" }

// matrix.json
{ "url": "http://localhost:29325", "username": "gomuks", "password": "…" }
```

Both accept `"passwordCommand"` instead of `"password"`. Sizes, colours and fonts live in `config/Config.qml`.

```
shell.qml        entry point: one frame per screen
config/          Config singleton: sizes, colours, fonts
modules/         Frame, bar, notifications, control centre, music, matrix
services/        Notifications, Owly, Navidrome, mpv player, Matrix, brightness, CPU/RAM
nix/             package, Home Manager and NixOS modules
```

Quickshell's file watcher stops following a file that gets replaced, for example by `sed -i`. Edit files in place, or restart `qs` when changes stop showing up.
