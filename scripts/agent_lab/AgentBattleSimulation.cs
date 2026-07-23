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

        Array.Clear(_velocities);
        Array.Fill(_hp, AgentBattleConfig.UnitMaxHp);
        Array.Fill(_actions, AgentBattleConfig.ActionAdvance);
        BuildFortification();
        SpawnMirroredTeams();
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
        ["flank_decisions"] = 0,
        ["yield_decisions"] = 0,
        ["side_route_crossings"] = 0,
        ["frontline_replacements"] = 0,
        ["pathological_idle_seconds"] = 0f,
        ["max_continuous_stuck"] = 0f,
        ["overlap_violations"] = 0,
        ["units_ever_attacked"] = 0,
        ["participation_ratio"] = 0f,
    };

    private void FixedStep()
    {
        long start = Stopwatch.GetTimestamp();
        _elapsed += AgentBattleConfig.FixedDelta;
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
                _blockedCells[write++] = y * AgentBattleConfig.ArenaWidth + x;
            }
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
