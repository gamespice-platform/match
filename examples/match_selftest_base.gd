extends Node

## Shared counters, assertions and fixtures for the dot-match self-test. Split out of match_selftest.gd for file size.

const TICK_RATE := 60

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


# --- Assertions ------------------------------------------------------------

func _section(title: String) -> void:
	_entered += 1
	_group(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s — %s" % [what, detail])
		print("  FAIL  %s%s" % [what, "" if detail == "" else " — " + detail])
	return condition


func _close(a: float, b: float, what: String, epsilon: float = 0.01) -> bool:
	return _check(absf(a - b) <= epsilon, what, "%.3f vs %.3f" % [a, b])


func _group(title: String) -> void:
	print("")
	print("%s" % title)


# --- Fixtures --------------------------------------------------------------

func _make_match(rules: DotMatchRules, with_teams: bool = false) -> DotMatch:
	var node := DotMatch.new()
	node.register_service = false
	node.rules = rules
	node.config = DotMatchConfig.new()
	node.config.tick_rate = TICK_RATE
	node.config.auto_start = false
	node.config.log_transitions = false
	node.config.idle_seconds = 0.0

	if with_teams:
		var manager := DotTeamManager.new()
		manager.teams = DotTeam.standard_pair()
		node.teams = manager
		node.add_child(manager)

	add_child(node)
	return node


func _quick_rules(limit: int = 3) -> DotMatchRules:
	var rules := DotMatchRules.deathmatch(limit)
	rules.warmup_sec = 1.0
	rules.countdown_sec = 0.5
	rules.time_limit_sec = 10.0
	rules.min_players = 2
	rules.respawn_delay_sec = 0.5
	rules.intermission_sec = 1.0
	rules.match_end_sec = 1.0
	return rules


## Runs the match forward, one tick at a time, from [param from] for [param ticks].
func _advance(node: DotMatch, from: int, ticks: int) -> int:
	for offset in range(ticks):
		node.tick(from + offset)
	return from + ticks


func _make_spawns(count: int, spacing: float = 10.0) -> Array[DotSpawnPoint]:
	var out: Array[DotSpawnPoint] = []

	for index in range(count):
		var point := DotSpawnPoint.make(Vector3(float(index) * spacing, 0.0, 0.0))
		point.name = "Spawn%02d" % index
		point.cooldown_ticks = 60
		add_child(point)
		out.append(point)

	return out


func _free_spawns(points: Array[DotSpawnPoint]) -> void:
	for point in points:
		point.queue_free()
		remove_child(point)
