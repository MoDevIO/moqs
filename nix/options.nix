# Options shared by the Home Manager and NixOS modules.
{ lib }:

let
  inherit (lib) mkOption mkEnableOption types;

  # A setting read from a file when the shell runs, e.g. a sops-nix or agenix secret, so it
  # stays out of the Nix store. The shell's user has to be able to read it.
  secretFile =
    what:
    mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/example";
      description = "File whose first line is ${what}. Read at runtime, so it stays out of the Nix store.";
    };

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

      urlFile = secretFile "the server URL, instead of `url`";

      username = mkOption {
        type = types.str;
        default = "";
        description = usernameDescription;
      };

      usernameFile = secretFile "the username, instead of `username`";

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

  dragToOpen =
    lib.genAttrs
      [
        "notifications"
        "music"
        "matrix"
      ]
      (
        corner:
        mkOption {
          type = types.bool;
          default = false;
          description = ''
            Pull the ${corner} panel out of its corner's border, like the dashboard, instead of
            opening it when the pointer reaches the corner.
          '';
        }
      );

  launcher.searchEngine = mkOption {
    type = types.str;
    default = "https://duckduckgo.com/?q=%s";
    example = "https://www.startpage.com/do/search?q=%s";
    description = "Web search for the launcher's `?` mode; `%s` stands for the query.";
  };

  lock.pamService = mkOption {
    type = types.str;
    default = "login";
    example = "swaylock";
    description = ''
      PAM service (a file in /etc/pam.d) the lock screen checks the password with. On NixOS,
      `security.pam.services.<name> = { };` makes a dedicated one.
    '';
  };

  updates = {
    flake = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/me/nixos-config";
      description = ''
        The system flake (a local checkout) the control centre's Updates tile looks after: it
        shows how far its nixpkgs is behind, and runs `nix flake update` and a rebuild, asking
        for the password through the shell's polkit agent. Without it the tile is hidden.
      '';
    };

    host = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "laptop";
      description = "The `nixosConfigurations` name to build; this machine's hostname without it.";
    };
  };

  capture.ocrLanguages = mkOption {
    type = types.listOf types.str;
    default = [
      "eng"
      "deu"
    ];
    example = [
      "eng"
      "deu"
      "lat"
    ];
    description = ''
      Languages the Capture tile's "Copy text" reads (tesseract's codes: eng, deu, lat, fra,
      …). Only these are installed; each makes reading a little slower.
    '';
  };

  airdrop.name = mkOption {
    type = types.nullOr types.str;
    default = null;
    example = "Mo's Laptop";
    description = "The name other devices see for AirDrop. `null` uses the host name.";
  };

  vocab.server = mkOption {
    type = types.nullOr types.str;
    default = null;
    example = "http://worker-03";
    description = ''
      The moqs-vocab server the vocabulary trainer uses: words, schedule, settings, stats and
      sessions all live there (with its web app). `null`: no vocabulary trainer words.
    '';
  };

  ai = {
    enable = mkEnableOption "a language model behind an OpenAI-compatible API, for the launcher's assistant (Tab) and mnemonics for hard vocabulary words";

    url = mkOption {
      type = types.str;
      example = "http://localhost:11434/v1";
      description = "Base URL of the API, the part before `/chat/completions`.";
    };

    model = mkOption {
      type = types.str;
      example = "llama3.1:8b";
      description = "The model to ask (by the assistant, and for mnemonics).";
    };

    apiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/llm";
      description = "File containing the API key, if the server needs one. Read at runtime, so it stays out of the Nix store.";
    };

    apiKeyCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "pass show llm";
      description = "Command printing the API key on its first line. Alternative to `apiKeyFile`.";
    };

    language = mkOption {
      type = types.str;
      default = "";
      example = "German";
      description = "Language the mnemonics are written in. Empty: the translations' language.";
    };

    prepareModel = mkOption {
      type = types.str;
      default = "";
      example = "mistral-large-4-1t-a52b";
      description = "Model for the suggestions prepared ahead in the background for words missed often, where speed doesn't matter. Empty: `model`.";
    };
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
      schoolFile = secretFile "the school name, instead of `school`";

      school = mkOption {
        type = types.str;
        default = "";
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

    locationFile = secretFile "the location, instead of `location`";

    location = mkOption {
      type = types.str;
      default = "";
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
