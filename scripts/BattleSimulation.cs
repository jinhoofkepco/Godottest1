using Godot;
using GArray = Godot.Collections.Array;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Collections.Generic;
using System.Diagnostics;

[GlobalClass]
public partial class BattleSimulation : Node
{
    public const int TeamNone = 0;
    public const int TeamEnemy = 1;
    public const int TeamAlly = 2;
    public const int BuildingHq = 0;
    public const int BuildingBarracks = 1;
    public const int BuildingDefenseTower = 2;
    public const int BuildingDragonLair = 3;
    public const int UnitMelee = 0;
    public const int UnitRanged = 1;
    public const int UnitDragon = 2;
    public const int UnitSiege = 3;
    public const int BuildDefenseTower = 2;
    public const int BuildBarracks = 0;
    public const int StateAdvance = 0;
    public const int StateAttack = 1;
    public const int StateWait = 2;
    private const int ShotRanged = 0;
    private const int ShotTower = 1;
    private const int ShotHq = 2;
    private const int MaxUnits = 8192;
    private const int MaxBuildings = 96;
    private const int MaxImpacts = 1024;
    private const int MaxGhosts = 1024;
    private const int MaxEvents = 32768;
    private const int SiegeTargetSentinel = -2147483647;

    private struct Building
    {
        public int Id;
        public int Team;
        public int Kind;
        public int UnitKind;
        public Vector2I Cell;
        public float Hp;
        public float MaxHp;
        public float SpawnTimer;
        public float AttackCooldown;
        public bool Destroyed;
        public int MeleeCount;
        public int RangedCount;
        public int SiegeCount;
        public int DragonCount;
        public int Formation;
        public int ActiveLegionId;
        public Vector2 Waypoint;
        public bool HasWaypoint;
    }

    private struct SiegeImpact
    {
        public int Team;
        public Vector2 Origin;
        public Vector2 Target;
        public float Damage;
        public float Remaining;
        public float Duration;
    }

    private struct DeathGhost
    {
        public Vector2 Position;
        public Vector2 Direction;
        public int Team;
        public int Kind;
        public float Remaining;
    }

    private struct RenderEntry : IComparable<RenderEntry>
    {
        public int Index;
        public int GhostIndex;
        public float Y;
        public int CompareTo(RenderEntry other) => Y.CompareTo(other.Y);
    }

    private readonly int[] _ids = new int[MaxUnits];
    private readonly int[] _teams = new int[MaxUnits];
    private readonly int[] _kinds = new int[MaxUnits];
    private readonly int[] _states = new int[MaxUnits];
    private readonly int[] _targetIds = new int[MaxUnits];
    private readonly int[] _lastAttackerTeams = new int[MaxUnits];
    private readonly Vector2[] _positions = new Vector2[MaxUnits];
    private readonly Vector2[] _velocities = new Vector2[MaxUnits];
    private readonly Vector2[] _lungeDirections = new Vector2[MaxUnits];
    private readonly Vector2[] _cachedTargetPositions = new Vector2[MaxUnits];
    private readonly Vector2[] _cachedSteering = new Vector2[MaxUnits];
    private readonly Vector2[] _siegeTargetPositions = new Vector2[MaxUnits];
    private readonly float[] _hp = new float[MaxUnits];
    private readonly float[] _cooldowns = new float[MaxUnits];
    private readonly float[] _speedScales = new float[MaxUnits];
    private readonly float[] _lungeTimers = new float[MaxUnits];
    private readonly float[] _flowBiasRadians = new float[MaxUnits];
    private readonly float[] _cachedTargetRadii = new float[MaxUnits];
    private readonly float[] _hpBarTimers = new float[MaxUnits];
    private readonly byte[] _cachedWaiting = new byte[MaxUnits];
    private readonly int[] _legionIds = new int[MaxUnits];
    private readonly Vector2[] _slotOffsets = new Vector2[MaxUnits];
    private int _unitCount;

    private readonly Building[] _buildings = new Building[MaxBuildings];
    private int _buildingCount;
    private readonly SiegeImpact[] _impacts = new SiegeImpact[MaxImpacts];
    private int _impactCount;
    private readonly DeathGhost[] _ghosts = new DeathGhost[MaxGhosts];
    private int _ghostCount;
    private readonly int[] _indexById = new int[65536];
    private int _nextUnitId;
    private int _nextBuildingId;
    private int _allyHqId;
    private int _enemyHqId;

    private readonly byte[] _ownership = new byte[BattleConfig.CellCount];
    private readonly byte[] _blocked = new byte[BattleConfig.CellCount];
    private readonly int[] _pendingOwnershipCells = new int[BattleConfig.CellCount];
    private readonly byte[] _pendingOwnershipFlags = new byte[BattleConfig.CellCount];
    private int _pendingOwnershipCount;
    private readonly int[] _pendingBlockedCells = new int[BattleConfig.CellCount];
    private readonly byte[] _pendingBlockedFlags = new byte[BattleConfig.CellCount];
    private int _pendingBlockedCount;
    private byte[] _elevation = new byte[BattleConfig.CellCount];
    private readonly TerrainMap _terrain = new(BattleConfig.GridColumns, BattleConfig.GridRows);
    private readonly FlowField _enemyFlow = new(BattleConfig.GridColumns, BattleConfig.GridRows);
    private readonly FlowField _allyFlow = new(BattleConfig.GridColumns, BattleConfig.GridRows);
    private readonly List<int>[] _enemyBuckets = NewBuckets();
    private readonly List<int>[] _allyBuckets = NewBuckets();
    private readonly int[] _enemyDensity = new int[BattleConfig.CellCount];
    private readonly int[] _allyDensity = new int[BattleConfig.CellCount];
    private readonly int[] _enemySiegeDensity = new int[BattleConfig.CellCount];
    private readonly int[] _allySiegeDensity = new int[BattleConfig.CellCount];
    private readonly byte[] _flowBlocked = new byte[BattleConfig.CellCount];

    private readonly RandomNumberGenerator _rng = new();
    private double _tickAccumulator;
    private float _visualClock;
    private float _timeRemaining;
    private int _allyGold;
    private int _enemyGold;
    private float _allyIncomeRemainder;
    private float _enemyIncomeRemainder;
    private float _enemyBuildTimer;
    private int _enemyBuildCursor;
    private int _enemyNextUnitKind;
    private bool _enemyAiEnabled = true;
    private float _congestionTimer;
    private int _nextFlowTeam;
    private float _territoryTimer;
    private float _allyOccupancy;
    private float _enemyOccupancy;
    private string _result = string.Empty;
    private int _decisionCursor;
    private int _boardVersion;

    private int _foundTargetId;
    private int _foundUnitIndex;
    private int _foundBuildingIndex;
    private Vector2 _foundTargetPosition;

    private GArray _events = new();
    private readonly int[] _hitIds = new int[MaxEvents];
    private readonly int[] _hitTeams = new int[MaxEvents];
    private readonly Vector2[] _hitPositions = new Vector2[MaxEvents];
    private readonly byte[] _hitHighGround = new byte[MaxEvents];
    private int _hitCount;
    private readonly byte[] _shotKinds = new byte[MaxEvents];
    private readonly int[] _shotTeams = new int[MaxEvents];
    private readonly Vector2[] _shotOrigins = new Vector2[MaxEvents];
    private readonly Vector2[] _shotTargets = new Vector2[MaxEvents];
    private int _shotCount;
    private readonly int[] _deathIds = new int[MaxEvents];
    private readonly int[] _deathTeams = new int[MaxEvents];
    private readonly int[] _deathKinds = new int[MaxEvents];
    private readonly Vector2[] _deathPositions = new Vector2[MaxEvents];
    private readonly Vector2[] _deathDirections = new Vector2[MaxEvents];
    private int _deathCount;

    private readonly RenderEntry[] _renderEntries = new RenderEntry[MaxUnits + MaxGhosts];
    private readonly RenderEntry[] _dragonEntries = new RenderEntry[MaxUnits];
    private float[] _infantryBuffer = Array.Empty<float>();
    private float[] _enemyDragonBuffer = Array.Empty<float>();
    private float[] _allyDragonBuffer = Array.Empty<float>();
    private float[] _shadowBuffer = Array.Empty<float>();
    private float[] _hpBarBuffer = Array.Empty<float>();
    private float[] _legionBannerBuffer = Array.Empty<float>();
    private float[] _legionGhostBuffer = Array.Empty<float>();
    private readonly GDictionary _renderSnapshot = new();
    private readonly GDictionary _hudSnapshot = new();
    private GDictionary? _boardSnapshot;
    private int _boardSnapshotVersion = -1;

    private bool _profilingEnabled;
    private long _profileTickUsec;
    private long _profileTargetUsec;
    private long _profileSeparationUsec;
    private long _profileTerritoryUsec;
    private long _profileEventUsec;
    private long _profileSnapshotUsec;
    private long _profileWorstTickUsec;
    private long _profileTickCount;
    private int _targetCandidateChecks;
    private int _aoeCandidateChecks;
    private int _siegeImpactsResolved;
    private int _decisionRefreshCount;
    private int _territoryUpdateCount;

    public BattleSimulation() => Reset();

    private static List<int>[] NewBuckets()
    {
        var buckets = new List<int>[BattleConfig.CellCount];
        for (int i = 0; i < buckets.Length; i++)
            buckets[i] = new List<int>(8);
        return buckets;
    }

    public void Reset()
    {
        _unitCount = 0;
        ResetLegions();
        _buildingCount = 0;
        _impactCount = 0;
        _ghostCount = 0;
        Array.Fill(_indexById, -1);
        _nextUnitId = 1;
        _nextBuildingId = 1;
        _tickAccumulator = 0.0;
        _visualClock = 0f;
        _timeRemaining = BattleConfig.MatchDuration;
        _allyGold = BattleConfig.StartGold;
        _enemyGold = BattleConfig.EnemyStartGold;
        _allyIncomeRemainder = 0f;
        _enemyIncomeRemainder = 0f;
        _enemyBuildTimer = BattleConfig.EnemyBuildInterval;
        _enemyBuildCursor = 0;
        _enemyNextUnitKind = UnitMelee;
        _enemyAiEnabled = true;
        _congestionTimer = 0f;
        _nextFlowTeam = TeamEnemy;
        _territoryTimer = BattleConfig.TerritoryUpdateInterval;
        _allyOccupancy = 0.5f;
        _enemyOccupancy = 0.5f;
        _result = string.Empty;
        _decisionCursor = 0;
        ClearPendingBoardDeltas();
        _boardVersion++;
        _boardSnapshot = null;
        _rng.Seed = 731942;
        _events.Clear();
        _hitCount = _shotCount = _deathCount = 0;
        Array.Clear(_blocked);
        for (int row = 0; row < BattleConfig.GridRows; row++)
        {
            byte owner = row < BattleConfig.GridRows / 2 ? (byte)TeamEnemy : (byte)TeamAlly;
            for (int col = 0; col < BattleConfig.GridColumns; col++)
                _ownership[Index(new Vector2I(col, row))] = owner;
        }
        _elevation = _terrain.Generate(
            BattleConfig.TerrainSeed,
            BattleConfig.TerrainHillPairCount,
            BattleConfig.TerrainSummitPairCount,
            BattleConfig.TerrainCliffPairCount,
            BattleConfig.TerrainMinRow,
            BattleConfig.TerrainMaxRow,
            BattleConfig.TerrainDeploymentDepth,
            BattleConfig.TerrainGenerationAttempts);
        _terrain.Elevation = _elevation;
        _enemyHqId = AddBuildingInternal(TeamEnemy, BuildingHq, new Vector2I(BattleConfig.GridColumns / 2, 0), UnitMelee);
        _allyHqId = AddBuildingInternal(TeamAlly, BuildingHq, new Vector2I(BattleConfig.GridColumns / 2, BattleConfig.GridRows - 1), UnitMelee);
        RebuildBuckets();
        RebuildFlowFields();
        RecalculateTerritory(false, false);
        ClearPendingBoardDeltas();
        ResetProfileCounters();
    }

    public void Step(double delta)
    {
        if (delta <= 0.0)
            return;
        _visualClock += (float)delta;
        AdvancePresentation((float)delta);
        if (_result.Length != 0)
            return;
        _tickAccumulator += delta;
        const double fixedDelta = 1.0 / BattleConfig.SimTickRate;
        int ticks = 0;
        while (_tickAccumulator + 0.000001 >= fixedDelta && _result.Length == 0 && ticks < BattleConfig.MaxCatchUpTicks)
        {
            _tickAccumulator -= fixedDelta;
            FixedStep((float)fixedDelta);
            ticks++;
        }
        if (ticks == BattleConfig.MaxCatchUpTicks && _tickAccumulator >= fixedDelta)
            _tickAccumulator %= fixedDelta;
        if (_result.Length == 0)
            CheckTerminalState();
    }

    public bool TryBuild(int team, Vector2I cell, int buildKind)
    {
        if (buildKind == BuildBarracks)
            return TryBuildBarracks(team, cell, PresetTemplate(0), FormationLine);
        if (_result.Length != 0 || buildKind != BuildDefenseTower || !Valid(cell) || IsBlocked(cell))
            return false;
        if (_ownership[Index(cell)] != team || BuildingAt(cell) >= 0)
            return false;
        if (buildKind == BuildDefenseTower && !InsideHqBuildZone(team, cell))
            return false;
        int cost = BuildCost(buildKind);
        if (team == TeamAlly)
        {
            if (_allyGold < cost) return false;
            _allyGold -= cost;
        }
        else if (team == TeamEnemy)
        {
            if (_enemyGold < cost) return false;
            _enemyGold -= cost;
        }
        else return false;

        int kind = BuildingDefenseTower;
        int unitKind = UnitMelee;
        int id = AddBuildingInternal(team, kind, cell, unitKind);
        if (id == 0)
        {
            if (team == TeamAlly) _allyGold += cost;
            else _enemyGold += cost;
            return false;
        }
        QueueStructural("building_built", team, id, cell, kind, unitKind);
        RebuildFlowFields();
        RecalculateTerritory(true, true);
        return true;
    }

    private int SpawnUnit(int team, Vector2 position, int unitKind, int legionId = -1, Vector2 slotOffset = default)
    {
        if (_unitCount >= MaxUnits || (team != TeamAlly && team != TeamEnemy) || unitKind < UnitMelee || unitKind > UnitSiege)
            return 0;
        int index = _unitCount++;
        int id = _nextUnitId++;
        if (id >= _indexById.Length)
            throw new InvalidOperationException("unit id pool exhausted");
        _ids[index] = id;
        _teams[index] = team;
        _kinds[index] = unitKind;
        position.X = Mathf.Clamp(position.X + _rng.RandfRange(-BattleConfig.UnitSpawnXVariation, BattleConfig.UnitSpawnXVariation), 0.2f, BattleConfig.GridColumns - 0.2f);
        _positions[index] = position;
        _hp[index] = UnitMaxHp(unitKind);
        _states[index] = StateAdvance;
        _targetIds[index] = 0;
        _cooldowns[index] = 0f;
        _lastAttackerTeams[index] = TeamNone;
        _speedScales[index] = _rng.RandfRange(1f - BattleConfig.UnitSpeedVariation, 1f + BattleConfig.UnitSpeedVariation);
        _lungeTimers[index] = 0f;
        _lungeDirections[index] = Vector2.Zero;
        _velocities[index] = Vector2.Zero;
        _flowBiasRadians[index] = Mathf.DegToRad(_rng.RandfRange(-BattleConfig.FlowNoiseDegrees, BattleConfig.FlowNoiseDegrees));
        _siegeTargetPositions[index] = new Vector2(-1f, -1f);
        _cachedTargetPositions[index] = new Vector2(-1f, -1f);
        _cachedTargetRadii[index] = 0f;
        _cachedSteering[index] = team == TeamEnemy ? Vector2.Down : Vector2.Up;
        _cachedWaiting[index] = 0;
        _hpBarTimers[index] = 0f;
        _legionIds[index] = legionId;
        _slotOffsets[index] = slotOffset;
        _indexById[id] = index;
        return id;
    }

    private int AddBuildingInternal(int team, int kind, Vector2I cell, int unitKind)
    {
        if (_buildingCount >= MaxBuildings || !Valid(cell) || IsBlocked(cell))
            return 0;
        float maximumHp = kind switch
        {
            BuildingBarracks => BattleConfig.BarracksMaxHp,
            BuildingDefenseTower => BattleConfig.DefenseTowerMaxHp,
            BuildingDragonLair => BattleConfig.DragonLairMaxHp,
            _ => BattleConfig.HqMaxHp,
        };
        float production = kind == BuildingBarracks ? BattleConfig.BarracksProductionInterval : 0f;
        int id = _nextBuildingId++;
        _buildings[_buildingCount++] = new Building
        {
            Id = id, Team = team, Kind = kind, UnitKind = unitKind, Cell = cell,
            Hp = maximumHp, MaxHp = maximumHp, SpawnTimer = production,
            MeleeCount = kind == BuildingBarracks ? 7 : 0,
            RangedCount = kind == BuildingBarracks ? 4 : 0,
            SiegeCount = kind == BuildingBarracks ? 1 : 0,
            DragonCount = 0,
            Formation = FormationLine,
            ActiveLegionId = -1,
        };
        QueueBlockedDelta(Index(cell));
        _boardVersion++;
        return id;
    }

    private void AdvancePresentation(float delta)
    {
        for (int i = 0; i < _unitCount; i++)
            _hpBarTimers[i] = Mathf.Max(0f, _hpBarTimers[i] - delta);
        int ghost = _ghostCount - 1;
        while (ghost >= 0)
        {
            _ghosts[ghost].Remaining -= delta;
            if (_ghosts[ghost].Remaining <= 0f)
                _ghosts[ghost] = _ghosts[--_ghostCount];
            ghost--;
        }
    }

    public void SetProfilingEnabled(bool enabled) => _profilingEnabled = enabled;
    public void ResetProfileCounters()
    {
        _profileTickUsec = _profileTargetUsec = _profileSeparationUsec = _profileTerritoryUsec = _profileEventUsec = _profileSnapshotUsec = _profileWorstTickUsec = 0;
        _profileTickCount = 0;
        _targetCandidateChecks = _aoeCandidateChecks = _siegeImpactsResolved = _decisionRefreshCount = _territoryUpdateCount = 0;
    }

    private static long Usec(long start) => (long)((Stopwatch.GetTimestamp() - start) * 1_000_000.0 / Stopwatch.Frequency);
    private static int Index(Vector2I cell) => cell.Y * BattleConfig.GridColumns + cell.X;
    private static bool Valid(Vector2I cell) => cell.X >= 0 && cell.X < BattleConfig.GridColumns && cell.Y >= 0 && cell.Y < BattleConfig.GridRows;
    private static Vector2I CellAt(Vector2 position) => new(Math.Clamp(Mathf.FloorToInt(position.X), 0, BattleConfig.GridColumns - 1), Math.Clamp(Mathf.FloorToInt(position.Y), 0, BattleConfig.GridRows - 1));
    private bool IsBlocked(Vector2I cell) => Valid(cell) && _blocked[Index(cell)] != 0;

    private void QueueOwnershipDelta(int cellIndex)
    {
        if (_pendingOwnershipFlags[cellIndex] != 0) return;
        _pendingOwnershipFlags[cellIndex] = 1;
        _pendingOwnershipCells[_pendingOwnershipCount++] = cellIndex;
    }

    private void QueueBlockedDelta(int cellIndex)
    {
        if (_pendingBlockedFlags[cellIndex] != 0) return;
        _pendingBlockedFlags[cellIndex] = 1;
        _pendingBlockedCells[_pendingBlockedCount++] = cellIndex;
    }

    private void ClearPendingBoardDeltas()
    {
        _pendingOwnershipCount = 0;
        _pendingBlockedCount = 0;
        Array.Clear(_pendingOwnershipFlags);
        Array.Clear(_pendingBlockedFlags);
    }
}
