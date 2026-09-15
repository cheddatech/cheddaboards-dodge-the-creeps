extends Node

@export var mob_scene: PackedScene
var score

# --- CheddaBoards leaderboard panel (built in code) ---
var _board_layer: CanvasLayer
var _board_rows: VBoxContainer
var _board_title: Label
var _name_input: LineEdit
var _awaiting_board := false   # set at game over; board renders once the profile answers

func _ready() -> void:
	# --- CheddaBoards credentials (managed by Setup Wizard) ---
	CheddaBoards.set_api_key("cb_your-game_xxxxxxxxx")
	CheddaBoards.set_game_id("your-game")
	# --- end CheddaBoards credentials ---
	CheddaBoards.score_submitted.connect(_on_cb_score_submitted)
	CheddaBoards.score_error.connect(_on_cb_score_error)
	CheddaBoards.leaderboard_loaded.connect(_on_cb_leaderboard_loaded)
	CheddaBoards.nickname_changed.connect(_on_cb_nickname_changed)
	CheddaBoards.nickname_error.connect(_on_cb_nickname_error)
	CheddaBoards.profile_loaded.connect(_on_cb_profile_loaded)
	CheddaBoards.no_profile.connect(_on_cb_no_profile)
	CheddaBoards.debug_logging = true  # dev only — nice while testing
	_build_leaderboard_panel()
	await CheddaBoards.wait_until_ready()
	CheddaBoards.login_anonymous()  # Guest; pass a nickname later if you like
	CheddaBoards.refresh_profile()  # learn our server-side nickname for highlighting

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
		# Offline / not logged in — still show whatever we can fetch.
		CheddaBoards.get_leaderboard("score", 10)

func new_game():
	_hide_leaderboard()
	get_tree().call_group(&"mobs", &"queue_free")
	score = 0
	$Player.start($StartPosition.position)
	$StartTimer.start()
	$HUD.update_score(score)
	$HUD.show_message("Get Ready")
	$Music.play()


func _on_MobTimer_timeout():
	# Create a new instance of the Mob scene.
	var mob = mob_scene.instantiate()

	# Choose a random location on Path2D.
	var mob_spawn_location = get_node(^"MobPath/MobSpawnLocation")
	mob_spawn_location.progress = randi()

	# Set the mob's direction perpendicular to the path direction.
	var direction = mob_spawn_location.rotation + PI / 2

	# Set the mob's position to a random location.
	mob.position = mob_spawn_location.position

	# Add some randomness to the direction.
	direction += randf_range(-PI / 4, PI / 4)
	mob.rotation = direction

	# Choose the velocity for the mob.
	var velocity = Vector2(randf_range(150.0, 250.0), 0.0)
	mob.linear_velocity = velocity.rotated(direction)

	# Spawn the mob by adding it to the Main scene.
	add_child(mob)

func _on_ScoreTimer_timeout():
	score += 1
	$HUD.update_score(score)


func _on_StartTimer_timeout():
	$MobTimer.start()
	$ScoreTimer.start()


# ============================================================
# CheddaBoards
# ============================================================

func _on_cb_score_submitted(submitted: int, _streak: int) -> void:
	print("CheddaBoards: score %d submitted" % submitted)
	# Learn our server-side name first (a first submit gets assigned one,
	# e.g. Player_2371), THEN render the board - so our row highlights even
	# before we've picked a name. The profile handlers below fetch the board.
	CheddaBoards.get_player_profile()

func _on_cb_profile_loaded(nickname: String, _score: int, _streak: int, _achievements: Array, _play_count: int) -> void:
	if not _name_input.text.length() and nickname != "":
		_name_input.placeholder_text = "Playing as %s" % nickname
	if _awaiting_board:
		_awaiting_board = false
		CheddaBoards.get_leaderboard("score", 10)

func _on_cb_no_profile() -> void:
	# Brand-new player (or the profile read lagging a fresh account) -
	# show the board anyway; the highlight catches up next time.
	if _awaiting_board:
		_awaiting_board = false
		CheddaBoards.get_leaderboard("score", 10)

func _on_cb_score_error(reason: String) -> void:
	push_warning("CheddaBoards submit failed: " + reason)
	# Submit failed — show the board anyway.
	CheddaBoards.get_leaderboard("score", 10)

func _on_cb_leaderboard_loaded(entries: Array) -> void:
	# Clear previous rows.
	for child in _board_rows.get_children():
		child.queue_free()

	if entries.is_empty():
		_add_board_row("No scores yet — be the first!", "", false)
	else:
		# Entries: { rank, nickname, score, streak, authType } — no player ID,
		# so we match ourselves by our server-side nickname (via refresh_profile).
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

func _on_cb_set_name_pressed() -> void:
	var wanted := _name_input.text.strip_edges()
	if wanted.is_empty():
		return
	CheddaBoards.change_nickname(wanted)

func _on_cb_nickname_changed(new_name: String) -> void:
	# The server may suffix on collision (e.g. Name_1) - show what came back.
	_name_input.text = ""
	_name_input.placeholder_text = "Playing as %s" % new_name
	CheddaBoards.get_leaderboard("score", 10)  # refresh so the new name shows

func _on_cb_nickname_error(reason: String) -> void:
	_name_input.text = ""
	_name_input.placeholder_text = reason

func _add_board_row(left_text: String, right_text: String, highlight: bool) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.text = left_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var score_label := Label.new()
	score_label.text = right_text
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if highlight:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))

	row.add_child(name_label)
	row.add_child(score_label)
	_board_rows.add_child(row)

func _build_leaderboard_panel() -> void:
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 10
	_board_layer.visible = false
	add_child(_board_layer)

	var panel := PanelContainer.new()
	# Top-centre so the HUD's Start button (lower half) stays clickable.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.offset_left = -150
	panel.offset_right = 150
	panel.offset_top = 70
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	_board_title = Label.new()
	_board_title.text = "Top Dodgers"
	_board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_board_title)

	_board_rows = VBoxContainer.new()
	_board_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_board_rows)

	# Name entry - set/change your board name (3-16 chars, letters/numbers/_).
	# These two controls keep the default mouse filter so they're clickable;
	# everything else in the panel ignores the mouse so the HUD stays usable.
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Set your name"
	_name_input.max_length = 16
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_submitted.connect(func(_text): _on_cb_set_name_pressed())
	name_row.add_child(_name_input)

	var name_button := Button.new()
	name_button.text = "Set name"
	name_button.pressed.connect(_on_cb_set_name_pressed)
	name_row.add_child(name_button)

func _hide_leaderboard() -> void:
	_board_layer.visible = false
