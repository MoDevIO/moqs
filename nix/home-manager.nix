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
    login:
    builtins.toJSON {
      inherit (login) url username;
      passwordCommand =
        if login.passwordCommand != null then
          login.passwordCommand
        else
          "cat ${lib.escapeShellArg login.passwordFile}";
    };

  shell = pkgs.runCommand "moqs-config" { } ''
    cp -r ${self.packages.${pkgs.stdenv.hostPlatform.system}.default} $out
    chmod -R u+w $out
    ${lib.optionalString cfg.navidrome.enable ''
      cp ${pkgs.writeText "navidrome.json" (settings cfg.navidrome)} $out/navidrome.json
    ''}
    ${lib.optionalString cfg.matrix.enable ''
      cp ${pkgs.writeText "matrix.json" (settings cfg.matrix)} $out/matrix.json
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
          ++ lib.optional cfg.navidrome.enable {
            assertion = cfg.navidrome.url != "";
            message = "services.moqs.navidrome.url must be set.";
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
