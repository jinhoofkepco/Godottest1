using Godot;
using GArray = Godot.Collections.Array;
using GDictionary = Godot.Collections.Dictionary;
using System;

public partial class BattleSimulation
{
    public int RunHeadlessTicks(int requestedTicks)
    {
        int count = Math.Clamp(requestedTicks, 0, BattleConfig.SimTickRate * 30);
        int executed = 0;
        float delta = 1f / BattleConfig.SimTickRate;
        while (executed < count && _result.Length == 0)
        {
            FixedStep(delta);
            executed++;
        }
        _events.Clear();
        _hitCount = _shotCount = _deathCount = 0;
        return executed;
    }

    public GDictionary GetDebugSnapshot()
    {
        var buildings = BuildBuildingsSnapshot();
        return new GDictionary
        {
            ["unit_count"] = _unitCount,
            ["ally_unit_count"] = _teamUnitCounts[TeamAlly],
            ["enemy_unit_count"] = _teamUnitCounts[TeamEnemy],
            ["ally_income_multiplier"] = PopulationIncomeMultiplier(TeamAlly),
            ["enemy_income_multiplier"] = PopulationIncomeMultiplier(TeamEnemy) * AiIncomeMultiplier(),
            ["ai_income_level"] = _aiIncomeLevel,
            ["unit_ids"] = Copy(_ids, _unitCount),
            ["unit_teams"] = Copy(_teams, _unitCount),
            ["unit_kinds"] = Copy(_kinds, _unitCount),
            ["unit_states"] = Copy(_states, _unitCount),
            ["unit_target_ids"] = Copy(_targetIds, _unitCount),
            ["unit_positions"] = Copy(_positions, _unitCount),
            ["unit_velocities"] = Copy(_velocities, _unitCount),
            ["unit_hp"] = Copy(_hp, _unitCount),
            ["unit_cooldowns"] = Copy(_cooldowns, _unitCount),
            ["unit_lunge_timers"] = Copy(_lungeTimers, _unitCount),
            ["unit_lunge_directions"] = Copy(_lungeDirections, _unitCount),
            ["unit_cached_waiting"] = Copy(_cachedWaiting, _unitCount),
            ["unit_shield_modes"] = Copy(_shieldModes, _unitCount),
            ["unit_stuck_timers"] = Copy(_stuckTimers, _unitCount),
            ["unit_recovery_active"] = Copy(_recoveryActive, _unitCount),
            ["unit_recovery_targets"] = Copy(_recoveryTargets, _unitCount),
            ["unit_legion_ids"] = Copy(_legionIds, _unitCount),
            ["unit_rally_ids"] = Copy(_rallyPointIds, _unitCount),
            ["unit_slot_offsets"] = Copy(_slotOffsets, _unitCount),
            ["legion_count"] = _legionCount,
            ["legion_ids"] = Copy(_legionRecordIds, _legionCount),
            ["legion_teams"] = Copy(_legionTeams, _legionCount),
            ["legion_states"] = Copy(_legionStates, _legionCount),
            ["legion_formations"] = Copy(_legionFormations, _legionCount),
            ["legion_anchors"] = Copy(_legionAnchors, _legionCount),
            ["legion_headings"] = Copy(_legionHeadings, _legionCount),
            ["legion_member_counts"] = Copy(_legionLiveCounts, _legionCount),
            ["legion_rally_ids"] = Copy(_legionRallyIds, _legionCount),
            ["legion_defending"] = Copy(_legionDefending, _legionCount),
            ["buildings"] = buildings,
            ["ownership"] = (byte[])_ownership.Clone(),
            ["elevation"] = (byte[])_elevation.Clone(),
            ["blocked"] = (byte[])_blocked.Clone(),
            ["water"] = (byte[])_water.Clone(),
            ["ally_gold"] = _allyGold,
            ["enemy_gold"] = _enemyGold,
            ["ally_hq_id"] = _allyHqId,
            ["enemy_hq_id"] = _enemyHqId,
            ["ally_occupancy"] = _allyOccupancy,
            ["enemy_occupancy"] = _enemyOccupancy,
            ["time_remaining"] = _timeRemaining,
            ["result"] = _result,
            ["decision_group_cursor"] = _decisionCursor,
            ["decision_refresh_count"] = _decisionRefreshCount,
            ["territory_update_count"] = _territoryUpdateCount,
            ["navigation_recovery_count"] = _navigationRecoveryCount,
            ["target_candidate_checks"] = _targetCandidateChecks,
            ["aoe_candidate_checks"] = _aoeCandidateChecks,
            ["siege_impacts_resolved"] = _siegeImpactsResolved,
            ["enemy_ai_decisions"] = _aiDecisions[TeamEnemy],
            ["enemy_ai_builds"] = _aiBuilds[TeamEnemy],
            ["enemy_ai_failed_searches"] = _aiFailedSearches[TeamEnemy],
            ["enemy_ai_forced_spends"] = _aiForcedSpends[TeamEnemy],
            ["enemy_ai_max_gold"] = _aiMaxGold[TeamEnemy],
            ["enemy_ai_last_reason"] = _aiLastReasons[TeamEnemy],
            ["ally_ai_decisions"] = _aiDecisions[TeamAlly],
            ["ally_ai_builds"] = _aiBuilds[TeamAlly],
            ["ally_ai_failed_searches"] = _aiFailedSearches[TeamAlly],
            ["ally_ai_forced_spends"] = _aiForcedSpends[TeamAlly],
            ["ally_ai_max_gold"] = _aiMaxGold[TeamAlly],
            ["ally_ai_last_reason"] = _aiLastReasons[TeamAlly],
        };
    }

    public GDictionary GetProfileSnapshot()
    {
        return new GDictionary
        {
            ["tick_count"] = _profileTickCount,
            ["tick_usec"] = _profileTickUsec,
            ["worst_tick_usec"] = _profileWorstTickUsec,
            ["target_usec"] = _profileTargetUsec,
            ["separation_usec"] = _profileSeparationUsec,
            ["territory_usec"] = _profileTerritoryUsec,
            ["event_usec"] = _profileEventUsec,
            ["snapshot_usec"] = _profileSnapshotUsec,
            ["gc_gen0"] = GC.CollectionCount(0),
            ["gc_gen1"] = GC.CollectionCount(1),
            ["gc_gen2"] = GC.CollectionCount(2),
        };
    }

    public GDictionary GetConfigSnapshot() => new()
    {
        ["grid_columns"] = BattleConfig.GridColumns,
        ["grid_rows"] = BattleConfig.GridRows,
        ["sim_tick_rate"] = BattleConfig.SimTickRate,
        ["territory_update_interval"] = BattleConfig.TerritoryUpdateInterval,
        ["decision_group_count"] = BattleConfig.DecisionGroupCount,
        ["siege_range"] = UnitAttackRange(UnitSiege, Vector2.Zero),
        ["siege_damage"] = UnitAttackDamage(UnitSiege),
        ["match_duration"] = BattleConfig.MatchDuration,
        ["occupancy_win_ratio"] = BattleConfig.OccupancyWinRatio,
        ["passive_income_per_second"] = BattleConfig.PassiveIncomePerSecond,
        ["hq_max_hp"] = BattleConfig.HqMaxHp,
        ["ranged_hp"] = UnitMaxHp(UnitRanged),
        ["dragon_hp"] = UnitMaxHp(UnitDragon),
        ["dragon_damage"] = UnitAttackDamage(UnitDragon),
        ["spawner_production_interval"] = ProductionInterval(UnitMelee),
        ["siege_production_interval"] = ProductionInterval(UnitSiege),
        ["dragon_production_interval"] = ProductionInterval(UnitDragon),
        ["melee_production_batch"] = ProductionBatch(UnitMelee),
        ["ranged_production_batch"] = ProductionBatch(UnitRanged),
        ["siege_production_batch"] = ProductionBatch(UnitSiege),
        ["dragon_production_batch"] = ProductionBatch(UnitDragon),
        ["siege_min_range"] = _settings.SiegeMinRange,
        ["siege_blast_radius"] = _settings.SiegeBlastRadius,
        ["rally_point_cost"] = BattleConfig.RallyPointCost,
        ["rally_launch_size"] = BattleConfig.RallyLaunchSize,
        ["rally_defense_capacity"] = BattleConfig.RallyDefenseCapacity,
        ["legion_max_members"] = BattleConfig.LegionMaxMembers,
        ["team_unit_cap"] = BattleConfig.TeamUnitCap,
        ["ai_income_level"] = _aiIncomeLevel,
    };

    public void SetAiIncomeLevel(int level) => _aiIncomeLevel = Math.Clamp(level, BattleConfig.AiIncomeLevelMin, BattleConfig.AiIncomeLevelMax);
    public int GetAiIncomeLevel() => _aiIncomeLevel;
    public float GetIncomeMultiplier(int team) => PopulationIncomeMultiplier(team) * (team == TeamEnemy ? AiIncomeMultiplier() : 1f);

    public bool ApplyDebugCommand(GDictionary command)
    {
        string op = DString(command, "op");
        switch (op)
        {
            case "spawn_unit":
                {
                    int team = DInt(command, "team", TeamAlly);
                    int kind = DInt(command, "kind", UnitMelee);
                    Vector2 position = DVector2(command, "position", new Vector2(BattleConfig.GridColumns * 0.5f, BattleConfig.GridRows * 0.5f));
                    int id = SpawnUnit(team, position, kind, -1, default, DBool(command, "bypass_cap", false));
                    if (id == 0) return false;
                    if (DBool(command, "exact", false)) _positions[_indexById[id]] = position;
                    return true;
                }
            case "spawn_legion":
                return CreateDebugLegion(
                    DInt(command, "team", TeamAlly),
                    command.TryGetValue("template", out Variant templateVariant) ? templateVariant.AsGodotDictionary() : PresetTemplate(0),
                    DInt(command, "formation", FormationLine),
                    DVector2(command, "anchor", new Vector2(BattleConfig.GridColumns * 0.5f, BattleConfig.GridRows * 0.5f)));
            case "spawn_stress":
                return SpawnStressFixture(Math.Clamp(DInt(command, "count", 600), 0, MaxUnits), true);
            case "spawn_capped_stress":
                return SpawnStressFixture(Math.Clamp(DInt(command, "count", 600), 0, BattleConfig.TeamUnitCap * 2), false);
            case "clear_units":
                _unitCount = 0;
                Array.Clear(_teamUnitCounts);
                Array.Clear(_shieldModes);
                Array.Clear(_stuckTimers);
                Array.Clear(_recoveryActive);
                Array.Clear(_progressOrigins);
                Array.Clear(_recoveryTargets);
                ResetLegions();
                Array.Fill(_indexById, -1);
                _nextUnitId = 1;
                RebuildBuckets();
                return true;
            case "add_building":
                {
                    int id = AddBuildingInternal(DInt(command, "team", TeamAlly), DInt(command, "kind", BuildingSpawner), DVector2I(command, "cell", Vector2I.Zero), DInt(command, "unit_kind", UnitMelee));
                    if (id != 0) RebuildFlowFields();
                    return id != 0;
                }
            case "set_unit":
                {
                    int index = ResolveUnit(command);
                    if (index < 0) return false;
                    if (command.ContainsKey("position"))
                    {
                        _positions[index] = DVector2(command, "position", _positions[index]);
                        _progressOrigins[index] = _positions[index];
                        _stuckTimers[index] = 0f;
                        _recoveryActive[index] = 0;
                    }
                    if (command.ContainsKey("velocity")) _velocities[index] = DVector2(command, "velocity", _velocities[index]);
                    if (command.ContainsKey("hp")) _hp[index] = DFloat(command, "hp", _hp[index]);
                    if (command.ContainsKey("cooldown")) _cooldowns[index] = DFloat(command, "cooldown", _cooldowns[index]);
                    if (command.ContainsKey("state")) _states[index] = DInt(command, "state", _states[index]);
                    if (command.ContainsKey("target_id")) _targetIds[index] = DInt(command, "target_id", _targetIds[index]);
                    if (command.ContainsKey("lunge_timer")) _lungeTimers[index] = DFloat(command, "lunge_timer", _lungeTimers[index]);
                    if (command.ContainsKey("lunge_direction")) _lungeDirections[index] = DVector2(command, "lunge_direction", _lungeDirections[index]);
                    if (command.ContainsKey("shield_mode")) _shieldModes[index] = DBool(command, "shield_mode", _shieldModes[index] != 0) ? (byte)1 : (byte)0;
                    if (command.ContainsKey("cached_waiting")) _cachedWaiting[index] = DBool(command, "cached_waiting", _cachedWaiting[index] != 0) ? (byte)1 : (byte)0;
                    if (command.ContainsKey("stuck_timer")) _stuckTimers[index] = DFloat(command, "stuck_timer", _stuckTimers[index]);
                    if (command.ContainsKey("progress_origin")) _progressOrigins[index] = DVector2(command, "progress_origin", _progressOrigins[index]);
                    if (command.ContainsKey("recovery_active")) _recoveryActive[index] = DBool(command, "recovery_active", _recoveryActive[index] != 0) ? (byte)1 : (byte)0;
                    if (command.ContainsKey("recovery_target")) _recoveryTargets[index] = DVector2(command, "recovery_target", _recoveryTargets[index]);
                    return true;
                }
            case "set_elevation":
                {
                    byte[] values = command.TryGetValue("values", out Variant variant) ? variant.AsByteArray() : Array.Empty<byte>();
                    if (values.Length != BattleConfig.CellCount) return false;
                    Array.Copy(values, _elevation, values.Length);
                    _terrain.Elevation = _elevation;
                    _boardVersion++;
                    RebuildFlowFields();
                    return true;
                }
            case "set_ownership":
                {
                    byte[] values = command.TryGetValue("values", out Variant variant) ? variant.AsByteArray() : Array.Empty<byte>();
                    if (values.Length != BattleConfig.CellCount) return false;
                    bool changed = false;
                    for (int i = 0; i < values.Length; i++)
                    {
                        if (_ownership[i] == values[i]) continue;
                        _ownership[i] = values[i];
                        QueueOwnershipDelta(i);
                        changed = true;
                    }
                    if (changed) _boardVersion++;
                    RecalculateTerritory(false, true);
                    return true;
                }
            case "force_ownership_delta":
                {
                    int[] indices = command.TryGetValue("indices", out Variant indexVariant) ? indexVariant.AsInt32Array() : Array.Empty<int>();
                    int[] owners = command.TryGetValue("owners", out Variant ownerVariant) ? ownerVariant.AsInt32Array() : Array.Empty<int>();
                    if (indices.Length == 0 || indices.Length != owners.Length) return false;
                    bool changed = false;
                    for (int i = 0; i < indices.Length; i++)
                    {
                        int cellIndex = indices[i];
                        int owner = owners[i];
                        if (cellIndex < 0 || cellIndex >= BattleConfig.CellCount || (owner != TeamEnemy && owner != TeamAlly)) return false;
                        if (_ownership[cellIndex] == owner) continue;
                        _ownership[cellIndex] = (byte)owner;
                        QueueOwnershipDelta(cellIndex);
                        changed = true;
                    }
                    if (changed) _boardVersion++;
                    return changed;
                }
            case "set_gold":
                _allyGold = DInt(command, "ally", _allyGold);
                _enemyGold = DInt(command, "enemy", _enemyGold);
                return true;
            case "set_enemy_ai": SetAiEnabled(TeamEnemy, DBool(command, "enabled", true)); return true;
            case "set_ai": SetAiEnabled(DInt(command, "team", TeamEnemy), DBool(command, "enabled", true)); return true;
            case "set_ai_income_level": SetAiIncomeLevel(DInt(command, "level", BattleConfig.AiIncomeLevelDefault)); return true;
            case "set_seed":
                _rng.Seed = (ulong)Math.Max(1, DInt(command, "value", 731942));
                _aiUpdateCursor = (DInt(command, "value", 731942) & 1) == 0 ? TeamEnemy : TeamAlly;
                return true;
            case "damage_unit":
                {
                    int index = ResolveUnit(command);
                    if (index < 0) return false;
                    _hp[index] -= DFloat(command, "damage", 0f);
                    _lastAttackerTeams[index] = DInt(command, "team", TeamEnemy);
                    return true;
                }
            case "set_time": _timeRemaining = DFloat(command, "value", _timeRemaining); return true;
            case "set_result": _result = DString(command, "value"); return true;
            case "set_building_spawn_timer":
                {
                    int index = BuildingIndexFromId(DInt(command, "id"));
                    if (index < 0) return false;
                    _buildings[index].SpawnTimer = DFloat(command, "value", 0f);
                    return true;
                }
            case "damage_building":
                ApplyBuildingDamage(DInt(command, "id"), DFloat(command, "damage"), DInt(command, "team", TeamAlly));
                return true;
            case "recalculate_territory": RecalculateTerritory(DBool(command, "emit", false), true); return true;
            case "rebuild_flow": RebuildFlowFields(); return true;
            case "schedule_siege":
                ScheduleSiegeImpact(DInt(command, "team", TeamAlly), DVector2(command, "origin", Vector2.Zero), DVector2(command, "target", Vector2.Zero), DFloat(command, "damage", UnitAttackDamage(UnitSiege)), DFloat(command, "duration", _settings.SiegeFlightSeconds));
                return true;
            default: return false;
        }
    }

    public float GetUnitRadius(int kind) => UnitRadius(kind);
    public float GetSeparationDistance(int firstKind, int secondKind) => SeparationDistance(firstKind, secondKind);
    public float GetSiegeDamageAtDistance(float centerDistance, float targetRadius, float baseDamage) => SiegeDamageAtDistance(centerDistance, targetRadius, baseDamage);
    public float GetSiegeFlightSeconds(float distance) => SiegeFlightSeconds(distance);
    public float GetUnitAttackRange(int kind, Vector2 position) => UnitAttackRange(kind, position);
    public float GetGroundSpeedMultiplier(Vector2 from, Vector2 toward) => GroundSpeedMultiplier(from, toward);
    public float GetElevationDamageMultiplier(Vector2 attacker, Vector2 target) => ElevationDamageMultiplier(attacker, target);
    public bool CanGroundStep(Vector2I from, Vector2I to) => CanGroundStepInternal(from, to);
    public bool CanGroundStepForKind(int team, int kind, Vector2I from, Vector2I to) =>
        GroundNavigation.CanTransition(from, to, SelectFlowBlocked(team, kind), _elevation, BattleConfig.GridColumns, BattleConfig.GridRows);
    public bool IsGroundPositionClear(Vector2 position, float radius) =>
        GroundNavigation.CanOccupyPosition(position, radius, _groundBlocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows);
    public Vector2I GetFlowNextCell(int team, int kind, Vector2I cell) => SelectFlow(team, kind).NextCellAt(cell);
    public bool CanFlyingStep(Vector2I from, Vector2I to) => Valid(from) && Valid(to);
    public bool IsWaterCell(Vector2I cell) => Valid(cell) && _water[Index(cell)] != 0;
    public int WaterComponentCount()
    {
        var visited = new byte[BattleConfig.CellCount];
        int components = 0;
        var queue = new System.Collections.Generic.Queue<int>();
        Vector2I[] offsets = { Vector2I.Left, Vector2I.Right, Vector2I.Up, Vector2I.Down };
        for (int start = 0; start < BattleConfig.CellCount; start++)
        {
            if (_water[start] == 0 || visited[start] != 0) continue;
            components++;
            visited[start] = 1;
            queue.Enqueue(start);
            while (queue.Count > 0)
            {
                int current = queue.Dequeue();
                int col = current % BattleConfig.GridColumns;
                int row = current / BattleConfig.GridColumns;
                foreach (Vector2I offset in offsets)
                {
                    Vector2I neighbor = new(col + offset.X, row + offset.Y);
                    if (!Valid(neighbor)) continue;
                    int next = Index(neighbor);
                    if (_water[next] == 0 || visited[next] != 0) continue;
                    visited[next] = 1;
                    queue.Enqueue(next);
                }
            }
        }
        return components;
    }
    public bool TerrainPathsValid() { _terrain.Elevation = _elevation; _terrain.Water = _water; return _terrain.AllRequiredPathsReachable(BattleConfig.TerrainDeploymentDepth); }

    private bool SpawnStressFixture(int count, bool bypassCap)
    {
        _unitCount = 0;
        Array.Clear(_teamUnitCounts);
        ResetLegions();
        Array.Fill(_indexById, -1);
        _nextUnitId = 1;
        for (int i = 0; i < count; i++)
        {
            int team = i < count / 2 ? TeamEnemy : TeamAlly;
            int local = team == TeamEnemy ? i : i - count / 2;
            int kind = local % 3 == 0 ? UnitMelee : local % 3 == 1 ? UnitRanged : UnitSiege;
            float x = (local % BattleConfig.GridColumns) + 0.5f;
            float rank = (local / BattleConfig.GridColumns) % 10;
            float y = team == TeamEnemy ? 29.0f + rank * 0.24f : 59.0f - rank * 0.24f;
            int id = SpawnUnit(team, new Vector2(x, y), kind, -1, default, bypassCap);
            if (id != 0) _positions[_indexById[id]] = new Vector2(x, y);
        }
        RebuildBuckets();
        RebuildFlowFields();
        return _unitCount == count;
    }
    public float GetFlowCost(int team, Vector2I cell) => team == TeamAlly ? _allyFlow.CostAt(cell) : _enemyFlow.CostAt(cell);
    public Vector2 GetFlowDirection(int team, Vector2I cell) => team == TeamAlly ? _allyFlow.DirectionAt(cell) : _enemyFlow.DirectionAt(cell);

    private int ResolveUnit(GDictionary command)
    {
        if (command.ContainsKey("index")) return Math.Clamp(DInt(command, "index"), -1, _unitCount - 1);
        int id = DInt(command, "id");
        return id > 0 && id < _indexById.Length ? _indexById[id] : -1;
    }

    private static string DString(GDictionary d, string key, string fallback = "") => d.TryGetValue(key, out Variant value) ? value.AsString() : fallback;
    private static int DInt(GDictionary d, string key, int fallback = 0) => d.TryGetValue(key, out Variant value) ? value.AsInt32() : fallback;
    private static float DFloat(GDictionary d, string key, float fallback = 0f) => d.TryGetValue(key, out Variant value) ? value.AsSingle() : fallback;
    private static bool DBool(GDictionary d, string key, bool fallback = false) => d.TryGetValue(key, out Variant value) ? value.AsBool() : fallback;
    private static Vector2 DVector2(GDictionary d, string key, Vector2 fallback) => d.TryGetValue(key, out Variant value) ? value.AsVector2() : fallback;
    private static Vector2I DVector2I(GDictionary d, string key, Vector2I fallback) => d.TryGetValue(key, out Variant value) ? value.AsVector2I() : fallback;
    private static float[] Copy(float[] source, int count) { var result = new float[count]; Array.Copy(source, result, count); return result; }
}
