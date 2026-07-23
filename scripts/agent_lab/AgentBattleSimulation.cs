using Godot;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Diagnostics;

[GlobalClass]
public partial class AgentBattleSimulation : Node
{
    private readonly Vector2[] _positions = new Vector2[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _velocities = new Vector2[AgentBattleConfig.UnitCount];
    private readonly int[] _teams = new int[AgentBattleConfig.UnitCount];
    private readonly float[] _hp = new float[AgentBattleConfig.UnitCount];
    private readonly int[] _actions = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _blockedCells = new int[AgentBattleConfig.BlockedCellCount];
    private readonly bool[] _blockedMask = new bool[AgentBattleConfig.ArenaWidth * AgentBattleConfig.ArenaHeight];
    private readonly int[] _routeIntents = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _actionCommitTicks = new int[AgentBattleConfig.UnitCount];
    private readonly float[] _selectedActionScores = new float[AgentBattleConfig.UnitCount];
    private readonly float[] _yieldSides = new float[AgentBattleConfig.UnitCount];
    private readonly float[] _stuckSeconds = new float[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _tickStartPositions = new Vector2[AgentBattleConfig.UnitCount];
    private readonly Vector2[] _desiredDirections = new Vector2[AgentBattleConfig.UnitCount];
    private readonly float[] _moveSpeeds = new float[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasFlanked = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasYielded = new bool[AgentBattleConfig.UnitCount];
    private readonly bool[] _hasCrossedSideRoute = new bool[AgentBattleConfig.UnitCount];
    private readonly int[] _bucketHeads = new int[AgentBattleConfig.ArenaWidth * AgentBattleConfig.ArenaHeight];
    private readonly int[] _bucketNext = new int[AgentBattleConfig.UnitCount];
    private readonly int[] _bucketCounts = new int[AgentBattleConfig.ArenaWidth * AgentBattleConfig.ArenaHeight];
    private readonly int[] _actionCounts = new int[AgentBattleConfig.ActionCount];

    private int _mode;
    private int _seed;
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

    public AgentBattleSimulation() => ResetExperiment();

    public void ResetExperiment(int mode = AgentBattleConfig.ModeAgent, int seed = AgentBattleConfig.DefaultSeed)
    {
        _mode = mode;
        _seed = seed;
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

        Array.Clear(_velocities);
        Array.Fill(_hp, AgentBattleConfig.UnitMaxHp);
        Array.Fill(_actions, AgentBattleConfig.ActionAdvance);
        Array.Clear(_routeIntents);
        Array.Clear(_actionCommitTicks);
        Array.Clear(_selectedActionScores);
        Array.Clear(_stuckSeconds);
        Array.Clear(_desiredDirections);
        Array.Clear(_hasFlanked);
        Array.Clear(_hasYielded);
        Array.Clear(_hasCrossedSideRoute);
        Array.Clear(_blockedMask);
        Array.Clear(_actionCounts);
        _actionCounts[AgentBattleConfig.ActionAdvance] = AgentBattleConfig.UnitCount;
        BuildFortification();
        SpawnMirroredTeams();
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            _yieldSides[index] = DeterministicSigned(_seed ^ 0x51F15E, index) < 0f ? -1f : 1f;
            _moveSpeeds[index] = AgentBattleConfig.MoveSpeed
                * (1f + DeterministicSigned(_seed ^ 0x7F4A7C15, index) * 0.045f);
            _tickStartPositions[index] = _positions[index];
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
        ["positions"] = (Vector2[])_positions.Clone(),
        ["velocities"] = (Vector2[])_velocities.Clone(),
        ["teams"] = (int[])_teams.Clone(),
        ["hp"] = (float[])_hp.Clone(),
        ["actions"] = (int[])_actions.Clone(),
        ["route_intents"] = (int[])_routeIntents.Clone(),
        ["alive_blue"] = _aliveBlue,
        ["alive_red"] = _aliveRed,
        ["time"] = _elapsed,
        ["result"] = _result,
        ["blocked_cells"] = (int[])_blockedCells.Clone(),
    };

    public GDictionary GetMetrics() => new()
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
        ["frontline_replacements"] = 0,
        ["idle_agent_seconds"] = _idleAgentSeconds,
        ["pathological_idle_seconds"] = _idleAgentSeconds,
        ["maximum_stuck_seconds"] = _maximumStuckSeconds,
        ["max_continuous_stuck"] = _maximumStuckSeconds,
        ["overlap_violations"] = _overlapViolations,
        ["units_ever_attacked"] = 0,
        ["participation_ratio"] = 0f,
    };

    private void FixedStep()
    {
        long start = Stopwatch.GetTimestamp();
        _elapsed += AgentBattleConfig.FixedDelta;
        RebuildSpatialBuckets();
        UpdateStaggeredDecisions();
        IntegrateMovement();
        UpdateMovementMetrics();
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

    private void BuildFortification()
    {
        int write = 0;
        for (int y = AgentBattleConfig.FortificationTopY; y <= AgentBattleConfig.FortificationBottomY; y++)
        {
            for (int x = AgentBattleConfig.FortificationMinX; x <= AgentBattleConfig.FortificationMaxX; x++)
            {
                if (x >= AgentBattleConfig.GateMinX && x <= AgentBattleConfig.GateMaxX)
                    continue;
                int cell = y * AgentBattleConfig.ArenaWidth + x;
                _blockedCells[write++] = cell;
                _blockedMask[cell] = true;
            }
        }
    }

    private void RecountActions()
    {
        Array.Clear(_actionCounts);
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
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
