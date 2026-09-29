<p align="center">
  <img src="assets/cheddaboards-logo.png" alt="CheddaBoards" width="360">
</p>

<h1 align="center">Dodge the Creeps × CheddaBoards</h1>

<p align="center">
  The official Godot demo game with a real online leaderboard — added in one script file, nothing to host.<br>
  <a href="https://cheddagames.itch.io/dodge-the-creeps-x-cheddaboards"><strong>▶ Play it in your browser</strong></a> ·
  <a href="https://cheddaboards.com">cheddaboards.com</a> ·
  <a href="https://docs.cheddaboards.com/engines/godot-4">Docs</a> ·
  <a href="https://github.com/cheddatech/cheddaboards-godot-addon">Addon</a> ·
  <a href="https://store.godotengine.org/asset/cheddatech/cheddaboards">Godot Asset Store</a>
</p>

<p align="center">
  <img src="assets/hero-leaderboard.png" alt="Dodge the Creeps title screen showing the Top Dodgers leaderboard with the player's entry highlighted in gold and a Set name field below the board" width="420">
</p>

Every Godot developer has built [Dodge the Creeps](https://docs.godotengine.org/en/stable/getting_started/first_2d_game/index.html). It's the official "your first 2D game" tutorial: dodge the mobs, watch your score tick up, die, restart. What it doesn't have is any reason to play twice.

This repo fixes that. The game submits every run to an online leaderboard and shows the top 10 at game over — with your own entry highlighted in gold. All the changes live in one file (`Main.gd`), and there's no backend to build: no server, no database, no per-player fees.

**Three ways to use this repo:**

- **Just play it.** [Live on itch.io](https://cheddagames.itch.io/dodge-the-creeps-x-cheddaboards), no download. Die, see the board, set a name.
- **Clone and run it.** Open the project in Godot 4.3+, add your own free API key (Step 2 below), play. The addon is included.
- **Read it as a tutorial.** The walkthrough below is the full integration, gotchas included. The commit history is deliberate: the first commit is vanilla Dodge the Creeps, the second adds the addon, the third is the integration — so `git show` on that third commit shows you *exactly* what an integration touches. It isn't much.

---

## Step 1 — Install the CheddaBoards addon

*(Already done in this repo — this is what you'd do in your own game.)*

Get the addon from the [Godot Asset Store](https://store.godotengine.org/asset/cheddatech/cheddaboards) or the [addon repo](https://github.com/cheddatech/cheddaboards-godot-addon) (the [Godot quick start](https://docs.cheddaboards.com/quickstart/godot) covers this same setup). You'll end up with an `addons/cheddaboards/` folder in your project root:

```
your-project/
├── addons/
│   └── cheddaboards/
│       ├── CheddaBoards.gd
│       ├── SetupWizard.gd
│       ├── plugin.cfg
│       └── ...
├── Main.tscn
├── Main.gd
└── ...
```

Then enable it: **Project → Project Settings → Plugins**, tick **CheddaBoards**. Enabling the plugin automatically registers the `CheddaBoards` autoload — that singleton is how your scripts talk to the service.

Run the game once before changing anything. It should play exactly as before; the addon sits quietly until you call it.

## Step 2 — Get your API key

Head to the [CheddaBoards dashboard](https://cheddaboards.com), create a game (this project expects one called `dodge-test`, but any name works), and copy its API key:

```
cb_your-game_xxxxxxxxxx
```

The middle section is your game ID — the SDK extracts it automatically, so the key is the only thing you copy.

## Step 3 — Run the Setup Wizard

Open `addons/cheddaboards/SetupWizard.gd` in the script editor and run it with **File → Run** (Ctrl/Cmd+Shift+X).

<p align="center">
  <img src="assets/setup-wizard.png" alt="The CheddaBoards Setup Wizard dialog in the Godot editor, showing the API key field, the auto-detected game ID, and the target script it will write to" width="640">
</p>

The wizard checks the autoload, then asks for your API key. It shows the game ID it detected and — importantly — which script it's about to write to. In Dodge the Creeps that's `Main.gd`, the root script of the main scene. Hit Save and it inserts a marked block at the top of `_ready()`:

```gdscript
	# --- CheddaBoards credentials (managed by Setup Wizard) ---
	CheddaBoards.set_api_key("cb_your-game_xxxxxxxxxx")
	CheddaBoards.set_game_id("your-game")
	# --- end CheddaBoards credentials ---
```

Re-run the wizard any time (say, to swap keys) — it replaces the block in place rather than duplicating it.

> **Gotcha #1: check your Inspector exports after the wizard runs.**
> The wizard edits `Main.gd` on disk while the editor has it open, and Godot's script hot-reload can occasionally reset exported property values on open scenes. In Dodge the Creeps that's the **Mob Scene** slot on the Main node — if your next run crashes with *"Cannot call method 'instantiate' on a null value"*, select the Main node and re-assign `mob.tscn` to the empty Mob Scene property. Thirty-second fix, and it only happens once.

## Step 4 — Log in and submit scores

Dodge the Creeps keeps everything we need in `Main.gd`: the `score` variable and a `game_over()` function that runs when you die. We log in once at startup, then submit on every game over.

In `_ready()`, after the wizard's credentials block:

```gdscript
	CheddaBoards.score_submitted.connect(_on_cb_score_submitted)
	CheddaBoards.score_error.connect(_on_cb_score_error)
	CheddaBoards.leaderboard_loaded.connect(_on_cb_leaderboard_loaded)
	CheddaBoards.nickname_changed.connect(_on_cb_nickname_changed)
	CheddaBoards.nickname_error.connect(_on_cb_nickname_error)
	CheddaBoards.profile_loaded.connect(_on_cb_profile_loaded)
	CheddaBoards.no_profile.connect(_on_cb_no_profile)
	CheddaBoards.debug_logging = true  # dev only — remove before shipping
	_build_leaderboard_panel()
	await CheddaBoards.wait_until_ready()
	CheddaBoards.login_anonymous()
	CheddaBoards.refresh_profile()
```

Two things worth understanding:

**Anonymous login needs no sign-up.** `login_anonymous()` identifies the player by a persistent device ID the SDK generates and stores in `user://` — the same player keeps the same identity across sessions without typing anything. If they don't choose a name, the server assigns one automatically (this project's test player came back as `Player_1248`). Want players to pick? `login_anonymous("Chedz")` — that's the whole upgrade.

**`refresh_profile()` fetches the player's server-side profile**, including that auto-assigned nickname. We use it later to spot the player's own row on the board.

Then in `game_over()`:

```gdscript
func game_over():
	$ScoreTimer.stop()
	$MobTimer.stop()
	$HUD.show_game_over()
	$Music.stop()
	$DeathSound.play()
	_awaiting_board = true
	if CheddaBoards.is_authenticated():
		CheddaBoards.submit_score(score)
	else:
		CheddaBoards.get_leaderboard("score", 10)
```

Logged in → submit. Login failed somehow → skip straight to fetching, so the player still sees a board.

## Step 5 — Fetch the board at the right moment

Here's the pattern that trips people up. Don't submit and fetch at the same time — the fetch can win the race, and the player stares at a board that doesn't include the run they just finished.

Fetch **in response to the submit confirmation** instead — and fetch your *profile* before the board. A first submit is what creates your player server-side (and assigns that `Player_NNNN` name), so learning the name first is what lets the board highlight your row on the very first game over:

```gdscript
func _on_cb_score_submitted(submitted: int, _streak: int) -> void:
	# Learn our server-side name first, THEN render the board -
	# the profile handlers below do the fetching.
	CheddaBoards.get_player_profile()

func _on_cb_profile_loaded(nickname: String, _score: int, _streak: int, _achievements: Array, _play_count: int) -> void:
	if not _name_input.text.length() and nickname != "":
		_name_input.placeholder_text = "Playing as %s" % nickname
	if _awaiting_board:
		_awaiting_board = false
		CheddaBoards.get_leaderboard("score", 10)

func _on_cb_no_profile() -> void:
	# Brand-new player whose profile hasn't landed yet - show the
	# board anyway; the highlight catches up next game over.
	if _awaiting_board:
		_awaiting_board = false
		CheddaBoards.get_leaderboard("score", 10)

func _on_cb_score_error(reason: String) -> void:
	push_warning("CheddaBoards submit failed: " + reason)
	# Submit failed — show the board anyway.
	CheddaBoards.get_leaderboard("score", 10)
```

Submit → confirmed → profile → fetch → display. Your new score is always on the board you're looking at, with your own row lit up. (`_awaiting_board` is just a one-line flag set in `game_over()` so a routine profile refresh at the title screen doesn't pop the board open.)

## Step 6 — Display it

The addon deliberately ships no UI — your game's look is your business. For Dodge the Creeps we build a small panel in code: a `CanvasLayer` holding a `PanelContainer`, one row per entry. The full code is in [`Main.gd`](Main.gd) (functions `_build_leaderboard_panel`, `_on_cb_leaderboard_loaded`, `_add_board_row`, `_hide_leaderboard`, plus the name entry: `_on_cb_set_name_pressed`, `_on_cb_nickname_changed`, `_on_cb_nickname_error`) — the interesting parts:

Entries come back as dictionaries — `{ rank, nickname, score, streak }` — with the rank already computed server-side:

```gdscript
func _on_cb_leaderboard_loaded(entries: Array) -> void:
	for child in _board_rows.get_children():
		child.queue_free()

	if entries.is_empty():
		_add_board_row("No scores yet — be the first!", "", false)
	else:
		var my_nick: String = CheddaBoards.get_nickname()
		for entry in entries:
			var nickname: String = str(entry.get("nickname", "")).strip_edges()
			if nickname.is_empty():
				nickname = "Guest"
			var entry_score := int(entry.get("score", 0))
			var entry_rank := int(entry.get("rank", 0))
			var is_me: bool = my_nick != "" and nickname == my_nick
			_add_board_row("%d. %s" % [entry_rank, nickname], str(entry_score), is_me)

	_board_layer.visible = true
```

The gold highlight compares each entry's nickname to your own — which is why Step 4 called `refresh_profile()` and Step 5 fetches the profile again after your first submit: without those, the SDK doesn't know the server named you `Player_1248`, and nothing lights up.

The board hides again when a new run starts — first line of `new_game()` calls `_hide_leaderboard()`.

> **Gotcha #2: `mouse_filter = MOUSE_FILTER_IGNORE` on every panel node.**
> Dodge the Creeps restarts via the HUD's Start button. An invisible Control sitting over it will silently eat the click and the game will feel broken. Every node in the leaderboard panel ignores mouse input, so clicks pass straight through to the HUD underneath — except the two name-entry controls below, which need clicks and keep the default filter.

### Let players pick their name

The bottom row of the panel is a `LineEdit` and a **Set name** button. The whole feature is one SDK call:

```gdscript
func _on_cb_set_name_pressed() -> void:
	var wanted := _name_input.text.strip_edges()
	if wanted.is_empty():
		return
	CheddaBoards.change_nickname(wanted)
```

`nickname_changed` comes back with the name the server actually stored — if someone else owns `Costa`, you might get `Costa_1`, so always display what the signal gives you rather than what was typed. The demo puts it in the field's placeholder ("Playing as Costa") and re-fetches the board so the renamed, highlighted row appears immediately. Validation failures (too short, bad characters) arrive on `nickname_error` with a human-readable reason.

## Step 7 — Die gloriously

Run the game. Dodge badly. When you hit a creep, watch the Output panel:

<p align="center">
  <img src="assets/verify-output.png" alt="The Godot editor showing game_over() code alongside the Output panel logging a successful score submission followed by the leaderboard request" width="800">
</p>

```
[CheddaBoards] Submitting: score=5, streak=0, nickname=(unset), gameId=dodge-test, ...
[CheddaBoards] Score submission successful: 5 points, 0 streak
[CheddaBoards] Player profile requested for: dev_...
[CheddaBoards] Leaderboard requested (sort: score, limit: 10)
```

…and the panel appears with your name in gold. Check your dashboard — the score is there too. That's a complete online leaderboard: persistent identity, score submission, a live top-10 with your row highlighted, and player-chosen names — 174 added lines, all in one modified file.

---

## Where to go from here

- **Keep their identity forever** — anonymous players can upgrade to a full account later (device-code login) without losing their scores or their name.
- **Daily and weekly boards** — `get_daily_leaderboard()` and `get_weekly_leaderboard()` work exactly like the fetch above, with automatic resets at calendar boundaries. Instant "come back tomorrow" energy for an arcade game.
- **Harden against cheaters** — for anything competitive, look at [anti-cheat in the docs](https://docs.cheddaboards.com/concepts/anti-cheat): the server validates that scores came from a plausible play session rather than a hand-crafted HTTP request.
- **A note on API keys** — the key ends up inside your shipped game, so treat it as identifying, not secret. Anyone can find it, which is exactly why score submission runs through CheddaBoards' rate-limited validation layer rather than trusting the client. Play sessions (above) tighten this further.

## Licenses & attribution

- Integration code and the CheddaBoards SDK: **MIT** © CheddaTech Ltd — see [LICENSE](LICENSE).
- Dodge the Creeps is from the official [Godot demo projects](https://github.com/godotengine/godot-demo-projects) (**MIT** © Godot Engine contributors); art and audio assets carry their original licenses — see [THIRD_PARTY.md](THIRD_PARTY.md).

Built and maintained by a solo dev - if you ship something with a board in it, [tell me](https://cheddaboards.com). I want to lose to strangers in your game.