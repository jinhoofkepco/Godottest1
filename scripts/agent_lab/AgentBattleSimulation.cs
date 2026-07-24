using Godot;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Diagnostics;

[GlobalClass]
public partial class AgentBattleSimulation : Node
{
    private readonly Vector2[] _positions = new Vector2[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _velocities = new Vector2[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _nextPositions = new Vector2[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _nextVelocities = new Vector2[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _positionCorrections = new Vector2[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _terrainDetourDirections = new Vector2[AgentBattleConfig.UnitCount];
    private readonly int[] _terrainDetourTicks = new int[AgentBattleConfig.UnitCount];
    private readonly float[] _terrainDetourSides = new float[AgentBattleConfig.UnitCount];
    private readonly int[] _terrainPathParents = new int[AgentBattleConfig.ArenaCellCount];
    private readonly int[] _terrainPathQueue = new int[AgentBattleConfig.ArenaCellCount];
    private readonly int[] _teams = new int[AgentBattleConfig.UnitCount];
    private readonly float[] _hp = new float[AgentBattleConfig.UnitCount];
    private readonly int[] _actions = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _blockedCells = new int[AgentBattleConfig.ArenaCellCount];
    private readonly bool[] _blockedMask = new bool[AgentBattleConfig.ArenaCellCount];
    private readonly int[] _routeIntents = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _actionCommitTicks = new int[AgentBattleConfig.UnitCount];
    private readonly float[] _selectedActionScores = new float[AgentBattleConfig.UnitCount];
    private readonly float[] _yieldSides = new float[AgentBattleConfig.UnitCount];
    private readonly float[] _stuckSeconds = new float[AgentBattleConfig.UnitCount];
    private readonly float[] _progressSampleY = new float[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _progressSamplePositions = new Vector2[AgentBattleConfig.UnitCount];
    private readonly int[] _progressSampleTicks = new int[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _desiredDirections = new Vector2[AgentBattleConfig.UnitCount];
    private readonly float[] _moveSpeeds = new float[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasFlanked = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasYielded = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasCrossedSideRoute = new bool[AgentBattleConfig.UnitCount];
    private readonly int[] _bucketHeads = new int[AgentBattleConfig.ArenaCellCount];
    private readonly int[] _bucketNext = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _bucketCounts = new int[AgentBattleConfig.ArenaCellCount];
    private readonly int[] _actionCounts = new int[AgentBattleConfig.ActionCount];
    private readonly int[] _targets = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _targetReservations = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _decisionBatch = new int[AgentBattleConfig.UnitCount];
    private readonly float[] _attackCooldowns = new float[AgentBattleConfig.UnitCount];
    private readonly float[] _attackPulseTimers = new float[AgentBattleConfig.UnitCount];
    private readonly float[] _pendingDamage = new float[AgentBattleConfig.UnitCount];
    private readonly bool[] _diedThisTick = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _everAttacked = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasCrossedCenter = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasPurposefullyHeld = new bool[AgentBattleConfig.UnitCount];
    private readonly long[] _deathTicks = new long[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _deathPositions = new Vector2[AgentBattleConfig.UnitCount];
    private readonly int[] _replacementCandidates = new int[AgentBattleConfig.UnitCount];
    private readonly bool[] _replacementCounted = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _routeCrossed = new bool[AgentBattleConfig.UnitCount];
    private readonly int[] _physicalRoutes = new int[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _routeCrossingPositions = new Vector2[AgentBattleConfig.UnitCount];
    private readonly bool[] _trapEntered = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _trapEscaped = new bool[AgentBattleConfig.UnitCount];
    private readonly long[] _trapEntryTicks = new long[AgentBattleConfig.UnitCount];
    private readonly int[] _routeCrossings = new int[AgentBattleConfig.RouteCount];

    private int _mode;
    private int _seed;
    private int _scenario;
    private int _blockedCellCount;
    private int _aliveBlue;
    private int _aliveRed;
    private float _elapsed;
    private float _accumulator;
    private string _result = string.Empty;
    private long _tickCount;
    private long _totalTickTicks;
    private long _worstTickTicks;
    private int _flankDecisions;
    private int _yieldDecisions;
    private int _sideCrossings;
    private int _overlapViolations;
    private float _idleAgentSeconds;
    private float _maximumStuckSeconds;
    private int _maximumStuckUnit;
    private Vector2 _maximumStuckPosition;
    private int _maximumStuckAction;
    private int _unitsEverAttacked;
    private int _blueUnitsEverAttacked;
    private int _redUnitsEverAttacked;
    private int _frontlineReplacements;
    private int _crossedCenter;
    private float _intentionalHoldSeconds;
    private int _trapEntriesBlue;
    private int _trapEntriesRed;
    private int _trapEscapesWithin12Seconds;
    private float _maximumTrapDwellSeconds;

    public AgentBattleSimulation() => ResetExperiment();

    public void ResetExperiment(int mode, int seed) =>
        ResetExperiment(mode, seed, AgentBattleConfig.ScenarioBottleneck);

    public void ResetExperiment(
        int mode = AgentBattleConfig.ModeAgent,
        int seed = AgentBattleConfig.DefaultSeed,
        int scenario = AgentBattleConfig.ScenarioBottleneck)
    {
        _mode = mode;
        _seed = seed;
        _scenario = (uint)scenario < AgentBattleConfig.ScenarioCount
            ? scenario
            : AgentBattleConfig.ScenarioBottleneck;
        _aliveBlue = AgentBattleConfig.TeamSize;
        _aliveRed = AgentBattleConfig.TeamSize;
        _elapsed = 0f;
        _accumulator = 0f;
        _result = string.Empty;
        _tickCount = 0;
        _totalTickTicks = 0;
        _worstTickTicks = 0;
        _flankDecisions = 0;
        _yieldDecisions = 0;
        _sideCrossings = 0;
        _overlapViolations = 0;
        _idleAgentSeconds = 0f;
        _maximumStuckSeconds = 0f;
        _maximumStuckUnit = -1;
        _maximumStuckPosition = Vector2.Zero;
        _maximumStuckAction = AgentBattleConfig.ActionAdvance;
        _unitsEverAttacked = 0;
        _blueUnitsEverAttacked = 0;
        _redUnitsEverAttacked = 0;
        _frontlineReplacements = 0;
        _crossedCenter = 0;
        _intentionalHoldSeconds = 0f;
        _trapEntriesBlue = 0;
        _trapEntriesRed = 0;
        _trapEscapesWithin12Seconds = 0;
        _maximumTrapDwellSeconds = 0f;

        Array.Clear(_velocities);
        Array.Clear(_nextPositions);
        Array.Clear(_nextVelocities);
        Array.Clear(_positionCorrections);
        Array.Clear(_terrainDetourDirections);
        Array.Clear(_terrainDetourTicks);
        Array.Clear(_terrainDetourSides);
        Array.Fill(_terrainPathParents, -1);
        Array.Clear(_terrainPathQueue);
        Array.Fill(_hp, AgentBattleConfig.UnitMaxHp);
        Array.Fill(_actions, AgentBattleConfig.ActionAdvance);
        Array.Clear(_routeIntents);
        Array.Clear(_actionCommitTicks);
        Array.Clear(_selectedActionScores);
        Array.Clear(_stuckSeconds);
        Array.Clear(_progressSamplePositions);
        Array.Clear(_progressSampleTicks);
        Array.Clear(_desiredDirections);
        Array.Clear(_hasFlanked);
        Array.Clear(_hasYielded);
        Array.Clear(_hasCrossedSideRoute);
        Array.Clear(_actionCounts);
        Array.Fill(_targets, -1);
        Array.Clear(_targetReservations);
        Array.Clear(_attackCooldowns);
        Array.Clear(_attackPulseTimers);
        Array.Clear(_pendingDamage);
        Array.Clear(_diedThisTick);
        Array.Clear(_everAttacked);
        Array.Clear(_hasCrossedCenter);
        Array.Clear(_hasPurposefullyHeld);
        Array.Fill(_deathTicks, -1);
        Array.Fill(_replacementCandidates, -1);
        Array.Clear(_replacementCounted);
        Array.Clear(_routeCrossed);
        Array.Fill(_physicalRoutes, -1);
        Array.Fill(_routeCrossingPositions, new Vector2(-1f, -1f));
        Array.Clear(_trapEntered);
        Array.Clear(_trapEscaped);
        Array.Fill(_trapEntryTicks, -1);
        Array.Clear(_routeCrossings);
        _actionCounts[AgentBattleConfig.ActionAdvance] = AgentBattleConfig.UnitCount;
        BuildScenario(_scenario);
        SpawnMirroredTeams();
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            int mirroredUnit = index % AgentBattleConfig.TeamSize;
            _yieldSides[index] =
                DeterministicSigned(_seed ^ 0x51F15E, mirroredUnit) < 0f ? -1f : 1f;
            _moveSpeeds[index] = AgentBattleConfig.MoveSpeed
                * (1f + DeterministicSigned(_seed ^ 0x7F4A7C15, mirroredUnit) * 0.045f);
            _progressSampleY[index] = _positions[index].Y;
            _progressSamplePositions[index] = _positions[index];
        }
        RebuildSpatialBuckets();
    }

    public void Step(float delta)
    {
        if (delta <= 0f)
            return;

        _accumulator += delta;
        while (_accumulator + 0.000001f >= AgentBattleConfig.FixedDelta)
        {
            _accumulator -= AgentBattleConfig.FixedDelta;
            FixedStep();
        }
    }

    public void RunTicks(int ticks)
    {
        int count = Math.Max(0, ticks);
        for (int i = 0; i < count; i++)
            FixedStep();
    }

    public GDictionary GetSnapshot() => new()
    {
        ["arena_width"] = AgentBattleConfig.ArenaWidth,
        ["arena_height"] = AgentBattleConfig.ArenaHeight,
        ["mode"] = _mode,
        ["seed"] = _seed,
        ["scenario_id"] = _scenario,
        ["scenario_name"] = ScenarioName(_scenario),
        ["positions"] = (Vector2[])_positions.Clone(),
        ["velocities"] = (Vector2[])_velocities.Clone(),
        ["teams"] = (int[])_teams.Clone(),
        ["hp"] = (float[])_hp.Clone(),
        ["actions"] = (int[])_actions.Clone(),
        ["route_intents"] = (int[])_routeIntents.Clone(),
        ["physical_routes"] = (int[])_physicalRoutes.Clone(),
        ["route_crossing_positions"] = (Vector2[])_routeCrossingPositions.Clone(),
        ["stuck_seconds"] = (float[])_stuckSeconds.Clone(),
        ["targets"] = (int[])_targets.Clone(),
        ["attack_pulses"] = (float[])_attackPulseTimers.Clone(),
        ["alive_blue"] = _aliveBlue,
        ["alive_red"] = _aliveRed,
        ["time"] = _elapsed,
        ["result"] = _result,
        ["blocked_cells"] = _blockedCells.AsSpan(0, _blockedCellCount).ToArray(),
        ["route_waypoints_blue"] = (Vector2[])_routeWaypointsBlue.Clone(),
        ["route_waypoints_red"] = (Vector2[])_routeWaypointsRed.Clone(),
        ["route_navigation_waypoints_blue"] = (Vector2[])_routeNavigationWaypointsBlue.Clone(),
        ["route_navigation_waypoints_red"] = (Vector2[])_routeNavigationWaypointsRed.Clone(),
        ["route_waypoint_counts"] = (int[])_routeWaypointCounts.Clone(),
    };

    public GDictionary GetMetrics()
    {
        float blueRemainingHp = 0f;
        float redRemainingHp = 0f;
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_teams[index] == AgentBattleConfig.TeamBlue)
                blueRemainingHp += _hp[index];
            else
                redRemainingHp += _hp[index];
        }

        int totalTrapEntries = _trapEntriesBlue + _trapEntriesRed;
        float trapEscapeRatio = totalTrapEntries == 0
            ? 0f
            : _trapEscapesWithin12Seconds / (float)totalTrapEntries;
        return new GDictionary
        {
            ["unit_count"] = AgentBattleConfig.UnitCount,
            ["blue_count"] = _aliveBlue,
            ["red_count"] = _aliveRed,
            ["tick_count"] = _tickCount,
            ["average_tick_ms"] = TicksToMilliseconds(_tickCount == 0 ? 0 : _totalTickTicks / (double)_tickCount),
            ["worst_tick_ms"] = TicksToMilliseconds(_worstTickTicks),
            ["action_counts"] = (int[])_actionCounts.Clone(),
            ["flank_decisions"] = _flankDecisions,
            ["yield_decisions"] = _yieldDecisions,
            ["side_crossings"] = _sideCrossings,
            ["side_route_crossings"] = _sideCrossings,
            ["route_crossings"] = (int[])_routeCrossings.Clone(),
            ["frontline_replacements"] = _frontlineReplacements,
            ["idle_agent_seconds"] = _idleAgentSeconds,
            ["pathological_idle_seconds"] = _idleAgentSeconds,
            ["maximum_stuck_seconds"] = _maximumStuckSeconds,
            ["max_continuous_stuck"] = _maximumStuckSeconds,
            ["maximum_stuck_unit"] = _maximumStuckUnit,
            ["maximum_stuck_position"] = _maximumStuckPosition,
            ["maximum_stuck_action"] = _maximumStuckAction,
            ["overlap_violations"] = _overlapViolations,
            ["units_ever_attacked"] = _unitsEverAttacked,
            ["blue_units_ever_attacked"] = _blueUnitsEverAttacked,
            ["red_units_ever_attacked"] = _redUnitsEverAttacked,
            ["blue_remaining_hp"] = blueRemainingHp,
            ["red_remaining_hp"] = redRemainingHp,
            ["trap_entries_blue"] = _trapEntriesBlue,
            ["trap_entries_red"] = _trapEntriesRed,
            ["trap_escapes_within_12s"] = _trapEscapesWithin12Seconds,
            ["trap_escape_ratio"] = trapEscapeRatio,
            ["maximum_trap_dwell_seconds"] = _maximumTrapDwellSeconds,
            ["crossed_center"] = _crossedCenter,
            ["intentional_hold_seconds"] = _intentionalHoldSeconds,
            ["elapsed_seconds"] = _elapsed,
            ["active_participation_ratio"] = ActiveParticipationRatio(),
            ["participation_ratio"] = ActiveParticipationRatio(),
            ["result"] = _result,
        };
    }

    private void FixedStep()
    {
        if (!string.IsNullOrEmpty(_result))
            return;

        long start = Stopwatch.GetTimestamp();
        _elapsed += AgentBattleConfig.FixedDelta;
        RebuildSpatialBuckets();
        RebuildTargetReservations();
        UpdateStaggeredDecisions();
        IntegrateMovement();
        UpdateScenarioRegionMetrics();
        UpdateCrossedCenter();
        UpdateCombat();
        UpdateMovementMetrics();
        UpdateBattleResult();
        RecountActions();
        long elapsedTicks = Stopwatch.GetTimestamp() - start;
        _totalTickTicks += elapsedTicks;
        _worstTickTicks = Math.Max(_worstTickTicks, elapsedTicks);
        _tickCount++;
    }

    private void SpawnMirroredTeams()
    {
        for (int index = 0; index < AgentBattleConfig.TeamSize; index++)
        {
            int rank = index / 5;
            int file = index % 5;
            float stagger = (rank & 1) == 0 ? -0.2f : 0.2f;
            float jitter = DeterministicSigned(_seed, index) * 0.08f;
            float x = 10.7f + file * 1.65f + stagger + jitter;
            float blueY = 29f + rank * 0.75f;

            _teams[index] = AgentBattleConfig.TeamBlue;
            _positions[index] = new Vector2(x, blueY);

            int redIndex = index + AgentBattleConfig.TeamSize;
            _teams[redIndex] = AgentBattleConfig.TeamRed;
            _positions[redIndex] = new Vector2(x, AgentBattleConfig.ArenaHeight - blueY);
        }
    }

    private void RecountActions()
    {
        Array.Clear(_actionCounts);
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
                continue;
            int action = _actions[index];
            if ((uint)action < AgentBattleConfig.ActionCount)
                _actionCounts[action]++;
        }
    }

    private static float DeterministicSigned(int seed, int index)
    {
        uint value = unchecked((uint)seed) ^ unchecked((uint)(index + 1) * 0x9E3779B9u);
        value ^= value >> 16;
        value *= 0x7FEB352Du;
        value ^= value >> 15;
        value *= 0x846CA68Bu;
        value ^= value >> 16;
        return (value / (float)uint.MaxValue) * 2f - 1f;
    }

    private static double TicksToMilliseconds(double ticks) => ticks * 1000.0 / Stopwatch.Frequency;
}
