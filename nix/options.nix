# Options shared by the Home Manager and NixOS modules.
{ lib }:

let
  inherit (lib) mkOption mkEnableOption types;

  # A login for one of the panels. Passwords never go into the Nix store: they're read
  # at runtime from a file (e.g. a sops/agenix secret) or printed by a command.
  login =
    {
      name,
      url,
      urlExample,
      usernameDescription,
    }:
    {
      enable = mkEnableOption "the ${name} panel";

      url = mkOption {
        type = types.str;
        default = url;
        example = urlExample;
        description = "Server URL for the ${name} panel.";
      };

      username = mkOption {
        type = types.str;
        description = usernameDescription;
      };

      passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/run/secrets/${lib.toLower name}";
        description = "File containing the password. Read at runtime, so it stays out of the Nix store.";
      };

      passwordCommand = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "pass show ${lib.toLower name}";
        description = "Command printing the password on its first line. Alternative to `passwordFile`.";
      };
    };
in
{
  enable = mkEnableOption "moqs, a minimal Quickshell shell for Hyprland";

  systemdTarget = mkOption {
    type = types.str;
    default = "hyprland-session.target";
    description = "The systemd user target that starts the shell.";
  };

  navidrome = login {
    name = "Navidrome";
    url = "";
    urlExample = "https://music.example.com";
    usernameDescription = "Navidrome username.";
  };

  matrix = login {
    name = "Matrix";
    url = "http://localhost:29325";
    urlExample = "http://localhost:29325";
    usernameDescription = "Username of the gomuks web login (set on gomuks-web's first run), not the Matrix account.";
  }
  // {
    gomuks.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run gomuks-web as a systemd user service. It is the backend the Matrix panel talks to,
        and handles sync and end-to-end encryption. Run `gomuks-web` once by hand first to set
        its web login, then log into Matrix at http://localhost:29325.
      '';
    };
  };
}
