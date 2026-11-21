# Design

Why gs-match is shaped the way it is. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## One call moves the match, and everything is counted in ticks

`GSMatch.tick(current_tick)` is the only thing that advances anything. There is no `Timer`, no `_process`, no `Time.get_ticks_msec`. A match that ticks itself ticks on whatever schedule the engine gives it, which is not the schedule the simulation runs on, and a server whose round clock and netcode disagree about the time produces a round that ends on a different tick for every client. The corollary is that a match is testable without a frame rendered: the self-test runs a two-round series in synchronous calls.

## `GSMatchRules` is what the mode is; `GSMatchConfig` is how the server runs it

Swapping the rules changes the game; changing the config does not. That is why `min_players` and `pause_when_empty` are both on the rules: a threshold in one file and the decision about what to do at it in another is the split that left the match stuck in `COUNTDOWN` ([history](history.md#pause_when_empty-was-read-off-the-wrong-object)). Two settings that mean nearly the same thing are worse than either alone, which is why `GSMatchConfig.run_when_empty` was removed.

## Ordering is never left to a dictionary

Every place two things could be equal has an explicit tie-break:

| Decision | Tie-break | Why |
| --- | --- | --- |
| `GSScoreboard.ranked` | player key | Otherwise players visibly swap places on a client |
| `GSSpawnSelector.choose` | node name | A symmetric map ties on nearly every point |
| `GSTeamManager.smallest_team` | lower team id | Server and client must agree who is on which side |
| `GSTeamManager._balance_candidate` | player key | Two machines must move the same person |
| `GSRespawnQueue.take_ready` | sorted keys | Decides who gets the good spawn when several return together |
| `GSScoreboard.leading_team` | lower team id | Same reason as assignment |

Team assignment is the one where the consequence is not cosmetic: a server and client that disagree about someone's team disagree about friendly fire, which is a player who cannot damage the enemy and can damage their own side.

## Kills go through one method

`report_kill` takes an empty `killer_key` for a world death and an equal one for a suicide. Both go through it, because every caller would otherwise have to work out which case it is, and the one that gets it wrong credits a kill to nobody. `GSKillFeed.add_kill` accepts a null killer for the same reason: "killed by someone who has already disconnected" is a normal event, and a null dereference if not handled centrally.

**A kill outside `LIVE` records the death, scores nothing, and does not re-run the win check.** A kill during warmup would let the first player to connect farm the second; a kill during intermission (a rocket already in the air) would re-run a win check on a round that is over.

**A kill in `LIVE` can end the round before `report_kill` returns.** It runs the win check at once, so the kill that reaches the score limit or eliminates the last of a side emits `round_ended` and the state change synchronously, inside the call. A caller that does more afterwards (a second kill from the same explosion, a stats row, its own respawn) re-checks `is_live()`: the second of two simultaneous kills is reported outside `LIVE` and does not score. That is correct (the first decided the round) and is documented at the method rather than changed, because deferring the check decides a round a tick late.

## One warmup, then a frozen countdown before every round

`WARMUP` is the one open wait, entered by `start()` and by falling below `min_players`. Warmup, `INTERMISSION` and `MATCH_END` (when `min_players` are still present; otherwise the match restarts into warmup) all lead to `COUNTDOWN`, because a second warmup after a match the same players just played, or a round that began with everyone standing wherever they died, was the "counts down three times" the flow replaced.

Entering `COUNTDOWN` is the round's start in every way but the clock: `round_number` increments, scores and the feed reset, spawn points reset, teams rebalance, `round_preparing(round_number)` is emitted and every present player is queued for this tick and placed (`respawn_due`). `round_number` increments here and `round_started` repeats the same number at `LIVE`, where nobody is respawned. `countdown_sec` of 0 skips all of this and starts the round live with the placing after `round_started`, so a game that lays its round out in that handler (most of them) is unchanged. A countdown that loses its players hands the number back and returns to warmup.

Freezing is the game's job: `is_frozen()` (state is `COUNTDOWN` and `rules.freeze_during_countdown`) and `freeze_changed(frozen)` say when. A join or a death during the countdown is placed at once, so it is frozen too. A client needs only the replicated `net_state` plus its own copy of the rules to know it is frozen. `begin_round_now` (a map change) still skips the countdown: it goes live and places everyone right after `round_started`, as before, because its caller builds the map in that handler.

Four details a game must know. `players_released(tick)` fires just before `round_started` when a countdown ends: spawn protection granted when players were placed during the freeze runs out inside it (2 s of protection in a 5 s countdown), so a game re-arms it there for everyone placed while `is_frozen()` was true, for `spawn_protection_ticks()` from that tick (or grants none while frozen). `begin_round_now` during a countdown goes live on the round already prepared, with no second reset, number or placement. `stop()` in a countdown hands the round number back and clears the respawn queue. On the wire, `GSMatchNetSync` replicates `net_frozen` (1 bit, appended last, so older bridges that never declare it keep their format) and `GSMatchNetSync.is_frozen(source)` answers from replicated data only; against an older server without the field it treats every countdown as frozen. With `pause_when_empty` off a countdown runs to LIVE whoever is present.

## Ending a round clears the respawn queue

A player who died on the round-winning kill must not reappear during the intermission. The self-test asserts exactly two respawns across three kills for this reason, and its comment says so, because "3 kills, 2 respawns" reads as an off-by-one otherwise.

## Autobalance runs between rounds, not during them

`GSMatchConfig.balance_between_rounds` calls it at round start. Switching someone mid-fight takes a player who was winning a duel and puts them on the other side of it.

`GSTeamManager.balance_grace_ticks` is the second half: being switched right after switching is the most annoying thing an autobalancer does, and two joins in a row can produce it. `rebalance` is bounded rather than `while not is_balanced()`: a team at `max_players` with everyone inside their grace period is permanently unbalanceable, and an unbounded loop would hang the server between rounds.

`_balance_candidate` picks the **longest-serving** player on the oversized team, not the newest: the newest is the one most likely to have just been assigned there.

## Spawn selection gives up gracefully

`GSSpawnSelector._fallback` runs when every point is on cooldown, occupied or tagged for another team, and spawns someone anyway. **Spawning badly beats not spawning**: the alternative is a player who stays dead until a point frees up, which on a busy map with a short round is the rest of the match. The fallback count is in `describe()`, so a map with too few points is visible rather than merely felt.

Threats are **enemies only**, filtered by `GSMatch._threats_against`. A selector that avoided the whole roster would scatter a team across the map; in a free-for-all, team 0 makes everyone an enemy, which is right there.

**Spawn points are added, removed and cleared through the match**: `add_spawn_point`, `remove_spawn_point`, `clear_spawn_points`. `spawn_points()` returns the match's own array, not a copy, because callers already hold it, but it is not a mutation interface: a game once cleared that array by reference on every map load, which works only while the return is not a copy. A level built at runtime frees its own nodes and calls `clear_spawn_points()`; the match never owned them.

**A freed point is forgotten, never walked.** With no `spawns_ref` the match collects every `GSSpawnPoint` under the current scene, which in a process holding two games includes the other one's. Every path that walks the list (`_begin_round`'s reset, `choose_spawn`, `spawn_points()`) drops freed points first (`_forget_freed_spawns`); a game that knows where its points are still sets `spawns_ref`. ([history](history.md#a-freed-spawn-point-crashed-the-engine))

## The replicated clock is an absolute end tick

`GSMatchNetSync` sends `net_ends_at`, not seconds remaining. A relative value would have to be re-sent every tick to stay accurate; an absolute end tick goes out once per state change, and every client counts down from the clock it already shares with the server (GameSpice Net's). `seconds_remaining` returns -1 for "no clock" on both server and client, so a HUD has one branch.

## Coupling: nothing is imported

GameSpice Match names no class outside GameSpice Core: not GameSpice Combat, GameSpice Net, GameSpice Server or GameSpice Loadout.

- `GSMatchNetSync` describes what to replicate as data, with type names as strings, which a bridge resolves with `GSNetVar.Type[spec.type]`.
- Being alive is GameSpice Combat's `GSHealth`, so `GSRulesElimination` takes an `alive_fn`. Unwired, it logs a warning and falls back to score and clock, visible in the first round played, which is the point.
- Where a player is comes from `GSMatch.position_fn`.
- `GSTeamManager.team_lookup()` returns exactly the `Callable` that GameSpice Combat's `GSDamageResolver.team_of` wants, without either project naming the other.
- Nothing here spawns anything. `respawn_due` carries a `GSSpawnPoint`; the game spawns, because what a player *is* is not GameSpice Match's business.

The `GSModule` that binds a match to a GameSpice Server belongs in the game (game-fatal-contact's `fc_module.gd` is one): GameSpice Server is not a dependency, and the bridge that forwards joins, leaves and deaths is about forty lines.

## Deliberately not here

- **Objectives.** `report_objective` carries a named counter and adds to a team score, which is the shared half. Control points, bombs, payloads and flags are [GameSpice Objective](../../gs-objective)'s, which does not import gs-match; its `score_fn` is where a game connects the two.
- **Map rotation and votes.** GameSpice Map (`GSMapRotation`) and GameSpice Vote own what plays next. A match that also rotated maps would be a second, competing owner of what is loaded. `min_players` and the warmup clock are what GameSpice Match contributes to readiness.
- **Assist attribution.** `report_assist` exists and scores; deciding *who* assisted needs a damage history with a time window, which is gs-combat's `GSDamage` stream plus a game's own policy.
- **Persisted stats.** The scoreboard is per match and `GSScoreboard.reset_match` drops absent records. Anything that outlives a match is GameSpice Stats or GameSpice User.
- **A HUD.** `describe_lines()` is what a console command dumps; the scoreboard as a Control is GameSpice Menu's `GSMenuScoreboard`, and other HUD pieces belong in GameSpice UI.
