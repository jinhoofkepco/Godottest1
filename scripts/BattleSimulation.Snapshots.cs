using Godot;
using GArray = Godot.Collections.Array;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Diagnostics;

public partial class BattleSimulation
{
    public GDictionary GetHudSnapshot()
    {
        _hudSnapshot["ally_gold"] = _allyGold;
        _hudSnapshot["enemy_gold"] = _enemyGold;
        _hudSnapshot["ally_hq_hp"] = BuildingHp(_allyHqId);
        _hudSnapshot["enemy_hq_hp"] = BuildingHp(_enemyHqId);
        _hudSnapshot["occupancy"] = _allyOccupancy;
        _hudSnapshot["time_remaining"] = _timeRemaining;
        _hudSnapshot["result"] = _result;
        _hudSnapshot["unit_count"] = _unitCount;
        _hudSnapshot["ally_unit_count"] = _teamUnitCounts[TeamAlly];
        _hudSnapshot["enemy_unit_count"] = _teamUnitCounts[TeamEnemy];
        _hudSnapshot["team_unit_cap"] = BattleConfig.TeamUnitCap;
        _hudSnapshot["ally_income_multiplier"] = PopulationIncomeMultiplier(TeamAlly);
        _hudSnapshot["enemy_income_multiplier"] = PopulationIncomeMultiplier(TeamEnemy) * AiIncomeMultiplier();
        _hudSnapshot["ai_income_level"] = _aiIncomeLevel;
        _hudSnapshot["ai_income_multiplier"] = AiIncomeMultiplier();
        _hudSnapshot["board_version"] = _boardVersion;
        return _hudSnapshot;
    }

    public int GetBoardVersion() => _boardVersion;

    public GDictionary GetBoardSnapshot()
    {
        ClearPendingBoardDeltas();
        if (_boardSnapshot is not null && _boardSnapshotVersion == _boardVersion)
            return _boardSnapshot;
        _boardSnapshot = new GDictionary
        {
            ["version"] = _boardVersion,
            ["ownership"] = (byte[])_ownership.Clone(),
            ["blocked"] = (byte[])_blocked.Clone(),
            ["water"] = (byte[])_water.Clone(),
            ["elevation"] = (byte[])_elevation.Clone(),
            ["buildings"] = BuildBuildingsSnapshot(),
            ["ally_hq_id"] = _allyHqId,
            ["enemy_hq_id"] = _enemyHqId,
        };
        _boardSnapshotVersion = _boardVersion;
        return _boardSnapshot;
    }

    public GDictionary GetBoardDelta()
    {
        int[] ownershipIndices = new int[_pendingOwnershipCount];
        int[] ownershipOwners = new int[_pendingOwnershipCount];
        for (int i = 0; i < _pendingOwnershipCount; i++)
        {
            int cellIndex = _pendingOwnershipCells[i];
            ownershipIndices[i] = cellIndex;
            ownershipOwners[i] = _ownership[cellIndex];
            _pendingOwnershipFlags[cellIndex] = 0;
        }
        int[] blockedIndices = new int[_pendingBlockedCount];
        int[] blockedValues = new int[_pendingBlockedCount];
        for (int i = 0; i < _pendingBlockedCount; i++)
        {
            int cellIndex = _pendingBlockedCells[i];
            blockedIndices[i] = cellIndex;
            Vector2I cell = new(cellIndex % BattleConfig.GridColumns, cellIndex / BattleConfig.GridColumns);
            blockedValues[i] = IsBlocked(cell) || BuildingAt(cell) >= 0 ? 1 : 0;
            _pendingBlockedFlags[cellIndex] = 0;
        }
        _pendingOwnershipCount = 0;
        _pendingBlockedCount = 0;
        return new GDictionary
        {
            ["version"] = _boardVersion,
            ["ownership_indices"] = ownershipIndices,
            ["ownership_owners"] = ownershipOwners,
            ["blocked_indices"] = blockedIndices,
            ["blocked_values"] = blockedValues,
            ["buildings"] = BuildBuildingsSnapshot(),
        };
    }

    private GArray BuildBuildingsSnapshot()
    {
        var buildings = new GArray();
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            buildings.Add(new GDictionary
            {
                ["id"] = building.Id,
                ["team"] = building.Team,
                ["kind"] = building.Kind,
                ["unit_kind"] = building.UnitKind,
                ["cell"] = building.Cell,
                ["hp"] = building.Hp,
                ["max_hp"] = building.MaxHp,
                ["complete"] = building.Complete,
                ["construction_duration"] = building.ConstructionDuration,
                ["construction_remaining"] = building.ConstructionRemaining,
                ["construction_progress"] = building.Complete || building.ConstructionDuration <= 0f ? 1f : 1f - building.ConstructionRemaining / building.ConstructionDuration,
                ["destroyed"] = building.Destroyed,
                ["rally_mode"] = building.RallyMode,
                ["formation"] = building.Formation,
                ["active_legion_id"] = building.ActiveLegionId,
                ["waiting_count"] = building.WaitingCount,
            });
        }
        return buildings;
    }

    public GDictionary GetRenderSnapshot()
    {
        long start = Stopwatch.GetTimestamp();
        int infantryCount = BuildInfantryBuffer();
        int enemyDragonCount = BuildDragonBuffer(TeamEnemy, ref _enemyDragonBuffer);
        int allyDragonCount = BuildDragonBuffer(TeamAlly, ref _allyDragonBuffer);
        int shadowCount = BuildShadowBuffer();
        int hpBarCount = BuildHpBarBuffer();
        int legionBannerCount = BuildLegionBannerBuffer();
        int legionGhostCount = BuildLegionGhostBuffer();
        long elapsed = Usec(start);
        if (_profilingEnabled) _profileSnapshotUsec += elapsed;
        _renderSnapshot["infantry_count"] = infantryCount;
        _renderSnapshot["infantry_buffer"] = _infantryBuffer;
        _renderSnapshot["enemy_dragon_count"] = enemyDragonCount;
        _renderSnapshot["enemy_dragon_buffer"] = _enemyDragonBuffer;
        _renderSnapshot["ally_dragon_count"] = allyDragonCount;
        _renderSnapshot["ally_dragon_buffer"] = _allyDragonBuffer;
        _renderSnapshot["shadow_count"] = shadowCount;
        _renderSnapshot["shadow_buffer"] = _shadowBuffer;
        _renderSnapshot["hp_bar_count"] = hpBarCount;
        _renderSnapshot["hp_bars"] = _hpBarBuffer;
        _renderSnapshot["legion_banner_count"] = legionBannerCount;
        _renderSnapshot["legion_banner_buffer"] = _legionBannerBuffer;
        _renderSnapshot["legion_ghost_count"] = legionGhostCount;
        _renderSnapshot["legion_ghost_buffer"] = _legionGhostBuffer;
        _renderSnapshot["assembly_usec"] = elapsed;
        return _renderSnapshot;
    }

    private int BuildInfantryBuffer()
    {
        int count = 0;
        for (int i = 0; i < _unitCount; i++)
            if (_hp[i] > 0f && _kinds[i] != UnitDragon)
                _renderEntries[count++] = new RenderEntry { Index = i, GhostIndex = -1, Y = PositionToWorld(_positions[i]).Y };
        for (int i = 0; i < _ghostCount; i++)
            _renderEntries[count++] = new RenderEntry { Index = -1, GhostIndex = i, Y = PositionToWorld(_ghosts[i].Position).Y };
        Array.Sort(_renderEntries, 0, count);
        EnsureBuffer(ref _infantryBuffer, count * 16);
        for (int draw = 0; draw < count; draw++)
        {
            RenderEntry entry = _renderEntries[draw];
            int team, kind, stateIndex, animationFrame;
            Vector2 position, direction;
            float brightness = 1f, alpha = 1f;
            if (entry.Index >= 0)
            {
                int index = entry.Index;
                team = _teams[index];
                kind = _kinds[index];
                position = UnitRenderPosition(index);
                direction = _velocities[index];
                int state = _states[index];
                if (state == StateAttack)
                {
                    stateIndex = 2;
                    direction = _lungeDirections[index];
                    float progress = 1f - Mathf.Clamp(_cooldowns[index] / UnitAttackInterval(kind), 0f, 1f);
                    animationFrame = Math.Min(3, Mathf.FloorToInt(progress * 4f));
                }
                else if (state == StateAdvance && direction.LengthSquared() > 0.01f)
                {
                    stateIndex = 1;
                    animationFrame = (Mathf.FloorToInt(_visualClock * BattleConfig.WalkFps) + _ids[index]) % 6;
                }
                else
                {
                    stateIndex = 0;
                    animationFrame = (Mathf.FloorToInt(_visualClock * BattleConfig.IdleFps) + _ids[index]) % 2;
                }
                brightness = Mathf.Lerp(0.58f, 1f, Mathf.Clamp(_hp[index] / UnitMaxHp(kind), 0f, 1f));
                if (state == StateWait) brightness *= 0.76f;
            }
            else
            {
                DeathGhost ghost = _ghosts[entry.GhostIndex];
                team = ghost.Team;
                kind = ghost.Kind;
                position = PositionToWorld(ghost.Position) + new Vector2(0f, UnitFootAnchor(kind));
                direction = ghost.Direction.LengthSquared() > 0.000001f ? ghost.Direction : team == TeamEnemy ? Vector2.Down : Vector2.Up;
                stateIndex = 3;
                float progress = 1f - Mathf.Clamp(ghost.Remaining / BattleConfig.DeathDuration, 0f, 1f);
                animationFrame = Math.Min(3, Mathf.FloorToInt(progress * 4f));
                alpha = Mathf.Clamp(ghost.Remaining / (BattleConfig.DeathDuration * 0.28f), 0f, 1f);
            }
            int directionIndex = DirectionIndex(direction, team);
            int stateOffset = stateIndex == 0 ? 0 : stateIndex == 1 ? 2 : stateIndex == 2 ? 8 : 12;
            int linear = (kind == UnitSiege ? 0 : kind * BattleConfig.ClassFrameCount) + directionIndex * BattleConfig.FramesPerDirection + stateOffset + animationFrame;
            int cellX = linear % BattleConfig.AtlasColumns;
            int cellY = linear / BattleConfig.AtlasColumns;
            Vector2 size = UnitRenderSize(kind);
            Vector2 scale = size / new Vector2(BattleConfig.InfantryBaseWidth, BattleConfig.InfantryBaseHeight);
            int layer = kind == UnitSiege ? (team == TeamEnemy ? 3 : 2) : (team == TeamEnemy ? 1 : 0);
            WriteRecord(_infantryBuffer, draw, scale, position, new Color(1f, brightness, 0f, alpha), new Color(cellX / 15f, cellY / 15f, layer / 3f, kind == UnitSiege ? 1f : 0f));
        }
        return count;
    }

    private int BuildDragonBuffer(int team, ref float[] buffer)
    {
        int count = 0;
        for (int i = 0; i < _unitCount; i++)
            if (_hp[i] > 0f && _kinds[i] == UnitDragon && _teams[i] == team)
                _dragonEntries[count++] = new RenderEntry { Index = i, GhostIndex = -1, Y = PositionToWorld(_positions[i]).Y };
        Array.Sort(_dragonEntries, 0, count);
        EnsureBuffer(ref buffer, count * 16);
        for (int draw = 0; draw < count; draw++)
        {
            int index = _dragonEntries[draw].Index;
            Vector2 direction = _velocities[index];
            int stateOffset = 2;
            int frame = (Mathf.FloorToInt(_visualClock * BattleConfig.WalkFps) + _ids[index]) % 6;
            if (_states[index] == StateAttack)
            {
                direction = _lungeDirections[index];
                stateOffset = 8;
                float progress = 1f - Mathf.Clamp(_cooldowns[index] / BattleConfig.DragonAttackInterval, 0f, 1f);
                frame = Math.Min(3, Mathf.FloorToInt(progress * 4f));
            }
            else if (direction.LengthSquared() <= 0.01f)
            {
                stateOffset = 0;
                frame = (Mathf.FloorToInt(_visualClock * BattleConfig.IdleFps) + _ids[index]) % 2;
            }
            int linear = DirectionIndex(direction, team) * BattleConfig.FramesPerDirection + stateOffset + frame;
            float brightness = Mathf.Lerp(0.62f, 1f, Mathf.Clamp(_hp[index] / BattleConfig.DragonHp, 0f, 1f));
            WriteRecord(buffer, draw, Vector2.One, UnitRenderPosition(index), new Color(brightness, brightness, brightness, 1f), new Color((linear % 16) / 15f, (linear / 16) / 7f, 0f, 1f));
        }
        return count;
    }

    private int BuildShadowBuffer()
    {
        int count = _unitCount + _ghostCount;
        EnsureBuffer(ref _shadowBuffer, count * 12);
        int draw = 0;
        for (int i = 0; i < _unitCount; i++)
        {
            if (_hp[i] <= 0f) continue;
            float scale = UnitRadius(_kinds[i]) / BattleConfig.MeleeRadius;
            WriteShadowRecord(_shadowBuffer, draw++, new Vector2(scale, scale * (_kinds[i] == UnitDragon ? 0.82f : 1f)), PositionToWorld(_positions[i]) + new Vector2(0f, 2f), _kinds[i] == UnitDragon ? 0.24f : 0.35f);
        }
        for (int i = 0; i < _ghostCount; i++)
        {
            float scale = UnitRadius(_ghosts[i].Kind) / BattleConfig.MeleeRadius;
            WriteShadowRecord(_shadowBuffer, draw++, new Vector2(scale, scale), PositionToWorld(_ghosts[i].Position) + new Vector2(0f, 2f), 0.35f);
        }
        if (draw != count) EnsureBuffer(ref _shadowBuffer, draw * 12);
        return draw;
    }

    private int BuildHpBarBuffer()
    {
        int count = 0;
        for (int i = 0; i < _unitCount; i++)
            if (_hp[i] < UnitMaxHp(_kinds[i]) * 0.995f && _hpBarTimers[i] > 0f)
                count++;
        EnsureBuffer(ref _hpBarBuffer, count * 8);
        int draw = 0;
        for (int i = 0; i < _unitCount; i++)
        {
            float maxHp = UnitMaxHp(_kinds[i]);
            if (_hp[i] >= maxHp * 0.995f || _hpBarTimers[i] <= 0f) continue;
            Vector2 size = UnitRenderSize(_kinds[i]);
            float width = Mathf.Max(12f, size.X * 0.62f);
            Vector2 at = PositionToWorld(_positions[i]) + new Vector2(-width * 0.5f, UnitFootAnchor(_kinds[i]) - size.Y * 0.55f);
            int offset = draw++ * 8;
            _hpBarBuffer[offset] = at.X;
            _hpBarBuffer[offset + 1] = at.Y;
            _hpBarBuffer[offset + 2] = width;
            _hpBarBuffer[offset + 3] = Mathf.Clamp(_hp[i] / maxHp, 0f, 1f);
            _hpBarBuffer[offset + 4] = _teams[i];
            _hpBarBuffer[offset + 5] = Mathf.Clamp(_hpBarTimers[i] / BattleConfig.HpBarFadeSeconds, 0f, 1f);
            _hpBarBuffer[offset + 6] = _ids[i];
            _hpBarBuffer[offset + 7] = 0f;
        }
        return count;
    }

    private int BuildLegionBannerBuffer()
    {
        int count = 0;
        for (int i = 0; i < _legionCount; i++)
            if (_legionStates[i] != LegionBroken && (_legionLiveCounts[i] > 0 || _legionStates[i] == LegionGathering)) count++;
        EnsureBuffer(ref _legionBannerBuffer, count * 16);
        int draw = 0;
        for (int i = 0; i < _legionCount; i++)
        {
            if (_legionStates[i] == LegionBroken || (_legionLiveCounts[i] <= 0 && _legionStates[i] != LegionGathering)) continue;
            Vector2 origin = PositionToWorld(_legionAnchors[i]) + new Vector2(0f, -24f);
            float alpha = _legionStates[i] == LegionGathering ? 0.58f : _legionStates[i] == LegionEngaged ? 0.78f : 0.72f;
            Color color = _legionTeams[i] == TeamAlly ? new Color(0.18f, 0.62f, 1f, alpha) : new Color(1f, 0.28f, 0.34f, alpha);
            color.G *= _legionStates[i] == LegionEngaged ? 1.25f : _legionStates[i] == LegionGathering ? 0.72f : 1f;
            WriteRecord(_legionBannerBuffer, draw++, Vector2.One, origin, color, new Color(_legionStates[i] / 3f, _legionFormations[i] / 2f, 0f, 0f));
        }
        return draw;
    }

    private int BuildLegionGhostBuffer()
    {
        int count = 0;
        for (int i = 0; i < _legionCount; i++) if (_legionStates[i] == LegionGathering) count += _legionOriginalCounts[i];
        EnsureBuffer(ref _legionGhostBuffer, count * 16);
        int draw = 0;
        for (int i = 0; i < _legionCount; i++)
        {
            if (_legionStates[i] != LegionGathering) continue;
            for (int slot = 0; slot < _legionOriginalCounts[i]; slot++)
            {
                Vector2 origin = PositionToWorld(LegionSlotWorldPosition(i, LocalSlotFor(i, slot))) + new Vector2(0f, -2f);
                float alpha = slot < _legionProducedCounts[i] ? 0.10f : 0.42f;
                Color color = _legionTeams[i] == TeamAlly ? new Color(0.25f, 0.78f, 1f, alpha) : new Color(1f, 0.36f, 0.42f, alpha);
                WriteRecord(_legionGhostBuffer, draw++, Vector2.One, origin, color, new Color(slot < _legionProducedCounts[i] ? 1f : 0f, _legionFormations[i] / 2f, 0f, 0f));
            }
        }
        return draw;
    }

    private static void EnsureBuffer(ref float[] buffer, int length)
    {
        if (buffer.Length != length) buffer = new float[length];
        else Array.Clear(buffer);
    }

    private static void WriteRecord(float[] buffer, int index, Vector2 scale, Vector2 origin, Color color, Color custom)
    {
        int o = index * 16;
        buffer[o] = scale.X; buffer[o + 1] = 0f; buffer[o + 2] = 0f; buffer[o + 3] = origin.X;
        buffer[o + 4] = 0f; buffer[o + 5] = scale.Y; buffer[o + 6] = 0f; buffer[o + 7] = origin.Y;
        buffer[o + 8] = color.R; buffer[o + 9] = color.G; buffer[o + 10] = color.B; buffer[o + 11] = color.A;
        buffer[o + 12] = custom.R; buffer[o + 13] = custom.G; buffer[o + 14] = custom.B; buffer[o + 15] = custom.A;
    }

    private static void WriteShadowRecord(float[] buffer, int index, Vector2 scale, Vector2 origin, float alpha)
    {
        int o = index * 12;
        buffer[o] = scale.X; buffer[o + 1] = 0f; buffer[o + 2] = 0f; buffer[o + 3] = origin.X;
        buffer[o + 4] = 0f; buffer[o + 5] = scale.Y; buffer[o + 6] = 0f; buffer[o + 7] = origin.Y;
        buffer[o + 8] = 0.02f; buffer[o + 9] = 0.03f; buffer[o + 10] = 0.05f; buffer[o + 11] = alpha;
    }

    private Vector2 PositionToWorld(Vector2 grid)
    {
        int elevation = _elevation[Index(CellAt(grid))];
        return new Vector2((grid.X - grid.Y) * BattleConfig.IsoTileWidth * 0.5f, (grid.X + grid.Y) * BattleConfig.IsoTileHeight * 0.5f - elevation * BattleConfig.ElevationPixelStep);
    }

    private Vector2 UnitRenderPosition(int index)
    {
        Vector2 lunge = Vector2.Zero;
        if (_lungeTimers[index] > 0f)
        {
            float remaining = Mathf.Clamp(_lungeTimers[index] / BattleConfig.UnitLungeDuration, 0f, 1f);
            lunge = _lungeDirections[index] * BattleConfig.UnitLungeDistance * Mathf.Sin((1f - remaining) * Mathf.Pi);
        }
        return PositionToWorld(_positions[index] + lunge) + new Vector2(0f, UnitFootAnchor(_kinds[index]));
    }

    private static Vector2 UnitRenderSize(int kind)
    {
        float width = UnitRadius(kind) * BattleConfig.UnitRenderPixelsPerRadius;
        float aspect = kind == UnitDragon ? 1.12f : kind == UnitSiege ? 1f : 1.30f;
        return new Vector2(width, width * aspect);
    }

    private static float UnitFootAnchor(int kind)
    {
        Vector2 size = UnitRenderSize(kind);
        return -size.Y * (kind == UnitDragon ? 0.47f : 0.45f);
    }

    private static int DirectionIndex(Vector2 direction, int team)
    {
        if (direction.LengthSquared() <= 0.000001f) direction = team == TeamEnemy ? Vector2.Down : Vector2.Up;
        float angle = Mathf.Atan2(direction.X, direction.Y);
        return Mathf.PosMod(Mathf.RoundToInt(angle / Mathf.Tau * BattleConfig.AtlasDirections), BattleConfig.AtlasDirections);
    }

    public GDictionary DrainEvents()
    {
        GArray drainedEvents = _events;
        _events = new GArray();
        var result = new GDictionary
        {
            ["events"] = drainedEvents,
            ["hit_unit_ids"] = Copy(_hitIds, _hitCount),
            ["hit_teams"] = Copy(_hitTeams, _hitCount),
            ["hit_positions"] = Copy(_hitPositions, _hitCount),
            ["hit_high_ground"] = Copy(_hitHighGround, _hitCount),
            ["shot_kinds"] = Copy(_shotKinds, _shotCount),
            ["shot_teams"] = Copy(_shotTeams, _shotCount),
            ["shot_origins"] = Copy(_shotOrigins, _shotCount),
            ["shot_targets"] = Copy(_shotTargets, _shotCount),
            ["death_unit_ids"] = Copy(_deathIds, _deathCount),
            ["death_teams"] = Copy(_deathTeams, _deathCount),
            ["death_kinds"] = Copy(_deathKinds, _deathCount),
            ["death_positions"] = Copy(_deathPositions, _deathCount),
            ["death_directions"] = Copy(_deathDirections, _deathCount),
        };
        _hitCount = _shotCount = _deathCount = 0;
        return result;
    }

    private void QueueHit(int unitIndex, bool highGround, bool strong = false)
    {
        if (_hitCount >= MaxEvents) return;
        int eventIndex = _hitCount++;
        _hitIds[eventIndex] = _ids[unitIndex];
        _hitTeams[eventIndex] = _teams[unitIndex];
        _hitPositions[eventIndex] = _positions[unitIndex];
        _hitHighGround[eventIndex] = (byte)((highGround ? 1 : 0) | (strong ? 2 : 0));
        _hpBarTimers[unitIndex] = BattleConfig.HpBarVisibleSeconds;
    }

    private void QueueShot(int kind, int team, Vector2 origin, Vector2 target)
    {
        if (_shotCount >= MaxEvents) return;
        int eventIndex = _shotCount++;
        _shotKinds[eventIndex] = (byte)kind;
        _shotTeams[eventIndex] = team;
        _shotOrigins[eventIndex] = origin;
        _shotTargets[eventIndex] = target;
    }

    private void QueueDeath(int unitIndex, Vector2 direction)
    {
        if (_deathCount >= MaxEvents) return;
        int eventIndex = _deathCount++;
        _deathIds[eventIndex] = _ids[unitIndex];
        _deathTeams[eventIndex] = _teams[unitIndex];
        _deathKinds[eventIndex] = _kinds[unitIndex];
        _deathPositions[eventIndex] = _positions[unitIndex];
        _deathDirections[eventIndex] = direction;
    }

    private void QueueStructural(string type, int team, int id, Vector2I cell, int kind, int unitKind)
    {
        _events.Add(new GDictionary { ["type"] = type, ["team"] = team, ["building_id"] = id, ["unit_id"] = id, ["cell"] = cell, ["kind"] = kind, ["unit_kind"] = unitKind });
    }

    private static int[] Copy(int[] source, int count) { var result = new int[count]; Array.Copy(source, result, count); return result; }
    private static byte[] Copy(byte[] source, int count) { var result = new byte[count]; Array.Copy(source, result, count); return result; }
    private static Vector2[] Copy(Vector2[] source, int count) { var result = new Vector2[count]; Array.Copy(source, result, count); return result; }

    private float BuildingHp(int id) { int index = BuildingIndexFromId(id); return index >= 0 ? _buildings[index].Hp : 0f; }
}
