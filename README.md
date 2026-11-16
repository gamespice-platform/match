The match loop for a Godot 4 multiplayer game: warmup, rounds, scoring, teams, spawning and respawning. Everything is counted in ticks and driven by one call, so a server's round clock and its netcode agree on what time it is. It needs only [dot-core](https://github.com/gamespice-platform/core). Part of TMC's open source **Gamespice** collection (MIT licence).

> Built with Claude Code. Every addon has a headless test suite and the suites pass, but little of this has met real players yet. Please report rough edges.

## Install

Copy `addons/dot_match/` and `addons/dot_core/` into your project and enable both under **Project > Project Settings > Plugins**.

## Use

```gdscript
var match_node := DotMatch.new()
match_node.rules = DotMatchRules.deathmatch(30)
match_node.position_fn = func(key): return player_position(key)
add_child(match_node)

match_node.respawn_due.connect(func(key, spawn, tick):
    spawn_player(key, spawn.spawn_transform())
)

# Once per simulated tick, on the server.
match_node.tick(tick)

# When someone dies.
match_node.report_kill(killer_key, victim_key, &"rifle", tick, headshot)
```

## How a match runs

A match is a state machine: `WARMUP`, `COUNTDOWN`, `LIVE`, `INTERMISSION`, `MATCH_END`. One call, `tick()`, moves it. There is no `Timer`, no `_process` and no wall clock. A match that ticks itself runs on the engine's schedule, not the simulation's, and a round timer and a netcode that disagree produce a round that ends on a different tick for every client.

- **Warmup** is the only open wait. It runs on `start()` and whenever the server drops below `min_players`.
- **Countdown** comes before every other round. The round resets, every present player is placed at a round spawn (`respawn_due`) and held still. `is_frozen()` is true for exactly this state when `rules.freeze_during_countdown` is on, `freeze_changed(frozen)` announces the changes, and `round_started` fires at `LIVE` without respawning anyone. dot-match owns no bodies, so your game freezes its controllers.

What winning means lives in a `DotMatchRules` resource. `DotMatch` never asks which mode it runs.

## What is in it

| Piece | What it does |
| --- | --- |
| `DotMatch` | The state machine: rounds, clocks, respawns and the win check. |
| `DotMatchRules` | What winning means and what a kill is worth. Presets `deathmatch(limit)` and `team_deathmatch(limit)`; subclass for a new mode. |
| `DotRulesElimination` | A worked subclass: the round ends when one side is wiped out. |
| `DotScoreboard`, `DotPlayerScore` | Who is playing and how they are doing. Survives reconnects. |
| `DotTeam`, `DotTeamManager` | Sides, assignment and deterministic autobalance. |
| `DotKillFeed` | The last few kills as data, not formatted strings. |
| `DotSpawnPoint`, `DotSpawnSelector` | Where a player appears, and why that point. |
| `DotRespawnQueue` | Who is waiting to come back, counted against a target tick. |
| `DotMatchNetSync` | What to replicate, without naming a dot-net type. |

## Settings

### Rules (`DotMatchRules`, one per mode)

| Setting | Default | What it does |
| --- | --- | --- |
| `score_limit` | 30 | Score that ends the match. 0 = no limit. |
| `time_limit_sec` | 600 | Match length in seconds. 0 = no limit. |
| `rounds_to_win` | 1 | Rounds a side needs to win the match. |
| `kill_points` | 1 | Points per kill. |
| `suicide_points` | -1 | Points for a suicide. |
| `friendly_points` | -1 | Points for killing a team-mate. |
| `assist_points` | 0 | Points per assist. |
| `friendly_kills_count` | false | Whether team kills count toward the team score. |
| `respawn_delay_sec` | 3.0 | Seconds before a dead player returns. |
| `respawn_disabled` | false | No respawns until the round ends. |
| `spawn_protection_sec` | 2.0 | Seconds of protection after spawning. |
| `warmup_sec` | 30 | Warmup length. |
| `min_players` | 2 | Players needed to leave warmup. |
| `countdown_sec` | 5 | Frozen countdown before each round. |
| `freeze_during_countdown` | true | Hold players still during the countdown. |
| `intermission_sec` | 10 | Pause between rounds. |
| `match_end_sec` | 20 | Pause at the end of a match. |
| `pause_when_empty` | true | Drop back to warmup when players fall below `min_players`. Turn off for scheduled matches and tests with no players. |
| `team_based` | false | Whether the mode has sides. |

### Server (`DotMatchConfig`)

Layered like every Gamespice config: defaults, JSON file, `DOT_MATCH_*` environment, `--match-*` command line.

| Setting | Default | What it does |
| --- | --- | --- |
| `tick_rate` | 64 | Must match whatever calls `tick()`. Durations are converted with it. |
| `auto_start` | true | Start warmup as soon as the node is ready. |
| `balance_between_rounds` | true | Rebalance teams at round start only, never mid-fight. |
| `idle_seconds` | 180 | Seconds of doing nothing before a player is marked idle. 0 = off. dot-match only marks them; what to do is dot-server's policy. |
| `respawn_delay_sec` | -1 | Replaces the rules' value when 0 or more. |
| `respawn_disabled` | -1 | -1 keeps the rules' value, 0 respawns, 1 does not. |
| `friendly_points` | -101 | Replaces the rules' value when -100 or more. |
| `log_transitions` | true | Log every state change at info level. |

## Three problems it is built around

- **A scoreboard that rewards rage-quitting.** Records are keyed by a stable player key, never a peer id, so a reconnecting player gets their kills back and the next player to join does not inherit someone else's.
- **Two machines that disagree.** Every ordering has an explicit tie-break: scoreboards fall back to the player key, spawn selection to the node name, team assignment to the lower team id, respawn batches to a sort. Dictionary order would make a server and client disagree, which for team assignment means disagreeing about friendly fire.
- **A round that never ends.** `DotRulesElimination` treats zero teams standing as the end of the round. A grenade that kills the last player on both sides would otherwise leave a server waiting for a side that no longer exists.

## Spawning

The default picks the available point furthest from the nearest enemy. Only enemies count as threats, because spawning away from your own team scatters a squad. Points have a cooldown so two players do not spawn inside each other. When every point is on cooldown or occupied, the selector falls back and spawns someone anyway, since a player who stays dead until a point frees up is worse than a bad spawn.

## More

[docs/design.md](docs/design.md) explains the choices and [docs/history.md](docs/history.md) lists bugs worth recognising if they return.

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/match_selftest.tscn
```

All offline. Exits non-zero on any failure.

## Licence

MIT. See [LICENSE](LICENSE).
