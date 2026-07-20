using Godot;
using GDictionary = Godot.Collections.Dictionary;
using System;

public partial class BattleSimulation
{
    public const int FormationLine = 0;
    public const int FormationWedge = 1;
    public const int FormationLoose = 2;
    public const int LegionGathering = 0;
    public const int LegionMarching = 1;
    public const int LegionEngaged = 2;
    public const int LegionBroken = 3;

    private const int MaxLegions = 256;
    private readonly int[] _legionRecordIds = new int[MaxLegions];
    private readonly int[] _legionTeams = new int[MaxLegions];
    private readonly int[] _legionBarracksIds = new int[MaxLegions];
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
    private readonly float[] _legionGatheringElapsed = new float[MaxLegions];
    private readonly float[] _legionDisengageTimers = new float[MaxLegions];
    private int _legionCount;
    private int _nextLegionId;

    private void ResetLegions()
    {
        _legionCount = 0;
        _nextLegionId = 1;
        Array.Fill(_legionIds, -1);
        Array.Clear(_slotOffsets);
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
        for (int i = 0; i < local.Length; i++)
            result[i] = right * local[i].X - forward * local[i].Y;
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

    public bool TryBuildBarracks(int team, Vector2I cell, GDictionary source, int formation)
    {
        if (_result.Length != 0 || !Valid(cell) || IsBlocked(cell) || _ownership[Index(cell)] != team || BuildingAt(cell) >= 0)
            return false;
        GDictionary template = ValidateTemplate(source);
        if (!SpendGold(team, BattleConfig.BarracksCost)) return false;
        int id = AddBuildingInternal(team, BuildingBarracks, cell, UnitMelee);
        if (id == 0) { RefundGold(team, BattleConfig.BarracksCost); return false; }
        int buildingIndex = BuildingIndexFromId(id);
        AssignTemplate(ref _buildings[buildingIndex], template, formation);
        _buildings[buildingIndex].SpawnTimer = BattleConfig.BarracksProductionInterval;
        _buildings[buildingIndex].ActiveLegionId = CreateGatheringLegion(buildingIndex);
        QueueStructural("building_built", team, id, cell, BuildingBarracks, UnitMelee);
        RebuildFlowFields();
        RecalculateTerritory(true, true);
        return true;
    }

    private bool SpendGold(int team, int amount)
    {
        if (team == TeamAlly && _allyGold >= amount) { _allyGold -= amount; return true; }
        if (team == TeamEnemy && _enemyGold >= amount) { _enemyGold -= amount; return true; }
        return false;
    }

    private void RefundGold(int team, int amount) { if (team == TeamAlly) _allyGold += amount; else if (team == TeamEnemy) _enemyGold += amount; }

    private void AssignTemplate(ref Building building, GDictionary template, int formation)
    {
        building.MeleeCount = TemplateValue(template, "melee", 0);
        building.RangedCount = TemplateValue(template, "ranged", 0);
        building.SiegeCount = TemplateValue(template, "siege", 0);
        building.DragonCount = TemplateValue(template, "dragon", 0);
        building.Formation = Math.Clamp(formation, FormationLine, FormationLoose);
    }

    private GDictionary BuildingTemplate(Building building) => new()
    {
        ["melee"] = building.MeleeCount, ["ranged"] = building.RangedCount,
        ["siege"] = building.SiegeCount, ["dragon"] = building.DragonCount,
    };

    private int CreateGatheringLegion(int buildingIndex)
    {
        if (_legionCount >= MaxLegions) return -1;
        Building building = _buildings[buildingIndex];
        int index = _legionCount++;
        int id = _nextLegionId++;
        _legionRecordIds[index] = id;
        _legionTeams[index] = building.Team;
        _legionBarracksIds[index] = building.Id;
        _legionFormations[index] = building.Formation;
        _legionStates[index] = LegionGathering;
        _legionMeleeCounts[index] = building.MeleeCount;
        _legionRangedCounts[index] = building.RangedCount;
        _legionSiegeCounts[index] = building.SiegeCount;
        _legionDragonCounts[index] = building.DragonCount;
        _legionProducedCounts[index] = 0;
        _legionOriginalCounts[index] = building.MeleeCount + building.RangedCount + building.SiegeCount + building.DragonCount;
        _legionLiveCounts[index] = 0;
        _legionHeadings[index] = building.Team == TeamEnemy ? Vector2.Down : Vector2.Up;
        _legionAnchors[index] = GatheringAnchor(building.Cell, building.Team);
        _legionWaypoints[index] = building.Waypoint;
        _legionHasWaypoint[index] = building.HasWaypoint ? (byte)1 : (byte)0;
        _legionGatheringElapsed[index] = 0f;
        _legionDisengageTimers[index] = 0f;
        return id;
    }

    private static Vector2 GatheringAnchor(Vector2I cell, int team) =>
        new(cell.X + 0.5f, cell.Y + 0.5f + (team == TeamEnemy ? 1.25f : -1.25f));

    private int LegionIndexFromId(int id)
    {
        for (int i = 0; i < _legionCount; i++) if (_legionRecordIds[i] == id) return i;
        return -1;
    }

    private int NextLegionUnitKind(int legionIndex)
    {
        int produced = _legionProducedCounts[legionIndex];
        if (produced < _legionMeleeCounts[legionIndex]) return UnitMelee;
        produced -= _legionMeleeCounts[legionIndex];
        if (produced < _legionRangedCounts[legionIndex]) return UnitRanged;
        produced -= _legionRangedCounts[legionIndex];
        if (produced < _legionSiegeCounts[legionIndex]) return UnitSiege;
        return UnitDragon;
    }

    private Vector2 LocalSlotFor(int legionIndex, int slotIndex)
    {
        GDictionary template = new()
        {
            ["melee"] = _legionMeleeCounts[legionIndex], ["ranged"] = _legionRangedCounts[legionIndex],
            ["siege"] = _legionSiegeCounts[legionIndex], ["dragon"] = _legionDragonCounts[legionIndex],
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
        Vector2 target = LegionSlotWorldPosition(legion, _slotOffsets[unitIndex]);
        Vector2 delta = target - _positions[unitIndex];
        float weight = _legionStates[legion] == LegionEngaged ? BattleConfig.LegionEngagedSlotWeight : BattleConfig.LegionSlotFollowWeight;
        return delta.LengthSquared() > 0.0001f ? delta.Normalized() * weight : Vector2.Zero;
    }

    private float LegionSpeedForUnit(int unitIndex)
    {
        int legion = LegionIndexFromId(_legionIds[unitIndex]);
        if (legion < 0 || _legionStates[legion] == LegionEngaged) return UnitSpeed(_kinds[unitIndex]);
        float speed = float.MaxValue;
        if (_legionMeleeCounts[legion] > 0) speed = Math.Min(speed, BattleConfig.MeleeSpeed);
        if (_legionRangedCounts[legion] > 0) speed = Math.Min(speed, BattleConfig.RangedSpeed);
        if (_legionSiegeCounts[legion] > 0) speed = Math.Min(speed, BattleConfig.SiegeSpeed);
        if (_legionDragonCounts[legion] > 0) speed = Math.Min(speed, BattleConfig.DragonSpeed);
        return speed == float.MaxValue ? UnitSpeed(_kinds[unitIndex]) : speed;
    }

    private void UpdateLegions(float delta)
    {
        for (int i = 0; i < _legionCount; i++)
        {
            if (_legionStates[i] == LegionBroken) continue;
            if (_legionStates[i] == LegionGathering)
            {
                _legionGatheringElapsed[i] += delta;
                if (_legionLiveCounts[i] > 0 && LegionHasHostile(i))
                {
                    DeployLegion(i);
                    _legionStates[i] = LegionEngaged;
                }
                else if (_legionLiveCounts[i] > 0 && ((_legionProducedCounts[i] >= _legionOriginalCounts[i] && LegionFormationReady(i)) || _legionGatheringElapsed[i] >= BattleConfig.LegionGatheringMaxSeconds))
                    DeployLegion(i);
                continue;
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
                if (_legionDisengageTimers[i] >= BattleConfig.LegionDisengageSeconds) _legionStates[i] = LegionMarching;
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
            float speed = LegionMinimumSpeed(i);
            _legionAnchors[i] = MoveGround(_legionAnchors[i], _legionHeadings[i] * speed * delta);
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

    private void DeployLegion(int legionIndex)
    {
        if (legionIndex < 0 || _legionStates[legionIndex] != LegionGathering) return;
        _legionOriginalCounts[legionIndex] = Math.Max(1, _legionLiveCounts[legionIndex]);
        _legionStates[legionIndex] = LegionMarching;
    }

    private bool LegionFormationReady(int legionIndex)
    {
        int legionId = _legionRecordIds[legionIndex];
        float toleranceSq = BattleConfig.LegionGatherTolerance * BattleConfig.LegionGatherTolerance;
        int found = 0;
        for (int i = 0; i < _unitCount; i++)
        {
            if (_legionIds[i] != legionId || _hp[i] <= 0f) continue;
            found++;
            if (_positions[i].DistanceSquaredTo(LegionSlotWorldPosition(legionIndex, _slotOffsets[i])) > toleranceSq) return false;
        }
        return found == _legionProducedCounts[legionIndex];
    }

    private void EvaluateLegionBroken(int legionIndex)
    {
        if (legionIndex < 0 || _legionStates[legionIndex] == LegionGathering || _legionStates[legionIndex] == LegionBroken) return;
        if (_legionLiveCounts[legionIndex] >= _legionOriginalCounts[legionIndex] * BattleConfig.LegionBrokenRatio) return;
        _legionStates[legionIndex] = LegionBroken;
        int id = _legionRecordIds[legionIndex];
        for (int i = 0; i < _unitCount; i++) if (_legionIds[i] == id) _legionIds[i] = -1;
    }

    public bool ConfigureBarracks(int buildingId, GDictionary source, int formation)
    {
        int index = BuildingIndexFromId(buildingId);
        if (index < 0 || _buildings[index].Destroyed || _buildings[index].Kind != BuildingBarracks) return false;
        AssignTemplate(ref _buildings[index], ValidateTemplate(source), formation);
        _boardVersion++;
        return true;
    }

    public bool SetBarracksWaypoint(int buildingId, Vector2I cell)
    {
        int index = BuildingIndexFromId(buildingId);
        if (index < 0 || _buildings[index].Destroyed || _buildings[index].Kind != BuildingBarracks || !Valid(cell)) return false;
        Vector2 waypoint = new(cell.X + 0.5f, cell.Y + 0.5f);
        _buildings[index].Waypoint = waypoint;
        _buildings[index].HasWaypoint = true;
        for (int i = 0; i < _legionCount; i++) if (_legionBarracksIds[i] == buildingId && _legionStates[i] != LegionBroken) { _legionWaypoints[i] = waypoint; _legionHasWaypoint[i] = 1; }
        _boardVersion++;
        return true;
    }

    public GDictionary GetBarracksConfig(int buildingId)
    {
        int index = BuildingIndexFromId(buildingId);
        if (index < 0 || _buildings[index].Kind != BuildingBarracks) return new GDictionary();
        Building b = _buildings[index];
        return new GDictionary
        {
            ["id"] = b.Id, ["team"] = b.Team, ["template"] = BuildingTemplate(b), ["formation"] = b.Formation,
            ["waypoint"] = b.Waypoint, ["has_waypoint"] = b.HasWaypoint, ["active_legion_id"] = b.ActiveLegionId,
        };
    }

    public bool DemolishBuilding(int buildingId)
    {
        int index = BuildingIndexFromId(buildingId);
        if (index < 0 || _buildings[index].Destroyed || _buildings[index].Kind != BuildingBarracks) return false;
        ref Building b = ref _buildings[index];
        b.Destroyed = true;
        int legion = LegionIndexFromId(b.ActiveLegionId);
        if (legion >= 0) DeployLegion(legion);
        QueueBlockedDelta(Index(b.Cell));
        QueueStructural("building_destroyed", b.Team, b.Id, b.Cell, b.Kind, b.UnitKind);
        _boardVersion++;
        RebuildFlowFields();
        return true;
    }

    private bool CreateDebugLegion(int team, GDictionary source, int formation, Vector2 anchor)
    {
        if (_legionCount >= MaxLegions || (team != TeamAlly && team != TeamEnemy)) return false;
        GDictionary template = ValidateTemplate(source);
        int index = _legionCount++;
        int id = _nextLegionId++;
        _legionRecordIds[index] = id;
        _legionTeams[index] = team;
        _legionBarracksIds[index] = -1;
        _legionFormations[index] = Math.Clamp(formation, FormationLine, FormationLoose);
        _legionStates[index] = LegionMarching;
        _legionMeleeCounts[index] = TemplateValue(template, "melee", 0);
        _legionRangedCounts[index] = TemplateValue(template, "ranged", 0);
        _legionSiegeCounts[index] = TemplateValue(template, "siege", 0);
        _legionDragonCounts[index] = TemplateValue(template, "dragon", 0);
        int total = TemplateTotal(template);
        _legionProducedCounts[index] = 0;
        _legionOriginalCounts[index] = total;
        _legionLiveCounts[index] = 0;
        _legionAnchors[index] = anchor;
        _legionHeadings[index] = team == TeamEnemy ? Vector2.Down : Vector2.Up;
        for (int slot = 0; slot < total; slot++)
        {
            int kind = NextLegionUnitKind(index);
            Vector2 local = LocalSlotFor(index, slot);
            Vector2 position = LegionSlotWorldPosition(index, local);
            int unitId = SpawnUnit(team, position, kind, id, local);
            if (unitId == 0) break;
            _positions[_indexById[unitId]] = position;
            _legionLiveCounts[index]++;
            _legionProducedCounts[index] = slot + 1;
        }
        _legionProducedCounts[index] = _legionLiveCounts[index];
        _legionOriginalCounts[index] = Math.Max(1, _legionLiveCounts[index]);
        RebuildBuckets();
        return _legionLiveCounts[index] == total;
    }
}
