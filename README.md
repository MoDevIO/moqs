# moqs

A minimal [Quickshell](https://quickshell.org) shell for Hyprland. Black frame around the screen, thicker on top where the bar lives. Panels grow out of the frame instead of floating above it. The layout is inspired by [Caelestia](https://github.com/caelestia-dots/shell).

## What's in it

**Bar**
- Workspaces as dots on the left. 1–5 are always shown, the rest only when they have windows or are active. A white dot slides to the active workspace.
- Clock in the middle. Clicking it opens the control centre.
- While volume or brightness changes, the clock turns into a level bar for a moment.
- For touch strips and other inputs, both can be driven over IPC:
  ```sh
  qs ipc call volume press     # shows the level until release
  qs ipc call volume up        # one step up (5%); down: one step down
  qs ipc call volume release
  ```
  The same works with `brightness`. `release` hides the level right away; `up` and `down` without a `press` show it briefly.
- CPU and RAM bars plus a battery icon on the right; clicking the battery shows its percentage and the time left (to empty, or to full while charging). Below 15 % on battery a notification says so, below 5 % an urgent one, each once until it's plugged in.
- **Microphone and camera in use:** while an app records from a microphone or has a camera open, an orange dot with a microphone or a camera shows left of the clock; hovered, the apps' names. Recording what plays (as the visualizer does) doesn't count. Apps that open the camera directly, as browsers do, are found too (checked every three seconds).

**Vocabulary**
- The vocabulary lives on a [moqs-vocab](http://worker-03/) server, set with `services.moqs.vocab.server = "http://worker-03";` (or `"vocab": { "server": "…" }` in `settings.json`): words, schedule, settings, stats and the answer log are kept there, and scheduling and answer checking run there, so its web app and the shell are always the same (practising in one shows in the other at once). The shell follows the server's API and events. Mnemonic suggestions are still made here. If the server can't be reached, the pane says so, and the lock screen and games let you through rather than ask a word. Without a server set there are no words.
- `;` in the launcher (or `qs ipc call vocab open`) asks words by spaced repetition, as Anki does with typed answers: type the translation and press Enter, or press Enter alone if you don't know it. A wrong answer (or none) counts as **Again** and shows the right one, which you type out before the next word. After a right answer you rate it as in Anki: **1 Hard · 2 Good · 3 Easy** (Enter is Good), each shown with when it would bring the word back. After a wrong one, what you typed is shown against the answer, wrong letters red and missing ones orange, as Anki compares typed answers. **Ctrl+Z** (or **Undo**) takes the last answer back and asks the word again. The pane's corner counts what's left as Anki does: new, learning and review words, in blue, red and green. If your answer was right after all (a synonym the list doesn't have, say), **I got it right** under it (or Ctrl+Enter) takes the Again back and lets you rate it; only in the pane, not on the lock screen or before a game. A wrong answer that is another word's translation is pointed out, e.g. "Mixed up: that's nūptiae = die Heirat".
- Scheduling is Anki's with FSRS on (FSRS-6 with its default weights, as Anki's fsrs-rs 6.6.2): each word has a stability and a difficulty that every answer updates. New words go through Anki's learning steps (1 and 10 minutes), forgotten ones through its relearning steps (10 minutes), with Anki's rules for Hard, Good and Easy in them; when nothing else is left, words in those steps due within 20 minutes come early, as Anki learns ahead. After that a word is asked again when the chance of still remembering it falls to 90 % (`retention`), at most 100 years later, its interval spread a little by Anki's fuzz so words learnt together don't stay together. These settings are the server's. Typos and accents don't make an answer wrong. After a right answer the whole answer shows, with the meanings you didn't type.
- A day starts at 4 am, as in Anki: practice after midnight still counts for the day before, and a word due "tomorrow" is there from 4 am, not 24 hours after you answered it.
- Due words come first, then up to 20 new ones a day (once you're caught up, holding **Learn more** for three seconds gives another 20), in the list's order or, with **Random** at the bottom of the pane, at random. A word is asked as written (word → translation); **Both ways** asks it the other way round too.
- Words are in the server's `vocab.txt`, one per line as `word = translation` (tab-separated lines, as Anki exports them, work too). `,`, `/` or `;` separates answers that each count (not inside brackets), a part in brackets may be left out, and German nouns count without their article: `currere = (schnell) laufen, rennen`, `silentium = die Ruhe, die Stille`. Umlauts count however they're typed (`schön`, `schoen`, `schon`), and missing accents or one typo in a longer word count too, with the right spelling shown. In the pane, `+word = translation` adds one and Ctrl+Delete removes the one shown. The schedule is kept in `vocab.json` beside it, on the server.
- A line may end in a note after ` # `, e.g. grammar: `dux = der Führer # (Gen. Sg.:) ducis · (m)`. It shows under the answer once you've answered. A comment line such as `# Lektion 3` heads the words below it.
- **Hard words:** a word forgotten in reviews eight times, a leech as Anki calls it, is marked in red while it's asked, with how often you've forgotten it. Once it's answered, the pane offers to keep a mnemonic with it: type `#` and the mnemonic (a sentence with a word that sounds like it), and it's added to the word's line in `vocab.txt` as ` # mnemonic: …` (the older ` # aid: …` still works) (after its note, which stays), shown with the answer from then on (`#` alone removes it). With `services.moqs.vocab.mnemonics` set up, a language model behind an OpenAI-compatible API (Ollama, llama.cpp, vLLM, or a hosted one) suggests four once a word is answered, on a click or **Tab**: an English or German word from the same root when there is one (restituere: restore), and short scenes where an everyday German word that sounds like the start of the word meets its main meaning ("Ich zeige auf ein Monster", monstrare = zeigen; "Ich werfe sofort Konfetti", cōnfestim = sofort). The shell finds the sound-alike words itself (from a list of common German words, by a rough sound spelling: Latin read as at school, v as w, c as k or z), since a language model can't hear what words sound like; the model only builds the pictures. After a mix-up, one tells the two apart. Ones without the word's meaning in them are dropped. For words forgotten three times or more (`prepareMisses` in `config/Config.qml`) they're prepared ahead in the background, one word every half minute or so, saved in `$XDG_STATE_HOME/moqs/mnemonics-cache.json`; those show at once ("Mnemonics ready"). A click or **1–4** keeps one, **Other ideas** (or Tab again) asks again with other sound-alikes and the ones turned down so far, Enter goes on. Only the word, its translation and note, the sound-alike words, the mnemonics you kept lately (as examples of your taste) and the word it was mixed up with are sent to the model. Every reply (with the sound-alikes given, what the model wrote and what was shown), prepared suggestions shown, and every mnemonic kept, picked or typed, goes to `$XDG_STATE_HOME/moqs/mnemonics-log.jsonl`, for seeing later what works. Stats lists the hard words, most missed first (all of them with `qs ipc call vocab hardWords`). A word stops counting as hard after three reviews right in a row.
- Every answer is appended to the server's `vocab-log.jsonl`, one JSON object a line: the word, what you typed, right or not, the grade, how long until the first key, mix-ups, and the schedule before and after. "I got it right" adds a line pointing at the answer it overrules. It's there to tune the scheduler to your memory later.
- **Stats** at the bottom of the pane shows, in place of the card: words seen and learnt (remembered three weeks or more), the streak of days with answers, how many were right in the last 7 days, the words due on each of the next 7 days, and each lesson's progress.
- While words are due, their number shows to the right of the clock; a click opens the pane.
- **Games** at the bottom of the pane (on by default; `qs ipc call vocab toggleGames`): a Steam game's window (its process has Steam's `SteamGameId`, or its class is `steam_app_…`; Steam itself never) moves to a hidden workspace as it opens, and a full-screen card asks a word first, as the lock does: a wrong answer shows the right one to type out, then another word, until one is right, with an emergency button after a minute. Then the game comes back where it opened, and its other windows pass until it's closed.
- While words are due for review, a notification says how many (clicking it opens the pane), at most every three hours (`notifyEvery` in `config/Config.qml`, 0 for none) and not while you're practising.
- **Lock asks** at the bottom of the pane: after the right password, the lock screen asks for a word too. A wrong answer shows the right one to type out, then another word, until you get one right. After a minute an emergency button unlocks without it. With no words it isn't asked. When none is due, it asks one of the words you've seen that is due soonest; answering it early barely changes when it comes back, so unlocking often doesn't push words away.
- Over IPC: `qs ipc call vocab` with `toggleLock`, `toggleBothWays`, `toggleRandom` (also `setLock`, `setBothWays`, `setRandom` with true or false, and `lockEnabled`, `bothWays`, `random`), `add "word" "translation"`, `stats`, `hardWords`.

**Timers**
- In the launcher, `=` followed by a time starts a timer: `=10m`, `=1h30 tea`, `=90s pasta`. The soonest counts down left of the clock (with how many more run); clicking it asks "Cancel?", clicking again cancels it. When one ends, a sound plays and a notification stays until dismissed. Timers outlast a restart. Also `qs ipc call timers start "25m focus"`, `list`, `cancel`.

**Updates**
- With `services.moqs.updates.flake` set to your system flake (and `.host` to its `nixosConfigurations` name, if that isn't the hostname), the shell checks every six hours how far its locked nixpkgs is behind its branch on GitHub (from the branch's commit feed, not GitHub's API, so it doesn't use up the 60 API requests an hour nix needs for `github:` inputs; `github:` and `git+https://github.com/…` inputs both work). From three days behind, a snowflake and the days show in the bar; clicking it opens the update's details.
- The details sit behind the control centre's Updates tile: how far behind nixpkgs is (your locked date and the branch's newest), the update running or last run with its steps (inputs, build, switch) and how long it took, the inputs it moved with their dates, the packages whose version changes (from `nix store diff-closures` between the running and the new system), and, when it failed, its last lines of output. **Check** looks again, **Log** opens the whole log.
- **Update now** there (clicked twice, as it takes a while) runs `nix flake update`, builds the system as you, and then asks for your password once to switch to it, as `nixos-rebuild switch` does. Its progress shows in the tile, the bar and the details, and a notification says how it went. It runs as its own systemd user unit (`moqs-update`, log in `$XDG_RUNTIME_DIR/moqs-update.log`), so the shell restarting into the new system doesn't stop it. Only files git knows about are built, as with any flake. Also `qs ipc call updates update`, `check`, `status`.

**Password requests**
- The shell is the polkit agent: when something asks for an administrator's password (`pkexec`, the update, mounting a disk), a pane with a password field grows out of the middle of the bar, where the control centre does. Enter answers, Escape or Cancel refuses. Another agent already running (polkit-gnome, hyprpolkitagent) keeps the job instead.

**Lock screen**
- `qs ipc call session lock` locks the session: the time, a password field, the weather, the next lesson, homework due soon or the next exam, and what's playing (with its controls). Only your password unlocks it; there's no IPC unlock.
- A pane grows out of the bar over the screen first, like the launcher, and shrinks back into it after unlocking. `qs ipc call session lockNow` locks at once, without it: use that before suspending, where there may be no time for the animation.
- Bind it to a key, or let hypridle use it: `general { lock_cmd = qs ipc call session lock; before_sleep_cmd = qs ipc call session lockNow }`.
- `qs ipc call session menu` opens the session menu, a pane out of the bar like the launcher: lock, suspend, log out, restart and power off. Arrows or Tab move, Enter or the first letter picks (`o` for log out), Escape closes. Log out, restart and power off ask "Sure?" first: pick them twice. Bind it to a key, e.g. Super+Escape.
- After the password it can ask for a word as well (see Vocabulary).
- The password is checked through PAM with the `login` service; `lock.pamService` (or `"lock": { "pam": "swaylock" }` in `settings.json`) picks another.

**Corners and panels**

| Where | What | How to open |
|---|---|---|
| Top right | Notification popups and the notification centre | Popups appear on their own; push the pointer into the corner for the centre |
| Top centre | App launcher: type to search installed apps (the ones you start most come first), Matrix rooms and recent files; Enter or click to start or open one, ↑/↓ or Tab to move, Esc or a click elsewhere to close. A first character switches mode: `=` calculates (`=sqrt(2)*3,5`) and converts units (`=5 km in mi`, `=100 F to C`, `=2^10 MiB in GB`; Enter copies), `!` runs a command (Shift+Enter in a terminal, `$TERMINAL` or kitty), `>` controls Home Assistant (`>desk lamp` toggles, `>desk lamp off`, `>desk lamp 40` dims, `>heater 21` sets a thermostat, `>lights off` turns all lights off; sensors' Enter copies the value; results come by kind: lights, vacuums, switches, sensors, media players, buttons and values, the rest, then cameras, whose Enter shows their picture, a new frame every second, until Esc or Enter), `?` searches the web or opens an address, `:` finds an emoji to copy (`:joy`), `;` practises vocabulary (see below), `/` lists recent files, `@` sends a Matrix message (`@lena see you at 8`; the room's name, or the start of it, then the message; without one Enter opens the room), `,` lists open windows by title or app, the last used first and the one in focus last, so Enter alone goes back to the previous window (Enter goes to the one picked, on whatever workspace; Shift+Enter brings it to the workspace shown; Ctrl+Delete closes it, and the launcher stays open for the next), `#` searches nixpkgs and starts a package with `nix run nixpkgs#…` (Shift+Enter in a terminal; unfree ones allowed; `#` alone lists the ones started before that are still in the store, until the garbage collector removes them; the index of `nix search nixpkgs ^` is kept in `$XDG_CACHE_HOME/moqs/nixpkgs.json` and rebuilt after three days, which takes a minute after a nixpkgs update) In every mode, ↑ in the empty field brings back what was run before (`=…`, `>…`, `!…` and the rest, kept in `$XDG_STATE_HOME/moqs/launcher-history.json`), ↓ goes forward again | `qs ipc call launcher toggle` (also `open`, `close`); bind it to a key in Hyprland |
| Top centre | Workspace overview: this monitor's workspaces with live pictures of their windows; click a window to go to it, a workspace to go there, drag a window onto another workspace to move it | Right-click the workspace dots, or `qs ipc call overview toggle` (also `open`, `close`) |
| Top centre | Control centre: Wi-Fi, Bluetooth, AirDrop and power profile tiles with lists, night light (hyprsunset from sunset to sunrise where the weather is; a click turns it on or off until the next one), the audio visualizer (cava, as bars along the bottom border while something plays; its chevron sets how high they reach), clipboard history, Capture (a click dims the screen to pick what to take: click a window, drag a region, or press Space for the whole screen, Esc to give up; its chevron also has the screen or the active window at once, and recording a picked window or region or the screen; while recording, the tile or the red dot left of the clock stops it; saved to `~/Pictures/Screenshots`, screenshots also copied; **Copy text** reads the text in a picked window or region with tesseract and copies it, in the languages of `services.moqs.capture.ocrLanguages`, English and German by default; `qs ipc call capture screenshot|text|record pick|screen|window`), Updates (see below), volume with output picker, brightness, now playing | Click the clock |
| Top centre | Displays: plugging in a display grows a panel out of the bar that asks how to use it, side by side (drag the displays into place; they snap edge to edge) or mirrored (click the one the others show), with the resolution and scale of the display clicked. Applied through `hyprctl`, and undone after 15 seconds unless kept, so a mode that doesn't work can't leave you stuck. A kept setup is remembered for that set of displays (in `$XDG_STATE_HOME/moqs/displays.json`) and restored next time they're plugged in, with a notification offering to rearrange | Plugging in a display, or `qs ipc call displays open` (also `close`) |
| Bottom left | Navidrome music player, playing through mpv | Push the pointer into the corner |
| Bottom right | Matrix client with end-to-end encryption through gomuks | Push the pointer into the corner |
| Bottom centre | Dashboard: WebUntis timetable and homework, weather, Home Assistant | Drag the bottom border up |

- **Notifications:** action buttons, history in the notification centre, and timers that pause while hovered.
- **AirDrop** (via [Owly](https://github.com/t4t5/owly)):
  - Receive on/off.
  - Accept/decline prompts for incoming transfers.
  - A nearby-devices list. Clicking a device opens a drop zone; files dropped there get sent to it.
  - The name others see is the host name, unless `airdrop.name` (Nix option, or `airdrop.json`) sets another.
- **Wi-Fi:** connect and disconnect from the list, with a password field for new secured networks.
- **Bluetooth:** connect, disconnect and pair.
- **Clipboard history** (via [cliphist](https://github.com/sentriz/cliphist)): the shell records what you copy while it runs, text and images. The Clipboard tile lists it newest first with image thumbnails. Type to search, click or press Enter to copy an entry back, ↑/↓ to move, × to remove one, the bin to clear everything. Copies that password managers mark as sensitive aren't kept.
- **Music:** search, album lists (new, random, most played), queueing a whole album from any track, seeking. Plays are reported back to Navidrome. The player shows up over MPRIS as "Navidrome", so `playerctl -p mpv` and media keys control it.
- **Matrix:** room list with avatars and unread counts, conversations, sending with Markdown, older history on scroll. Invites show on top of the room list with Accept and Deny. Chips above the list narrow it to Discord, Signal, Telegram, WhatsApp or plain Matrix rooms. Rooms bridged from Discord, Signal, Telegram or WhatsApp get that network's icon on their avatar, going by their members' IDs (`@discord_…`, `@signalbot`, …). Right-click a room to rename it just for you: Enter saves, an empty name goes back to the room's own. These names are kept in `$XDG_STATE_HOME/moqs/matrix-names.json`.
- **Timetable** (WebUntis): today's lessons until the last one is over, then the next day that has lessons. The lesson running now is highlighted, and cancelled or changed lessons are marked. Back-to-back lessons with the same subject, teacher, room and notes show as one long lesson. Arrows in the header browse other school days; reopening the dashboard goes back. Cancelled lessons are red; lessons in rooms listed in `cancelledRooms` count as cancelled. The coming two weeks are checked every two minutes, and a notification lists what changed on a day (cancelled, added, moved, new room or teacher), also for changes made while the shell wasn't running.
- **Homework:** WebUntis homework and your own, by due date: red when due today or overdue, orange for tomorrow, yellow within three days. Tick any of them off. To add one, type its subject (a short name from `subjects`, or the WebUntis name), the task and optionally a date, e.g. `Eng S. 42 bis 21.11.`: subject and date are picked out and shown under the field before you press Enter. Dates can be `21.11.`, `21.11.2026`, `2026-11-21`, today/heute, tomorrow/morgen, übermorgen or a weekday; without one, the subject's next lesson sets it. Your own entries and ticks are kept in a plain text file (`$XDG_STATE_HOME/moqs/homework.txt` by default), one per line as `[ ] 2026-11-21 | Englisch | S. 42`, so you can edit it by hand too.
- **Exams:** below the homework, a smaller list of upcoming exams from WebUntis and your own, with a countdown coloured by how close they are (red within two days, orange within a week, yellow within two weeks). Hover the countdown for the date. Each has a slider for how far your learning is: drag, click or scroll it, in steps of 5%. Add your own by starting the homework field with `exam:`, e.g. `exam: M Kurvendiskussion 3.12.`; × removes it. Own exams and progress are kept in the homework file as `[exam 40%] 2026-12-03 | Mathematik | Kurvendiskussion`.
- **Weather** (from [Open-Meteo](https://open-meteo.com), no API key): now, the coming hours, and the week with each day's range. Set a place name, a GeoNames ID or coordinates.
- **Home Assistant:** a card laid out the way `hass.json` says: switches and lights (with a brightness slider when they dim), scene and script buttons, single values, and blocks of values side by side. It updates every few seconds while the dashboard is open.

Panels close once the pointer leaves them. Clicking the music or Matrix corner while its panel is open goes back to that panel's start page.

Each corner can instead be pulled out like the dashboard: drag from the top-right corner downwards, or from the bottom corners upwards. A panel pulled out at least 30% of the way stays open. Set this per corner with `dragToOpen` (Nix option, or `settings.json` next to `shell.qml`):

```json
{ "dragToOpen": { "notifications": false, "music": true, "matrix": true } }
```

The same file sets the launcher's web search (Nix option `launcher.searchEngine`), with `%s` for the query:

```json
{ "launcher": { "search": "https://www.startpage.com/do/search?q=%s" } }
```

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

    webuntis = {
      enable = true;
      url = "https://mese.webuntis.com"; # your school's WebUntis server
      school = "Example-School";         # the school= part of the login page's URL
      username = "me";
      passwordCommand = "pass show webuntis";
    };

    weather = {
      enable = true;
      location = "Frankfurt, DE"; # or a GeoNames ID like "2925533", or "50.11,8.68"
    };

    vocab.mnemonics = {
      enable = true;
      url = "http://localhost:11434/v1"; # any OpenAI-compatible API, before /chat/completions
      model = "llama3.1:8b";
      apiKeyCommand = "pass show llm"; # or apiKeyFile; leave both out if the server needs no key
      language = "German"; # what the mnemonics are written in
    };

    hass = {
      enable = true;
      url = "http://homeassistant.local:8123";
      tokenCommand = "pass show hass"; # or tokenFile; a long-lived access token
      sections = [
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
      ];
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
    # navidrome = { … }; matrix = { … }; webuntis = { … }; weather = { … }; hass = { … }; vocab.mnemonics = { … }; as above
  };
}
```

Don't put `homeManagerModules.default` in a NixOS module list. It stops with an error telling you to use `nixosModules.default` instead.

### What the module does

- Turns on `programs.quickshell`, started from `hyprland-session.target`. Change the target with `services.moqs.systemdTarget`.
- Installs the shell to `~/.config/quickshell`, together with `settings.json`, `airdrop.json`, `navidrome.json`, `matrix.json`, `webuntis.json`, `weather.json`, `hass.json` and `mnemonics.json` generated from your settings.
- Installs the programs the shell runs:
  - always: `brightnessctl`, `cliphist`, `curl`, `libnotify` and `wl-clipboard`
  - with Navidrome enabled: `mpv`, plus [mpv-mpris](https://github.com/hoyon/mpv-mpris) loaded into the shell's own mpv
  - with Matrix enabled: `gomuks-web`, plus a user service to run it (turn the service off with `matrix.gomuks.enable = false`)

Passwords never go into the Nix store. Give exactly one of `passwordFile` (read at runtime) or `passwordCommand` (its first output line is used).

Other settings you'd rather keep out of the store too can come from files read at runtime, such as sops-nix or agenix secrets: `urlFile` and `usernameFile` for Navidrome, Matrix and WebUntis, `webuntis.schoolFile` and `weather.locationFile`, each instead of the plain setting. The shell runs as you, so these files (and `passwordFile`s) have to be readable by you: with sops-nix, give the secrets `owner = "<you>";`. When one isn't readable, the panel says so.

### Options

| Option | Default | |
|---|---|---|
| `enable` | `false` | Enable the shell |
| `systemdTarget` | `"hyprland-session.target"` | Target that starts it |
| `user` | (none) | NixOS module only: whose Home Manager gets the shell |
| `dragToOpen.notifications` / `music` / `matrix` | `false` | Pull that corner's panel out of the border instead of opening it on hover |
| `launcher.searchEngine` | `"https://duckduckgo.com/?q=%s"` | Web search for the launcher's `?`; `%s` is the query |
| `lock.pamService` | `"login"` | PAM service the lock screen checks passwords with |
| `capture.ocrLanguages` | `[ "eng" "deu" ]` | Languages "Copy text" reads (tesseract's codes); only these are installed |
| `updates.flake` | `null` | Your system flake (a local path) for the Updates tile; without it the tile and the bar's indicator are hidden |
| `updates.host` | `null` | The `nixosConfigurations` name to build; the hostname without it |
| `greeter.enable` | `false` | NixOS module only: the login screen through greetd (see [Login screen](#login-screen)) |
| `greeter.package` | `pkgs.quickshell` | NixOS module only: the Quickshell it runs |
| `airdrop.name` | `null` | Name others see for AirDrop; `null` means the host name |
| `navidrome.enable` | `false` | Configure the music panel |
| `navidrome.url` | (none) | Navidrome server URL |
| `navidrome.username` | (none) | Navidrome username |
| `navidrome.passwordFile` / `passwordCommand` | `null` | Where the password comes from |
| `matrix.enable` | `false` | Configure the Matrix panel |
| `matrix.url` | `"http://localhost:29325"` | gomuks web address |
| `matrix.username` | (none) | gomuks web username |
| `matrix.passwordFile` / `passwordCommand` | `null` | gomuks web password |
| `matrix.gomuks.enable` | `true` | Run gomuks-web as a user service |
| `webuntis.enable` | `false` | Configure the timetable and homework widgets |
| `webuntis.url` | (none) | WebUntis server, e.g. `https://mese.webuntis.com` |
| `webuntis.school` | (none) | School name (`school=` in the login page's URL) |
| `webuntis.username` | (none) | WebUntis username |
| `webuntis.passwordFile` / `passwordCommand` | `null` | WebUntis password |
| `webuntis.cancelledRooms` | `[]` | Rooms whose lessons show as cancelled, e.g. `[ "Eva" ]` |
| `webuntis.subjects` | `[]` | Short names for new homework, e.g. `[ { name = "Eng"; untis = "Englisch"; } ]` |
| `webuntis.homeworkFile` | `null` | Your own homework and ticks; `null` means `$XDG_STATE_HOME/moqs/homework.txt` |
| `weather.enable` | `false` | Configure the weather widget |
| `weather.location` | (none) | Place name (`"Frankfurt, DE"`), GeoNames ID or `"latitude,longitude"` |
| `hass.enable` | `false` | Configure the Home Assistant widget |
| `hass.url` | (none) | Home Assistant URL |
| `hass.tokenFile` / `tokenCommand` | `null` | Long-lived access token (profile page → Security) |
| `hass.sections` | `[]` | What the card shows; see [Home Assistant card](#home-assistant-card) |
| `vocab.server` | `null` | The moqs-vocab server the vocabulary lives on, e.g. `http://worker-03` |
| `vocab.mnemonics.enable` | `false` | Mnemonics for hard vocabulary words from a language model (`vocab.aids` still works) |
| `vocab.mnemonics.url` | (none) | OpenAI-compatible API, e.g. `http://localhost:11434/v1` |
| `vocab.mnemonics.model` | (none) | Model to ask |
| `vocab.mnemonics.apiKeyFile` / `apiKeyCommand` | `null` | API key, if the server needs one |
| `vocab.mnemonics.language` | `""` | Language of the mnemonics; empty: the translations' |
| `vocab.mnemonics.prepareModel` | `""` | Model for suggestions prepared ahead for often-missed words; empty: `model` |

### Login screen

The NixOS module can also replace SDDM, GDM or LightDM with a login screen in the lock screen's style: the time, who logs in (arrows switch users), the password field, and the session to start underneath. It lists every session NixOS has installed, so Hyprland, GNOME (`services.desktopManager.gnome.enable`), Steam (`programs.steam.gamescopeSession.enable`), Plasma and the rest all show up; X11 sessions start through `startx` when `services.xserver.enable` is on. Suspend, restart and power off sit in the corner, and the weather shows when `services.moqs.weather` is set up (with a `location`; a `locationFile` that only you can read stays hidden from the login screen). The last user and session are remembered; until then it starts on `services.displayManager.defaultSession`, e.g. `"hyprland"`. It types with your `services.xserver.xkb` keyboard layout.

```nix
{
  imports = [ inputs.moqs.nixosModules.default ];

  services.moqs.greeter.enable = true;
  # The login screen replaces the display manager:
  services.displayManager.sddm.enable = false;
}
```

It doesn't need the Home Manager part. Under the hood it's greetd running Quickshell (`greeter.qml`) in [cage](https://github.com/cage-kiosk/cage). If the login screen fails to start, switch to another TTY (Ctrl+Alt+F2) to log in and fix it.

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

## Home Assistant card

The card shows the `sections` of `hass.json` (or `services.moqs.hass.sections`) from top to bottom. The token is a long-lived access token from your Home Assistant profile page, under Security.

```json
"sections": [
  { "type": "toggle", "entity": "light.mo" },
  { "type": "sensors", "title": "Energy", "entities": [
    { "entity": "sensor.foxess_pvenergytotal", "name": "Produced", "icon": "mdi:solar-power" },
    { "entity": "sensor.foxess_load", "name": "Used", "icon": "mdi:home-lightning-bolt" },
    "sensor.batterie"
  ] },
  { "type": "button", "title": "Scenes", "entities": ["scene.movie", "script.good_night"] }
]
```

| `type` | Shows |
|---|---|
| `toggle` | Switches entities on and off. Lights that dim get a brightness slider; click its icon to switch |
| `button` | Runs a scene or script, or presses a button |
| `sensor` | One value per row |
| `sensors` | Several values side by side in one block |

Each section takes one `entity` or a list of `entities`, plus an optional `title`. An entity is its ID, or `{ "entity", "name", "icon" }`. Name and icon default to Home Assistant's own. Icons are [Material Design Icons](https://pictogrammers.com/library/mdi/) names like `"mdi:solar-power"`, looked up in `assets/mdi.json` (generated from the Nerd Font). Battery sensors without an icon of their own show their charge.

## Developing

Run the shell straight from a checkout; Quickshell reloads it when files change:

```sh
qs -p ./shell.qml
```

Without the Nix module, put the panel settings next to `shell.qml`. These files are gitignored:

```jsonc
// airdrop.json: the name others see (default: the host name)
{ "name": "Mo's Laptop" }

// navidrome.json
{ "url": "https://music.example.com", "username": "me", "password": "…" }

// matrix.json
{ "url": "http://localhost:29325", "username": "gomuks", "password": "…" }

// webuntis.json ("cancelledRooms", "subjects" and "homeworkFile" are optional)
{
  "url": "https://mese.webuntis.com", "school": "Example-School", "username": "me", "password": "…",
  "cancelledRooms": ["Eva"],
  "subjects": [{ "name": "Eng", "untis": "Englisch" }, { "name": "Mathe", "untis": "Mathematik" }]
}

// weather.json: a place name, a GeoNames ID ("2925533") or "latitude,longitude"
{ "location": "Frankfurt, DE" }

// mnemonics.json: mnemonics for vocabulary; "apiKey" or "apiKeyCommand" if the server needs one
{ "url": "http://localhost:11434/v1", "model": "llama3.1:8b", "language": "German" }

// hass.json: the card's layout is described below
{
  "url": "http://homeassistant.local:8123",
  "token": "…",
  "sections": [{ "type": "toggle", "entity": "light.mo" }]
}
```

The logins accept `"passwordCommand"` instead of `"password"`, and `hass.json` `"tokenCommand"` instead of `"token"`. Any of `"url"`, `"username"`, `"school"` and `"location"` can instead be `"urlFile"`, `"usernameFile"`, … naming a file whose first line is the value. For MPRIS (playerctl) on the music player, link in mpv-mpris; restart the shell's mpv afterwards if it is already running:

```sh
nix build .#mpv-mpris -o mpv-mpris
```

For the vocabulary's sound-alike words (mnemonic suggestions), link in the word list the package has:

```sh
nix build .#german-words -o german-words.txt
```

Sizes, colours and fonts live in `config/Config.qml`.

```
shell.qml        entry point: one frame per screen
config/          Config singleton: sizes, colours, fonts
modules/         Frame, bar, notifications, control centre, music, matrix, dashboard
services/        Notifications, Owly, Navidrome, mpv player, Matrix, WebUntis, weather, Home Assistant, brightness, CPU/RAM
nix/             package, Home Manager and NixOS modules
```

Quickshell's file watcher stops following a file that gets replaced, for example by `sed -i`. Edit files in place, or restart `qs` when changes stop showing up.
