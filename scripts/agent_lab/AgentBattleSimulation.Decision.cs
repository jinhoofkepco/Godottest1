using Godot;
using System;

public partial class AgentBattleSimulation
{
    private struct LocalPerception
    {
        public int FriendlyAhead;
        public int FriendlyLeft;
        public int FriendlyRight;
        public int HostilesNear;
        public bool LowerForwardPriority;
    }

    private void UpdateStaggeredDecisions()
    {
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_actionCommitTicks[index] > 0)
                _actionCommitTicks[index]--;
        }

        int decisionGroup = (int)(_tickCount % AgentBattleConfig.DecisionIntervalTicks);
        if (decisionGroup >= AgentBattleConfig.DecisionGroupCount)
            return;

        for (int index = decisionGroup; index < AgentBattleConfig.UnitCount; index += AgentBattleConfig.DecisionGroupCount)
            DecideAction(index);
    }

    private void DecideAction(int index)
    {
        if (_hp[index] <= 0f)
            return;

        if (_mode == AgentBattleConfig.ModeBaseline)
        {
            _routeIntents[index] = AgentBattleConfig.RouteCenter;
            SetAction(index, AgentBattleConfig.ActionAdvance, 1f, AgentBattleConfig.DefaultCommitTicks);
            return;
        }

        LocalPerception perception = SenseLocalArea(index);
        float stuck = _stuckSeconds[index];
        float wallDistance = MathF.Abs(_positions[index].Y - 17.5f);
        bool approachingFortification = wallDistance < 8.5f && !HasPassedFortification(index);

        if (_routeIntents[index] != AgentBattleConfig.RouteCenter && !_hasCrossedSideRoute[index])
        {
            int committedFlank = _routeIntents[index] == AgentBattleConfig.RouteLeft
                ? AgentBattleConfig.ActionFlankLeft
                : AgentBattleConfig.ActionFlankRight;
            SetAction(index, committedFlank, 3f, AgentBattleConfig.FlankCommitTicks);
            return;
        }

        float advanceScore = 1f + MathF.Min(stuck, 2f) * 0.04f;
        float engageScore = perception.HostilesNear > 0 ? 0.72f : 0.08f;
        float fillGapScore = 0.42f + MathF.Abs(perception.FriendlyLeft - perception.FriendlyRight) * 0.08f;
        float congestion = perception.FriendlyAhead + perception.HostilesNear * 0.5f;
        float flankBase = approachingFortification
            ? 0.38f + congestion * 0.36f + MathF.Min(stuck, 3f) * 0.28f
            : 0.12f;
        float personality = DeterministicSigned(_seed ^ 0x34D1B54, index) * 0.12f;
        float leftScore = flankBase + personality;
        float rightScore = flankBase - personality;

        if (perception.FriendlyLeft > perception.FriendlyRight)
            rightScore += 0.18f;
        else if (perception.FriendlyRight > perception.FriendlyLeft)
            leftScore += 0.18f;

        float yieldScore = perception.LowerForwardPriority
            ? 1.34f + MathF.Min(stuck, 2f) * 0.16f
            : 0.1f;
        float holdScore = congestion >= 5f ? 0.82f + MathF.Min(stuck, 1f) * 0.08f : 0.18f;
        float retreatScore = _hp[index] < AgentBattleConfig.UnitMaxHp * 0.25f ? 2.4f : 0f;

        int bestAction = AgentBattleConfig.ActionAdvance;
        float bestScore = advanceScore;
        ConsiderAction(AgentBattleConfig.ActionEngage, engageScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionFillGap, fillGapScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionFlankLeft, leftScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionFlankRight, rightScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionYield, yieldScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionHold, holdScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionRetreat, retreatScore, ref bestAction, ref bestScore);

        int currentAction = _actions[index];
        bool commitmentExpired = _actionCommitTicks[index] <= 0;
        bool decisivelyBetter = bestScore > _selectedActionScores[index] + AgentBattleConfig.ActionHysteresis;
        if (bestAction != currentAction && !commitmentExpired && !decisivelyBetter)
            return;

        if (bestAction == AgentBattleConfig.ActionFlankLeft)
            _routeIntents[index] = AgentBattleConfig.RouteLeft;
        else if (bestAction == AgentBattleConfig.ActionFlankRight)
            _routeIntents[index] = AgentBattleConfig.RouteRight;

        int commitTicks = bestAction switch
        {
            AgentBattleConfig.ActionFlankLeft or AgentBattleConfig.ActionFlankRight => AgentBattleConfig.FlankCommitTicks,
            AgentBattleConfig.ActionYield => AgentBattleConfig.YieldCommitTicks,
            _ => AgentBattleConfig.DefaultCommitTicks,
        };
        SetAction(index, bestAction, bestScore, commitTicks);
    }

    private LocalPerception SenseLocalArea(int index)
    {
        LocalPerception result = default;
        Vector2 origin = _positions[index];
        float forward = TeamForward(index);
        int originX = CellX(origin.X);
        int originY = CellY(origin.Y);
        float rangeSquared = AgentBattleConfig.PerceptionRange * AgentBattleConfig.PerceptionRange;

        int minX = Math.Max(0, originX - AgentBattleConfig.PerceptionCellRadius);
        int maxX = Math.Min(AgentBattleConfig.ArenaWidth - 1, originX + AgentBattleConfig.PerceptionCellRadius);
        int minY = Math.Max(0, originY - AgentBattleConfig.PerceptionCellRadius);
        int maxY = Math.Min(AgentBattleConfig.ArenaHeight - 1, originY + AgentBattleConfig.PerceptionCellRadius);

        for (int y = minY; y <= maxY; y++)
        {
            for (int x = minX; x <= maxX; x++)
            {
                int neighbor = _bucketHeads[y * AgentBattleConfig.ArenaWidth + x];
                while (neighbor >= 0)
                {
                    if (neighbor != index && _hp[neighbor] > 0f)
                    {
                        Vector2 offset = _positions[neighbor] - origin;
                        float distanceSquared = offset.LengthSquared();
                        if (distanceSquared <= rangeSquared)
                        {
                            float forwardOffset = offset.Y * forward;
                            if (_teams[neighbor] == _teams[index])
                            {
                                if (forwardOffset > 0.05f && MathF.Abs(offset.X) < 1.15f)
                                {
                                    result.FriendlyAhead++;
                                    if (distanceSquared <= AgentBattleConfig.ForwardBlockRange * AgentBattleConfig.ForwardBlockRange
                                        && HasForwardPriority(neighbor, index))
                                    {
                                        result.LowerForwardPriority = true;
                                    }
                                }

                                if (offset.X < -0.05f)
                                    result.FriendlyLeft++;
                                else if (offset.X > 0.05f)
                                    result.FriendlyRight++;
                            }
                            else if (distanceSquared <= 2.25f)
                            {
                                result.HostilesNear++;
                            }
                        }
                    }

                    neighbor = _bucketNext[neighbor];
                }
            }
        }

        return result;
    }

    private bool HasForwardPriority(int first, int second)
    {
        float firstProgress = ForwardProgress(first);
        float secondProgress = ForwardProgress(second);
        if (MathF.Abs(firstProgress - secondProgress) > 0.02f)
            return firstProgress > secondProgress;
        return first < second;
    }

    private float ForwardProgress(int index)
    {
        return _teams[index] == AgentBattleConfig.TeamBlue
            ? AgentBattleConfig.ArenaHeight - _positions[index].Y
            : _positions[index].Y;
    }

    private float TeamForward(int index) => _teams[index] == AgentBattleConfig.TeamBlue ? -1f : 1f;

    private bool HasPassedFortification(int index)
    {
        return _teams[index] == AgentBattleConfig.TeamBlue
            ? _positions[index].Y < AgentBattleConfig.FortificationTopY - 0.35f
            : _positions[index].Y > AgentBattleConfig.FortificationBottomY + 1.35f;
    }

    private static void ConsiderAction(int action, float score, ref int bestAction, ref float bestScore)
    {
        if (score <= bestScore)
            return;
        bestAction = action;
        bestScore = score;
    }

    private void SetAction(int index, int action, float score, int commitTicks)
    {
        if (_actions[index] != action)
        {
            if (action == AgentBattleConfig.ActionFlankLeft || action == AgentBattleConfig.ActionFlankRight)
            {
                _flankDecisions++;
                _hasFlanked[index] = true;
            }
            else if (action == AgentBattleConfig.ActionYield)
            {
                _yieldDecisions++;
                _hasYielded[index] = true;
            }
        }

        _actions[index] = action;
        _selectedActionScores[index] = score;
        _actionCommitTicks[index] = commitTicks;
    }
}
