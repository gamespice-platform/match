@tool
extends EditorPlugin

## Editor entry point for GameSpice Match. Registers inspector types only.
##
## No autoload, for the family's reason: a process may run two matches at once — which
## is what this project's own self-test does — and a singleton match makes that
## impossible. [GSMatch] registers itself in [GSRegistry] instead.

const _ICON := "res://addons/gs_match/icon_placeholder.svg"

const _TYPES := [
	[
		"GSMatch",
		"Node",
		"res://addons/gs_match/gs_match.gd",
	],
	[
		"GSScoreboard",
		"Node",
		"res://addons/gs_match/core/gs_scoreboard.gd",
	],
	[
		"GSTeamManager",
		"Node",
		"res://addons/gs_match/core/gs_team_manager.gd",
	],
	[
		"GSKillFeed",
		"Node",
		"res://addons/gs_match/core/gs_kill_feed.gd",
	],
	[
		"GSSpawnPoint",
		"Node3D",
		"res://addons/gs_match/spawn/gs_spawn_point.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
