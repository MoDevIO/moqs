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

  # The panels read these JSON files next to shell.qml.
  settings =
    login: extra:
    builtins.toJSON (
      {
        inherit (login) url username;
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
              inherit (cfg.webuntis) school cancelledRooms subjects;
            }
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
        pkgs.writeText "weather.json" (builtins.toJSON { inherit (cfg.weather) location; })
      } $out/weather.json
    ''}
  '';

  loginAssertions =
    name: login:
    lib.optional login.enable {
      assertion = (login.passwordFile == null) != (login.passwordCommand == null);
      message = "services.moqs.${name}: set exactly one of passwordFile or passwordCommand.";
    };
in
{
  options.services.moqs = import ./options.nix { inherit lib; };

  # Imported as a NixOS module by mistake, this would fail with confusing errors about
  # systemd.user.services; say what to do instead.
  config =
    if !(options ? home) then
      throw "moqs: homeManagerModules.default is a Home Manager module. In a NixOS configuration, import moqs.nixosModules.default and set services.moqs.user instead."
    else
      lib.mkIf cfg.enable {
        assertions =
          loginAssertions "navidrome" cfg.navidrome
          ++ loginAssertions "matrix" cfg.matrix
          ++ loginAssertions "webuntis" cfg.webuntis
          ++ lib.optional cfg.navidrome.enable {
            assertion = cfg.navidrome.url != "";
            message = "services.moqs.navidrome.url must be set.";
          }
          ++ lib.optional cfg.hass.enable {
            assertion = (cfg.hass.tokenFile == null) != (cfg.hass.tokenCommand == null);
            message = "services.moqs.hass: set exactly one of tokenFile or tokenCommand.";
          }
          ++ lib.optional cfg.webuntis.enable {
            assertion = cfg.webuntis.url != "";
            message = "services.moqs.webuntis.url must be set.";
          };

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
