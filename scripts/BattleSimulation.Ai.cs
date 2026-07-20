using Godot;
using System;

public partial class BattleSimulation
{
    private readonly bool[] _aiEnabled = new bool[3];
    private readonly float[] _aiDecisionTimers = new float[3];
    private readonly int[] _aiBuildCursors = new int[3];
    private readonly int[] _aiDecisions = new int[3];
    private readonly int[] _aiBuilds = new int[3];
    private readonly int[] _aiFailedSearches = new int[3];
    private readonly int[] _aiForcedSpends = new int[3];
    private readonly int[] _aiMaxGold = new int[3];
    private readonly string[] _aiLastReasons = new string[3];
    private int _aiUpdateCursor;

    private void ResetAiControllers()
    {
        for (int team = TeamEnemy; team <= TeamAlly; team++)
        {
            _aiEnabled[team] = team == TeamEnemy;
            _aiDecisionTimers[team] = BattleConfig.AiDecisionInterval;
            _aiBuildCursors[team] = BattleConfig.GridColumns / 2;
            _aiDecisions[team] = _aiBuilds[team] = _aiFailedSearches[team] = _aiForcedSpends[team] = 0;
            _aiMaxGold[team] = TeamGold(team);
            _aiLastReasons[team] = "opening";
        }
        _aiUpdateCursor = TeamEnemy;
    }

    public void SetAiEnabled(int team, bool enabled)
    {
        if (team != TeamEnemy && team != TeamAlly) return;
        _aiEnabled[team] = enabled;
        if (enabled) _aiDecisionTimers[team] = 0f;
    }

    private void UpdateAiControllers(float delta)
    {
        int first = _aiUpdateCursor;
        int second = first == TeamEnemy ? TeamAlly : TeamEnemy;
        UpdateAiTeam(first, delta);
        UpdateAiTeam(second, delta);
        _aiUpdateCursor = second;
    }

    private void UpdateAiTeam(int team, float delta)
    {
        if (!_aiEnabled[team]) return;
        _aiMaxGold[team] = Mathf.Max(_aiMaxGold[team], TeamGold(team));
        _aiDecisionTimers[team] -= delta;
        bool forced = TeamGold(team) > BattleConfig.AiForcedSpendGold;
        if (_aiDecisionTimers[team] > 0f && !forced) return;
        _aiDecisionTimers[team] = BattleConfig.AiDecisionInterval;
        _aiDecisions[team]++;
        ConfigureAiRallies(team);
        int attempts = forced ? 3 : 1;
        for (int attempt = 0; attempt < attempts; attempt++)
        {
            bool built = TryAiEconomyAction(team, forced);
            if (!built) break;
            if (forced) _aiForcedSpends[team]++;
            if (TeamGold(team) <= BattleConfig.AiForcedSpendGold) break;
        }
    }

    private bool TryAiEconomyAction(int team, bool forced)
    {
        int spawners = CountSpawners(team);
        int rallies = CountBuildings(team, BuildingRallyPoint);
        int desiredRallies = spawners >= 4 ? BattleConfig.AiMaxRallyPoints : 1;
        if (rallies < desiredRallies && TeamGold(team) >= BattleConfig.RallyPointCost)
        {
            if (TryAiBuild(team, BuildRallyPoint, true)) { _aiLastReasons[team] = "rally"; return true; }
        }
        if (spawners < BattleConfig.AiMaxSpawners)
        {
            int buildKind = CounterBuildKind(team);
            if (TeamGold(team) < BuildCost(buildKind)) buildKind = BuildMeleeSpawner;
            if (TryAiBuild(team, buildKind, false)) { _aiLastReasons[team] = "counter"; return true; }
        }
        if (forced && TeamGold(team) >= BattleConfig.DefenseTowerCost && TryAiBuild(team, BuildDefenseTower, false))
        {
            _aiLastReasons[team] = "forced_tower";
            return true;
        }
        if (forced)
        {
            int emergencyKind = CounterBuildKind(team);
            if (TeamGold(team) >= BuildCost(emergencyKind) && TryAiBuild(team, emergencyKind, false))
            {
                _aiLastReasons[team] = "forced_spawner";
                return true;
            }
        }
        _aiFailedSearches[team]++;
        _aiLastReasons[team] = forced ? "forced_blocked" : "saving";
        return false;
    }

    private void ConfigureAiRallies(int team)
    {
        float occupancy = team == TeamAlly ? _allyOccupancy : _enemyOccupancy;
        int mode = occupancy < BattleConfig.AiDefendOccupancy ? RallyDefend : RallyAdvance;
        int formation = CounterFormation(team);
        for (int i = 0; i < _buildingCount; i++)
            if (IsFriendlyRally(i, team) && (_buildings[i].RallyMode != mode || _buildings[i].Formation != formation))
                ConfigureRally(_buildings[i].Id, mode, formation);
    }

    private int CounterBuildKind(int team)
    {
        Span<int> hostileCounts = stackalloc int[4];
        for (int i = 0; i < _unitCount; i++)
            if (_hp[i] > 0f && _teams[i] != team) hostileCounts[_kinds[i]]++;
        Span<int> kinds = stackalloc int[4] { UnitMelee, UnitRanged, UnitSiege, UnitDragon };
        float bestScore = float.NegativeInfinity;
        int bestKind = UnitMelee;
        for (int candidate = 0; candidate < kinds.Length; candidate++)
        {
            int kind = kinds[candidate];
            int rotationKind = Math.Max(0, _aiDecisions[team] - 1) % kinds.Length;
            float score = kind == rotationKind ? 0.08f : 0f;
            for (int target = 0; target < hostileCounts.Length; target++)
                score += hostileCounts[target] * Mathf.Max(0f, GetClassDamageMultiplier(kind, target) - 1f);
            if (score > bestScore) { bestScore = score; bestKind = kind; }
        }
        return bestKind switch
        {
            UnitRanged => BuildRangedSpawner,
            UnitSiege => BuildSiegeSpawner,
            UnitDragon => BuildDragonLair,
            _ => BuildMeleeSpawner,
        };
    }

    private int CounterFormation(int team)
    {
        int buildKind = CounterBuildKind(team);
        return buildKind == BuildRangedSpawner ? FormationLoose : buildKind == BuildDragonLair ? FormationWedge : FormationLine;
    }

    private bool TryAiBuild(int team, int buildKind, bool rally)
    {
        int preferredRow = rally
            ? (team == TeamEnemy ? BattleConfig.GridRows / 2 - 7 : BattleConfig.GridRows / 2 + 6)
            : (team == TeamEnemy ? 4 : BattleConfig.GridRows - 5);
        for (int ring = 0; ring < BattleConfig.GridRows; ring++)
        {
            int row = preferredRow + (ring % 2 == 0 ? ring / 2 : -(ring + 1) / 2);
            if (row < 1 || row >= BattleConfig.GridRows - 1) continue;
            for (int offset = 0; offset < BattleConfig.GridColumns; offset++)
            {
                int column = (_aiBuildCursors[team] + offset) % BattleConfig.GridColumns;
                Vector2I cell = new(column, row);
                if (_ownership[Index(cell)] != team || !TryBuild(team, cell, buildKind)) continue;
                _aiBuildCursors[team] = (column + 5) % BattleConfig.GridColumns;
                _aiBuilds[team]++;
                return true;
            }
        }
        return false;
    }

    private int CountBuildings(int team, int kind)
    {
        int count = 0;
        for (int i = 0; i < _buildingCount; i++)
            if (!_buildings[i].Destroyed && _buildings[i].Team == team && _buildings[i].Kind == kind) count++;
        return count;
    }

    private int TeamGold(int team) => team == TeamAlly ? _allyGold : _enemyGold;
}
