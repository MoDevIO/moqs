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

  webuntis =
    login {
      name = "WebUntis";
      url = "";
      urlExample = "https://mese.webuntis.com";
      usernameDescription = "WebUntis username.";
    }
    // {
      school = mkOption {
        type = types.str;
        example = "Example-School";
        description = "School name as WebUntis knows it: the `school=` part of the WebUntis login page's URL.";
      };

      cancelledRooms = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "Eva" ];
        description = "Rooms whose lessons show as cancelled (crossed out), ignoring case.";
      };

      subjects = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "What you type, e.g. `Eng`.";
              };
              untis = mkOption {
                type = types.str;
                description = "The subject's name in WebUntis, e.g. `Englisch`.";
              };
            };
          }
        );
        default = [ ];
        example = [
          {
            name = "Eng";
            untis = "Englisch";
          }
        ];
        description = ''
          Short names for subjects when adding homework: "Eng S. 42 bis 21.11." files it under
          Englisch, due on the 21st. Without a date, the subject's next lesson sets it.
        '';
      };

      homeworkFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/home/alice/Documents/homework.txt";
        description = ''
          Text file holding your own homework and which homework you ticked off. Created when
          first needed. `null` uses `$XDG_STATE_HOME/moqs/homework.txt`.
        '';
      };
    };

  weather = {
    enable = mkEnableOption "the weather widget (from Open-Meteo, no API key needed)";

    location = mkOption {
      type = types.str;
      example = "Frankfurt, DE";
      description = ''
        Where the weather is for: a place name, optionally narrowed down by country or region
        ("Springfield, Illinois"), a GeoNames ID (the number in a geonames.org link, e.g.
        "2925533"), or "latitude,longitude".
      '';
    };
  };

  hass = {
    enable = mkEnableOption "the Home Assistant widget";

    url = mkOption {
      type = types.str;
      example = "http://homeassistant.local:8123";
      description = "Home Assistant URL.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/hass";
      description = ''
        File containing a long-lived access token (made on your Home Assistant profile page,
        under Security). Read at runtime, so it stays out of the Nix store.
      '';
    };

    tokenCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "pass show hass";
      description = "Command printing the token on its first line. Alternative to `tokenFile`.";
    };

    sections = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
      example = lib.literalExpression ''
        [
          { type = "toggle"; entity = "light.mo"; }
          {
            type = "sensors";
            title = "Energy";
            entities = [
              { entity = "sensor.foxess_pvenergytotal"; name = "Produced"; icon = "mdi:solar-power"; }
              { entity = "sensor.foxess_load"; name = "Used"; icon = "mdi:home-lightning-bolt"; }
              { entity = "sensor.batterie"; name = "Battery"; }
            ];
          }
        ]
      '';
      description = ''
        What the Home Assistant card shows, top to bottom. Each section has a `type`, an
        optional `title`, and either one `entity` or a list of `entities`:

        - `toggle`: switch entities on and off; lights that dim get a brightness slider
        - `button`: run a scene or script, or press a button
        - `sensor`: one value per row
        - `sensors`: several values side by side in one block

        An entity is an ID or `{ entity; name; icon; }`. Name and icon default to Home
        Assistant's; icons are Material Design Icons names like `"mdi:solar-power"`.
      '';
    };
  };

  matrix =
    login {
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
