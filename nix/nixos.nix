# NixOS wrapper: the same options under services.moqs, applied to one user through Home Manager.
# Needs the Home Manager NixOS module to be imported as well. Also has the login screen
# (services.moqs.greeter), which is system-wide and works without the rest, Home Manager
# included.
self:
{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.moqs;
  system = pkgs.stdenv.hostPlatform.system;

  # Every session NixOS knows: Hyprland, GNOME, Plasma, Steam's gamescope session, …
  sessions = config.services.displayManager.sessionData.desktops;
  xserver = config.services.xserver.enable;

  # The shell's files, plus weather.json for the weather card when it's set up.
  greeterShell = pkgs.runCommand "moqs-greeter" { } ''
    cp -r ${self.packages.${system}.default} $out
    chmod -R u+w $out
    ${lib.optionalString cfg.weather.enable ''
      cp ${
        pkgs.writeText "weather.json" (
          builtins.toJSON (
            if cfg.weather.locationFile != null then
              { inherit (cfg.weather) locationFile; }
            else
              { inherit (cfg.weather) location; }
          )
        )
      } $out/weather.json
    ''}
  '';

  # Quickshell in cage, a kiosk compositor that shows one window and nothing else.
  xkb = config.services.xserver.xkb;

  greeter = pkgs.writeShellScript "moqs-greeter" ''
    export XDG_STATE_HOME=/var/lib/moqs-greeter
    # The greeter user has no home to keep a cache in.
    export XDG_CACHE_HOME=/var/lib/moqs-greeter/cache
    # The system's keyboard layout, so passwords type as they do everywhere else.
    export XKB_DEFAULT_LAYOUT=${lib.escapeShellArg xkb.layout}
    export XKB_DEFAULT_VARIANT=${lib.escapeShellArg xkb.variant}
    export XKB_DEFAULT_OPTIONS=${lib.escapeShellArg xkb.options}
    # The session picked until someone picks another.
    export MOQS_DEFAULT_SESSION=${lib.escapeShellArg (lib.defaultTo "" (config.services.displayManager.defaultSession or null))}
    export MOQS_SESSIONS=wayland=${sessions}/share/wayland-sessions:x11=${sessions}/share/xsessions
    ${lib.optionalString xserver ''
      export MOQS_XSESSION_WRAPPER="${pkgs.xorg.xinit}/bin/startx /usr/bin/env"
    ''}
    exec ${lib.getExe pkgs.cage} -s -d -- ${lib.getExe' cfg.greeter.package "quickshell"} -p ${greeterShell}/greeter.qml
  '';

  otherDisplayManagers = lib.filter (x: x.on) [
    {
      name = "services.displayManager.sddm.enable";
      on = config.services.displayManager.sddm.enable or false;
    }
    {
      name = "services.displayManager.gdm.enable";
      on = config.services.displayManager.gdm.enable or false;
    }
    {
      name = "services.xserver.displayManager.lightdm.enable";
      on = config.services.xserver.displayManager.lightdm.enable or false;
    }
  ];
in
{
  options.services.moqs = import ./options.nix { inherit lib; } // {
    user = lib.mkOption {
      type = lib.types.str;
      example = "alice";
      description = "The user whose Home Manager configuration gets the shell.";
    };

    greeter = {
      enable = lib.mkEnableOption ''
        the moqs login screen: greetd showing the lock screen's look, with a choice of user
        and of every installed session (Hyprland, GNOME, Steam, …). Replaces SDDM, GDM or
        LightDM, which have to be turned off
      '';

      package = lib.mkPackageOption pkgs "quickshell" { };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.enable -> options ? home-manager;
          message = "services.moqs.enable needs the Home Manager NixOS module (home-manager.nixosModules.home-manager) imported as well.";
        }
      ];
    }

    # Only where Home Manager is imported: its options don't exist otherwise, not even
    # behind mkIf.
    (lib.optionalAttrs (options ? home-manager) {
      home-manager = lib.mkIf cfg.enable {
        sharedModules = [ self.homeManagerModules.default ];
        users.${cfg.user}.services.moqs = builtins.removeAttrs cfg [
          "user"
          "greeter"
        ];
      };
    })

    (lib.mkIf cfg.greeter.enable {
      assertions = [
        {
          assertion = otherDisplayManagers == [ ];
          message = "services.moqs.greeter replaces the display manager; turn off ${
            lib.concatMapStringsSep " and " (x: x.name) otherDisplayManagers
          }.";
        }
      ];

      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${greeter}";
          user = "greeter";
        };
      };

      # X11 sessions start through startx.
      services.xserver.displayManager.startx.enable = lib.mkIf xserver (lib.mkDefault true);

      # Where the greeter remembers the last user and session.
      systemd.tmpfiles.rules = [
        "d /var/lib/moqs-greeter 0755 greeter greeter - -"
        "d /var/lib/moqs-greeter/cache 0755 greeter greeter - -"
      ];

      fonts.packages = [
        pkgs.nerd-fonts.jetbrains-mono
        pkgs.noto-fonts-color-emoji
      ];
    })
  ];
}
