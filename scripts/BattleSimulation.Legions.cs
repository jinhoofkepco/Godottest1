using Godot;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Collections.Generic;

public partial class BattleSimulation
{
    public const int FormationLine = 0;
    public const int FormationWedge = 1;
    public const int FormationLoose = 2;
    public const int LegionGathering = 0;
    public const int LegionMarching = 1;
    public const int LegionEngaged = 2;
    public const int LegionBroken = 3;
    public const int RallyAdvance = 0;
    public const int RallyDefend = 1;

    private const int MaxLegions = 256;
    private readonly int[] _legionRecordIds = new int[MaxLegions];
    private readonly int[] _legionIndexById = new int[MaxLegions + 1];
    private readonly int[] _legionTeams = new int[MaxLegions];
    private readonly int[] _legionRallyIds = new int[MaxLegions];
    private readonly int[] _legionFormations = new int[MaxLegions];
    private readonly int[] _legionStates = new int[MaxLegions];
    private readonly int[] _legionMeleeCounts = new int[MaxLegions];
    private readonly int[] _legionRangedCounts = new int[MaxLegions];
    private readonly int[] _legionSiegeCounts = new int[MaxLegions];
    private readonly int[] _legionDragonCounts = new int[MaxLegions];
    private readonly int[] _legionProducedCounts = new int[MaxLegions];
    private readonly int[] _legionOriginalCounts = new int[MaxLegions];
    private readonly int[] _legionLiveCounts = new int[MaxLegions];
    private readonly Vector2[] _legionAnchors = new Vector2[MaxLegions];
    private readonly Vector2[] _legionHeadings = new Vector2[MaxLegions];
    private readonly Vector2[] _legionWaypoints = new Vector2[MaxLegions];
    private readonly byte[] _legionHasWaypoint = new byte[MaxLegions];
    private readonly byte[] _legionDefending = new byte[MaxLegions];
    private readonly float[] _legionGatheringElapsed = new float[MaxLegions];
    private readonly float[] _legionDisengageTimers = new float[MaxLegions];
    private readonly List<int>[] _rallyMembers = NewRallyMemberLists();
    private int _legionCount;
    private int _nextLegionId;

    private static List<int>[] NewRallyMemberLists()
    {
        var result = new List<int>[MaxBuildings];
        for (int i = 0; i < result.Length; i++) result[i] = new List<int>(32);
        return result;
    }

    private void ResetLegions()
    {
        _legionCount = 0;
        _nextLegionId = 1;
        Array.Fill(_legionIndexById, -1);
        Array.Fill(_legionIds, -1);
        Array.Fill(_rallyPointIds, -1);
        Array.Clear(_slotOffsets);
        for (int i = 0; i < _rallyMembers.Length; i++) _rallyMembers[i].Clear();
    }

    private static GDictionary PresetTemplate(int preset) => preset switch
    {
        1 => new GDictionary { ["melee"] = 4, ["ranged"] = 7, ["siege"] = 1, ["dragon"] = 0 },
        2 => new GDictionary { ["melee"] = 9, ["ranged"] = 1, ["siege"] = 1, ["dragon"] = 1 },
        3 => new GDictionary { ["melee"] = 6, ["ranged"] = 4, ["siege"] = 1, ["dragon"] = 1 },
        _ => new GDictionary { ["melee"] = 7, ["ranged"] = 4, ["siege"] = 1, ["dragon"] = 0 },
    };

    public GDictionary ValidateTemplate(GDictionary source)
    {
        int melee = TemplateValue(source, "melee", 0);
        int ranged = TemplateValue(source, "ranged", 0);
        int siege = Math.Min(BattleConfig.LegionMaxSiege, TemplateValue(source, "siege", 0));
        int dragon = Math.Min(BattleConfig.LegionMaxDragons, TemplateValue(source, "dragon", 0));
        int remaining = BattleConfig.LegionMaxMembers;
        melee = Math.Min(melee, remaining); remaining -= melee;
        ranged = Math.Min(ranged, remaining); remaining -= ranged;
        siege = Math.Min(siege, remaining); remaining -= siege;
        dragon = Math.Min(dragon, remaining);
        if (melee + ranged + siege + dragon == 0) melee = 1;
        return new GDictionary { ["melee"] = melee, ["ranged"] = ranged, ["siege"] = siege, ["dragon"] = dragon };
    }

    private static int TemplateValue(GDictionary source, string key, int fallback) =>
        source.TryGetValue(key, out Variant value) ? Math.Max(0, value.AsInt32()) : fallback;

    private static int TemplateTotal(GDictionary template) =>
        TemplateValue(template, "melee", 0) + TemplateValue(template, "ranged", 0) + TemplateValue(template, "siege", 0) + TemplateValue(template, "dragon", 0);

    public Vector2[] GetFormationSlots(GDictionary source, int formation, Vector2 heading)
    {
        GDictionary template = ValidateTemplate(source);
        Vector2[] local = BuildLocalSlots(template, Math.Clamp(formation, FormationLine, FormationLoose));
        Vector2 forward = heading.LengthSquared() > 0.0001f ? heading.Normalized() : Vector2.Up;
        Vector2 right = new(-forward.Y, forward.X);
        var result = new Vector2[local.Length];
        for (int i = 0; i < local.Length; i++) result[i] = right * local[i].X - forward * local[i].Y;
        return result;
    }

    private static Vector2[] BuildLocalSlots(GDictionary template, int formation)
    {
        int melee = TemplateValue(template, "melee", 0);
        int ranged = TemplateValue(template, "ranged", 0);
        int siege = TemplateValue(template, "siege", 0);
        int dragon = TemplateValue(template, "dragon", 0);
        var slots = new Vector2[melee + ranged + siege + dragon];
        int cursor = 0;
        if (formation == FormationLoose)
        {
            for (int i = 0; i < melee; i++) slots[cursor++] = GridSlot(i, melee, 4, 0.96f, -1.15f);
            int rear = ranged + siege + dragon;
            for (int i = 0; i < rear; i++) slots[cursor++] = GridSlot(i, rear, 4, 0.96f, 0.75f);
            return slots;
        }
        if (formation == FormationWedge)
        {
            for (int i = 0; i < melee; i++)
            {
                if (i == 0) slots[cursor++] = new Vector2(0f, -1.15f);
                else
                {
                    int rank = (i + 1) / 2;
                    float side = i % 2 == 1 ? -1f : 1f;
                    slots[cursor++] = new Vector2(side * rank * 0.40f, -1.15f + rank * 0.42f);
                }
            }
            int rear = ranged + siege + dragon;
            for (int i = 0; i < rear; i++) slots[cursor++] = GridSlot(i, rear, 4, 0.48f, 0.62f);
            return slots;
        }
        for (int i = 0; i < melee; i++) slots[cursor++] = CenteredRowSlot(i, melee, 0.70f, -0.58f);
        for (int i = 0; i < ranged; i++) slots[cursor++] = CenteredRowSlot(i, ranged, 0.58f, 0.28f);
        for (int i = 0; i < siege; i++) slots[cursor++] = CenteredRowSlot(i, siege, 0.62f, 0.82f);
        for (int i = 0; i < dragon; i++) slots[cursor++] = CenteredRowSlot(i, dragon, 0.72f, 1.30f);
        return slots;
    }

    private static Vector2 CenteredRowSlot(int index, int count, float spacing, float depth) =>
        new((index - (count - 1) * 0.5f) * spacing, depth);

    private static Vector2 GridSlot(int index, int count, int columns, float spacing, float startDepth)
    {
        int width = Math.Min(columns, count);
        int col = index % columns;
        int row = index / columns;
        int rowCount = Math.Min(width, count - row * columns);
        return new Vector2((col - (rowCount - 1) * 0.5f) * spacing, startDepth + row * spacing);
    }

    private int LegionIndexFromId(int id)
    {
        return id > 0 && id < _legionIndexById.Length ? _legionIndexById[id] : -1;
    }

    private Vector2 LocalSlotFor(int legionIndex, int slotIndex)
    {
        GDictionary template = new()
        {
            ["melee"] = _legionMeleeCounts[legionIndex],
            ["ranged"] = _legionRangedCounts[legionIndex],
            ["siege"] = _legionSiegeCounts[legionIndex],
            ["dragon"] = _legionDragonCounts[legionIndex],
        };
        Vector2[] slots = BuildLocalSlots(template, _legionFormations[legionIndex]);
        return slotIndex >= 0 && slotIndex < slots.Length ? slots[slotIndex] : Vector2.Zero;
    }

    private Vector2 LegionSlotWorldPosition(int legionIndex, Vector2 local)
    {
        Vector2 forward = _legionHeadings[legionIndex].Normalized();
        Vector2 right = new(-forward.Y, forward.X);
        return _legionAnchors[legionIndex] + right * local.X - forward * local.Y;
    }

    private Vector2 LegionSteering(int unitIndex)
    {
        int legion = LegionIndexFromId(_legionIds[unitIndex]);
        if (legion < 0 || _legionStates[legion] == LegionBroken) return Vector2.Zero;
        Vector2 delta = LegionSlotWorldPosition(legion, _slotOffsets[unitIndex]) - _positions[unitIndex];
        float weight = _legionStates[legion] == LegionEngaged ? BattleConfig.LegionEngagedSlotWeight : BattleConfig.LegionSlotFollowWeight;
        return delta.LengthSquared() > 0.0001f ? delta.Normalized() * weight : Vector2.Zero;
    }

    private Vector2 RallySteering(int unitIndex)
    {
        int buildingIndex = BuildingIndexFromId(_rallyPointIds[unitIndex]);
        if (!IsFriendlyRally(buildingIndex, _teams[unitIndex])) return Vector2.Zero;
        Vector2 target = RallyAnchor(_buildings[buildingIndex]);
        Vector2 delta = target - _positions[unitIndex];
        return delta.LengthSquared() > 0.04f ? delta.Normalized() * BattleConfig.RallyFollowWeight : Vector2.Zero;
    }

    private float LegionSpeedForUnit(int unitIndex)
    {
        int legion = LegionIndexFromId(_legionIds[unitIndex]);
        if (legion < 0 || _legionStates[legion] == LegionEngaged) return UnitSpeed(_kinds[unitIndex]);
        return LegionMinimumSpeed(legion);
    }

    private void UpdateRallyPoints(float delta)
    {
        _ = delta;
        for (int i = 0; i < _buildingCount; i++)
        {
            _rallyMembers[i].Clear();
        }
        for (int unit = 0; unit < _unitCount; unit++)
        {
            if (_hp[unit] <= 0f || _legionIds[unit] >= 0) continue;
            int rallyIndex = BuildingIndexFromId(_rallyPointIds[unit]);
            if (!IsFriendlyRally(rallyIndex, _teams[unit]))
            {
                _rallyPointIds[unit] = NearestRallyId(_teams[unit], _positions[unit]);
                rallyIndex = BuildingIndexFromId(_rallyPointIds[unit]);
            }
            if (!IsFriendlyRally(rallyIndex, _teams[unit])) continue;
            if (_positions[unit].DistanceSquaredTo(RallyAnchor(_buildings[rallyIndex])) <= BattleConfig.RallyArrivalRadius * BattleConfig.RallyArrivalRadius)
                _rallyMembers[rallyIndex].Add(unit);
        }
        for (int buildingIndex = 0; buildingIndex < _buildingCount; buildingIndex++)
        {
            ref Building rally = ref _buildings[buildingIndex];
            if (rally.Destroyed || rally.Kind != BuildingRallyPoint) continue;
            List<int> waiting = _rallyMembers[buildingIndex];
            waiting.Sort((left, right) => _ids[left].CompareTo(_ids[right]));
            if (rally.RallyMode == RallyAdvance)
            {
                while (waiting.Count >= BattleConfig.RallyLaunchSize)
                {
                    CreateLegionFromMembers(rally.Team, rally.Id, rally.Formation, waiting, 0, BattleConfig.RallyLaunchSize, false);
                    waiting.RemoveRange(0, BattleConfig.RallyLaunchSize);
                }
                SetRallyWaitingCount(ref rally, waiting.Count);
                continue;
            }
            int garrison = LegionIndexFromId(rally.ActiveLegionId);
            if (garrison < 0 || _legionStates[garrison] == LegionBroken)
            {
                rally.ActiveLegionId = -1;
                if (waiting.Count > 0)
                {
                    int take = Math.Min(BattleConfig.RallyDefenseCapacity, waiting.Count);
                    rally.ActiveLegionId = CreateLegionFromMembers(rally.Team, rally.Id, rally.Formation, waiting, 0, take, true);
                    waiting.RemoveRange(0, take);
                    garrison = LegionIndexFromId(rally.ActiveLegionId);
                }
            }
            else if (_legionLiveCounts[garrison] < BattleConfig.RallyDefenseCapacity && waiting.Count > 0)
            {
                int take = Math.Min(BattleConfig.RallyDefenseCapacity - _legionLiveCounts[garrison], waiting.Count);
                AddMembersToLegion(garrison, waiting, take);
                waiting.RemoveRange(0, take);
            }
            while (waiting.Count > 0)
            {
                int take = Math.Min(BattleConfig.RallyLaunchSize, waiting.Count);
                CreateLegionFromMembers(rally.Team, rally.Id, rally.Formation, waiting, 0, take, false);
                waiting.RemoveRange(0, take);
            }
            SetRallyWaitingCount(ref rally, garrison >= 0 && _legionStates[garrison] != LegionBroken ? _legionLiveCounts[garrison] : 0);
        }
    }

    private void SetRallyWaitingCount(ref Building rally, int value)
    {
        if (rally.WaitingCount == value) return;
        rally.WaitingCount = value;
        _boardVersion++;
    }

    private bool IsFriendlyRally(int buildingIndex, int team) =>
        buildingIndex >= 0 && !_buildings[buildingIndex].Destroyed && _buildings[buildingIndex].Kind == BuildingRallyPoint && _buildings[buildingIndex].Team == team;

    private int NearestRallyId(int team, Vector2 position)
    {
        float best = float.MaxValue;
        int bestId = -1;
        for (int i = 0; i < _buildingCount; i++)
        {
            if (!IsFriendlyRally(i, team)) continue;
            float distance = position.DistanceSquaredTo(RallyAnchor(_buildings[i]));
            if (distance < best) { best = distance; bestId = _buildings[i].Id; }
        }
        return bestId;
    }

    private static Vector2 RallyAnchor(Building rally) =>
        new(rally.Cell.X + 0.5f, rally.Cell.Y + 0.5f + (rally.Team == TeamEnemy ? 1.25f : -1.25f));

    private int CreateLegionFromMembers(int team, int rallyId, int formation, List<int> members, int start, int count, bool defending)
    {
        if (_legionCount >= MaxLegions || count <= 0) return -1;
        int index = _legionCount++;
        int id = _nextLegionId++;
        _legionRecordIds[index] = id;
        _legionIndexById[id] = index;
        _legionTeams[index] = team;
        _legionRallyIds[index] = rallyId;
        _legionFormations[index] = Math.Clamp(formation, FormationLine, FormationLoose);
        _legionStates[index] = defending ? LegionGathering : LegionMarching;
        _legionDefending[index] = defending ? (byte)1 : (byte)0;
        _legionHeadings[index] = team == TeamEnemy ? Vector2.Down : Vector2.Up;
        int rallyIndex = BuildingIndexFromId(rallyId);
        _legionAnchors[index] = rallyIndex >= 0 ? RallyAnchor(_buildings[rallyIndex]) : _positions[members[start]];
        _legionHasWaypoint[index] = 0;
        _legionGatheringElapsed[index] = 0f;
        _legionDisengageTimers[index] = 0f;
        for (int cursor = 0; cursor < count; cursor++)
        {
            int unit = members[start + cursor];
            _legionIds[unit] = id;
            _rallyPointIds[unit] = -1;
        }
        RebuildLegionSlots(index);
        QueueStructural("legion_launched", team, id, rallyIndex >= 0 ? _buildings[rallyIndex].Cell : CellAt(_legionAnchors[index]), BuildingRallyPoint, count);
        return id;
    }

    private void AddMembersToLegion(int legionIndex, List<int> members, int count)
    {
        int id = _legionRecordIds[legionIndex];
        for (int i = 0; i < count; i++)
        {
            int unit = members[i];
            _legionIds[unit] = id;
            _rallyPointIds[unit] = -1;
        }
        RebuildLegionSlots(legionIndex);
    }

    private void RebuildLegionSlots(int legionIndex)
    {
        int id = _legionRecordIds[legionIndex];
        _legionMeleeCounts[legionIndex] = _legionRangedCounts[legionIndex] = _legionSiegeCounts[legionIndex] = _legionDragonCounts[legionIndex] = 0;
        int live = 0;
        for (int kindOrder = 0; kindOrder < 4; kindOrder++)
        {
            int kind = kindOrder == 0 ? UnitMelee : kindOrder == 1 ? UnitRanged : kindOrder == 2 ? UnitSiege : UnitDragon;
            for (int unit = 0; unit < _unitCount; unit++)
            {
                if (_legionIds[unit] != id || _hp[unit] <= 0f || _kinds[unit] != kind) continue;
                if (kind == UnitMelee) _legionMeleeCounts[legionIndex]++;
                else if (kind == UnitRanged) _legionRangedCounts[legionIndex]++;
                else if (kind == UnitSiege) _legionSiegeCounts[legionIndex]++;
                else _legionDragonCounts[legionIndex]++;
                live++;
            }
        }
        _legionProducedCounts[legionIndex] = live;
        _legionLiveCounts[legionIndex] = live;
        _legionOriginalCounts[legionIndex] = Math.Max(_legionOriginalCounts[legionIndex], live);
        int slot = 0;
        for (int kindOrder = 0; kindOrder < 4; kindOrder++)
        {
            int kind = kindOrder == 0 ? UnitMelee : kindOrder == 1 ? UnitRanged : kindOrder == 2 ? UnitSiege : UnitDragon;
            for (int unit = 0; unit < _unitCount; unit++)
                if (_legionIds[unit] == id && _hp[unit] > 0f && _kinds[unit] == kind) _slotOffsets[unit] = LocalSlotFor(legionIndex, slot++);
        }
    }

    private void UpdateLegions(float delta)
    {
        for (int i = 0; i < _legionCount; i++)
        {
            if (_legionStates[i] == LegionBroken) continue;
            if (_legionDefending[i] != 0)
            {
                int rallyIndex = BuildingIndexFromId(_legionRallyIds[i]);
                if (!IsFriendlyRally(rallyIndex, _legionTeams[i])) { BreakLegion(i); continue; }
                _legionAnchors[i] = RallyAnchor(_buildings[rallyIndex]);
            }
            bool hostile = LegionHasHostile(i);
            if (hostile)
            {
                _legionStates[i] = LegionEngaged;
                _legionDisengageTimers[i] = 0f;
            }
            else if (_legionStates[i] == LegionEngaged)
            {
                _legionDisengageTimers[i] += delta;
                if (_legionDisengageTimers[i] >= BattleConfig.LegionDisengageSeconds)
                    _legionStates[i] = _legionDefending[i] != 0 ? LegionGathering : LegionMarching;
            }
            if (_legionStates[i] != LegionMarching) continue;
            Vector2 direction;
            if (_legionHasWaypoint[i] != 0 && _legionAnchors[i].DistanceTo(_legionWaypoints[i]) > BattleConfig.LegionWaypointTolerance)
                direction = _legionAnchors[i].DirectionTo(_legionWaypoints[i]);
            else
            {
                _legionHasWaypoint[i] = 0;
                direction = _legionTeams[i] == TeamEnemy ? _enemyFlow.DirectionAt(CellAt(_legionAnchors[i])) : _allyFlow.DirectionAt(CellAt(_legionAnchors[i]));
            }
            if (direction.LengthSquared() <= 0.0001f) direction = _legionTeams[i] == TeamEnemy ? Vector2.Down : Vector2.Up;
            _legionHeadings[i] = _legionHeadings[i].Slerp(direction.Normalized(), Mathf.Clamp(delta * BattleConfig.LegionHeadingTurnRate, 0f, 1f)).Normalized();
            _legionAnchors[i] = MoveGround(_legionAnchors[i], _legionHeadings[i] * LegionMinimumSpeed(i) * delta);
        }
    }

    private bool LegionHasHostile(int legionIndex)
    {
        int team = _legionTeams[legionIndex];
        if (NearestHostileUnitIndex(team, _legionAnchors[legionIndex], BattleConfig.LegionEngageRadius, true) >= 0) return true;
        float radiusSq = BattleConfig.LegionEngageRadius * BattleConfig.LegionEngageRadius;
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            if (!building.Destroyed && building.Team != team && _legionAnchors[legionIndex].DistanceSquaredTo(new Vector2(building.Cell.X + 0.5f, building.Cell.Y + 0.5f)) <= radiusSq) return true;
        }
        return false;
    }

    private float LegionMinimumSpeed(int legionIndex)
    {
        float speed = float.MaxValue;
        if (_legionMeleeCounts[legionIndex] > 0) speed = Math.Min(speed, BattleConfig.MeleeSpeed);
        if (_legionRangedCounts[legionIndex] > 0) speed = Math.Min(speed, BattleConfig.RangedSpeed);
        if (_legionSiegeCounts[legionIndex] > 0) speed = Math.Min(speed, BattleConfig.SiegeSpeed);
        if (_legionDragonCounts[legionIndex] > 0) speed = Math.Min(speed, BattleConfig.DragonSpeed);
        return speed == float.MaxValue ? BattleConfig.MeleeSpeed : speed;
    }

    private void EvaluateLegionBroken(int legionIndex)
    {
        if (legionIndex < 0 || _legionStates[legionIndex] == LegionBroken) return;
        if (_legionLiveCounts[legionIndex] >= _legionOriginalCounts[legionIndex] * BattleConfig.LegionBrokenRatio) return;
        BreakLegion(legionIndex);
    }

    private void BreakLegion(int legionIndex)
    {
        if (legionIndex < 0 || _legionStates[legionIndex] == LegionBroken) return;
        _legionStates[legionIndex] = LegionBroken;
        int id = _legionRecordIds[legionIndex];
        for (int i = 0; i < _unitCount; i++) if (_legionIds[i] == id) _legionIds[i] = -1;
        int rallyIndex = BuildingIndexFromId(_legionRallyIds[legionIndex]);
        if (rallyIndex >= 0 && _buildings[rallyIndex].ActiveLegionId == id) _buildings[rallyIndex].ActiveLegionId = -1;
    }

    private void HandleRallyDestroyed(int rallyId)
    {
        for (int i = 0; i < _unitCount; i++) if (_rallyPointIds[i] == rallyId) _rallyPointIds[i] = -1;
        for (int i = 0; i < _legionCount; i++)
            if (_legionRallyIds[i] == rallyId && _legionDefending[i] != 0 && _legionStates[i] != LegionBroken) BreakLegion(i);
    }

    public bool ConfigureRally(int buildingId, int mode, int formation)
    {
        int index = BuildingIndexFromId(buildingId);
        if (index < 0 || _buildings[index].Destroyed || _buildings[index].Kind != BuildingRallyPoint || mode < RallyAdvance || mode > RallyDefend) return false;
        ref Building rally = ref _buildings[index];
        if (rally.RallyMode == RallyDefend && mode == RallyAdvance)
        {
            int legion = LegionIndexFromId(rally.ActiveLegionId);
            if (legion >= 0 && _legionStates[legion] != LegionBroken)
            {
                _legionDefending[legion] = 0;
                _legionStates[legion] = LegionMarching;
            }
            rally.ActiveLegionId = -1;
        }
        rally.RallyMode = mode;
        rally.Formation = Math.Clamp(formation, FormationLine, FormationLoose);
        _events.Add(new GDictionary { ["type"] = "rally_mode_changed", ["team"] = rally.Team, ["building_id"] = rally.Id, ["cell"] = rally.Cell, ["mode"] = mode });
        _boardVersion++;
        return true;
    }

    public GDictionary GetRallyConfig(int buildingId)
    {
        int index = BuildingIndexFromId(buildingId);
        if (index < 0 || _buildings[index].Destroyed || _buildings[index].Kind != BuildingRallyPoint) return new GDictionary();
        Building rally = _buildings[index];
        return new GDictionary { ["id"] = rally.Id, ["team"] = rally.Team, ["mode"] = rally.RallyMode, ["formation"] = rally.Formation, ["waiting_count"] = rally.WaitingCount };
    }

    public bool DemolishRally(int buildingId)
    {
        int index = BuildingIndexFromId(buildingId);
        if (index < 0 || _buildings[index].Destroyed || _buildings[index].Kind != BuildingRallyPoint) return false;
        ApplyBuildingDamage(buildingId, _buildings[index].MaxHp + 1f, _buildings[index].Team);
        return true;
    }

    private bool CreateDebugLegion(int team, GDictionary source, int formation, Vector2 anchor)
    {
        if (_legionCount >= MaxLegions || (team != TeamAlly && team != TeamEnemy)) return false;
        GDictionary template = ValidateTemplate(source);
        var members = new List<int>(TemplateTotal(template));
        int[] counts = { TemplateValue(template, "melee", 0), TemplateValue(template, "ranged", 0), TemplateValue(template, "siege", 0), TemplateValue(template, "dragon", 0) };
        int[] kinds = { UnitMelee, UnitRanged, UnitSiege, UnitDragon };
        for (int role = 0; role < kinds.Length; role++)
            for (int slot = 0; slot < counts[role]; slot++)
            {
                int unitId = SpawnUnit(team, anchor, kinds[role]);
                if (unitId == 0) return false;
                int unit = _indexById[unitId];
                _positions[unit] = anchor;
                members.Add(unit);
            }
        int id = CreateLegionFromMembers(team, -1, formation, members, 0, members.Count, false);
        int legion = LegionIndexFromId(id);
        if (legion >= 0) _legionAnchors[legion] = anchor;
        RebuildBuckets();
        return id > 0;
    }
}
