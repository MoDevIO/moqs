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

  # A setting, or the file it's read from at runtime instead ("urlFile" for "url").
  fromFile =
    name: value: file:
    if file != null then { "${name}File" = file; } else { ${name} = value; };

  # The panels read these JSON files next to shell.qml.
  settings =
    login: extra:
    builtins.toJSON (
      fromFile "url" login.url login.urlFile
      // fromFile "username" login.username login.usernameFile
      // {
        passwordCommand =
          if login.passwordCommand != null then
            login.passwordCommand
          else
            "cat ${lib.escapeShellArg login.passwordFile}";
      }
      // extra
    );

  shell = pkgs.runCommand "moqs-config" { } ''
    cp -r ${self.packages.${pkgs.stdenv.hostPlatform.system}.default} $out
    chmod -R u+w $out
    cp ${
      pkgs.writeText "settings.json" (
        builtins.toJSON {
          inherit (cfg) dragToOpen;
          launcher.search = cfg.launcher.searchEngine;
          lock.pam = cfg.lock.pamService;
        }
      )
    } $out/settings.json
    ${lib.optionalString (cfg.airdrop.name != null) ''
      cp ${pkgs.writeText "airdrop.json" (builtins.toJSON { inherit (cfg.airdrop) name; })} $out/airdrop.json
    ''}
    ${lib.optionalString cfg.navidrome.enable ''
      cp ${pkgs.writeText "navidrome.json" (settings cfg.navidrome { })} $out/navidrome.json
      ln -s ${pkgs.mpvScripts.mpris} $out/mpv-mpris
    ''}
    ${lib.optionalString cfg.matrix.enable ''
      cp ${pkgs.writeText "matrix.json" (settings cfg.matrix { })} $out/matrix.json
    ''}
    ${lib.optionalString cfg.webuntis.enable ''
      cp ${
        pkgs.writeText "webuntis.json" (
          settings cfg.webuntis (
            {
              inherit (cfg.webuntis) cancelledRooms subjects;
            }
            // fromFile "school" cfg.webuntis.school cfg.webuntis.schoolFile
            // lib.optionalAttrs (cfg.webuntis.homeworkFile != null) { inherit (cfg.webuntis) homeworkFile; }
          )
        )
      } $out/webuntis.json
    ''}
    ${lib.optionalString cfg.hass.enable ''
      cp ${
        pkgs.writeText "hass.json" (
          builtins.toJSON {
            inherit (cfg.hass) url sections;
            tokenCommand =
              if cfg.hass.tokenCommand != null then
                cfg.hass.tokenCommand
              else
                "cat ${lib.escapeShellArg cfg.hass.tokenFile}";
          }
        )
      } $out/hass.json
    ''}
    ${lib.optionalString cfg.weather.enable ''
      cp ${
        pkgs.writeText "weather.json" (
          builtins.toJSON (fromFile "location" cfg.weather.location cfg.weather.locationFile)
        )
      } $out/weather.json
    ''}
  '';

  # Exactly one of a setting and its file: "username" or "usernameFile".
  oneOf =
    path: name: value: file: {
      assertion = (value != "") != (file != null);
      message = "services.moqs.${path}: set exactly one of ${name} or ${name}File.";
    };

  loginAssertions =
    name: login:
    lib.optionals login.enable [
      {
        assertion = (login.passwordFile == null) != (login.passwordCommand == null);
        message = "services.moqs.${name}: set exactly one of passwordFile or passwordCommand.";
      }
      (oneOf name "username" login.username login.usernameFile)
    ];
in
{
  options.services.moqs = import ./options.nix { inherit lib; } // {
    # The login screen is system-wide and lives in the NixOS module; this only catches it
    # being set here by mistake.
    greeter = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      visible = false;
    };
  };

  # Imported as a NixOS module by mistake, this would fail with confusing errors about
  # systemd.user.services; say what to do instead.
  config =
    if !(options ? home) then
      throw "moqs: homeManagerModules.default is a Home Manager module. In a NixOS configuration, import moqs.nixosModules.default and set services.moqs.user instead."
    else
      lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.greeter == { };
            message = "services.moqs.greeter is the login screen, which is system-wide: set it in your NixOS configuration (with nixosModules.default), not in Home Manager.";
          }
        ]
          ++ loginAssertions "navidrome" cfg.navidrome
          ++ loginAssertions "matrix" cfg.matrix
          ++ loginAssertions "webuntis" cfg.webuntis
          ++ lib.optional cfg.navidrome.enable (oneOf "navidrome" "url" cfg.navidrome.url cfg.navidrome.urlFile)
          ++ [
            {
              assertion = lib.hasInfix "%s" cfg.launcher.searchEngine;
              message = "services.moqs.launcher.searchEngine must contain %s, where the query goes.";
            }
          ]
          ++ lib.optional cfg.hass.enable {
            assertion = (cfg.hass.tokenFile == null) != (cfg.hass.tokenCommand == null);
            message = "services.moqs.hass: set exactly one of tokenFile or tokenCommand.";
          }
          ++ lib.optionals cfg.webuntis.enable [
            (oneOf "webuntis" "url" cfg.webuntis.url cfg.webuntis.urlFile)
            (oneOf "webuntis" "school" cfg.webuntis.school cfg.webuntis.schoolFile)
          ]
          ++ lib.optional cfg.weather.enable (oneOf "weather" "location" cfg.weather.location cfg.weather.locationFile);

        programs.quickshell = {
          enable = true;
          systemd = {
            enable = true;
            target = cfg.systemdTarget;
          };
        };

        xdg.configFile."quickshell".source = shell;

        # Programs the shell runs.
        home.packages =
          with pkgs;
          [
            brightnessctl
            cliphist
            curl
            libnotify
            wl-clipboard
          ]
          ++ lib.optional cfg.navidrome.enable mpv
          ++ lib.optional cfg.matrix.enable gomuks-web;

        systemd.user.services.gomuks-web = lib.mkIf (cfg.matrix.enable && cfg.matrix.gomuks.enable) {
          Unit = {
            Description = "gomuks web, the Matrix backend for moqs";
            After = [ "network-online.target" ];
          };
          Service = {
            ExecStart = lib.getExe' pkgs.gomuks-web "gomuks-web";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
}
