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

        long decisionEpoch = _tickCount / AgentBattleConfig.DecisionIntervalTicks;
        bool redFirst = (decisionEpoch & 1L) != 0L;
        int lanes = AgentBattleConfig.TeamSize / AgentBattleConfig.DecisionGroupCount;
        int batchCount = 0;
        for (int laneOffset = 0; laneOffset < lanes; laneOffset++)
        {
            int local = decisionGroup + laneOffset * AgentBattleConfig.DecisionGroupCount;
            int blue = local;
            int red = local + AgentBattleConfig.TeamSize;
            if (redFirst)
            {
                _decisionBatch[batchCount++] = red;
                _decisionBatch[batchCount++] = blue;
            }
            else
            {
                _decisionBatch[batchCount++] = blue;
                _decisionBatch[batchCount++] = red;
            }
        }

        ReserveDecisionTargets(batchCount);
        for (int batchIndex = 0; batchIndex < batchCount; batchIndex++)
            DecideAction(_decisionBatch[batchIndex]);
    }

    private void ReserveDecisionTargets(int batchCount)
    {
        // Release the complete mirrored batch before anyone chooses. Both teams use
        // the same local order and alternate which team goes first; the live ledger
        // then enforces the hard per-target capacity inside this decision batch.
        for (int batchIndex = 0; batchIndex < batchCount; batchIndex++)
        {
            int index = _decisionBatch[batchIndex];
            int previous = _targets[index];
            if (IsCombatTargetValid(index, previous) && _targetReservations[previous] > 0)
                _targetReservations[previous]--;
            _targets[index] = -1;
        }

        for (int batchIndex = 0; batchIndex < batchCount; batchIndex++)
        {
            int index = _decisionBatch[batchIndex];
            if (_hp[index] <= 0f || ShouldRetreat(index))
                continue;
            int target = SelectCombatTarget(index);
            _targets[index] = target;
            if (target >= 0)
                _targetReservations[target]++;
        }
    }

    private void DecideAction(int index)
    {
        if (_hp[index] <= 0f)
            return;

        bool mustRetreat = ShouldRetreat(index);
        if (mustRetreat)
        {
            ReleaseCombatTarget(index);
            SetAction(index, AgentBattleConfig.ActionRetreat, 2.6f, AgentBattleConfig.DefaultCommitTicks);
            return;
        }

        int combatTarget = _targets[index];
        if (_mode == AgentBattleConfig.ModeBaseline)
        {
            _routeIntents[index] = AgentBattleConfig.RouteCenter;
            int baselineAction = combatTarget >= 0 ? AgentBattleConfig.ActionEngage : AgentBattleConfig.ActionAdvance;
            float baselineScore = combatTarget >= 0 ? 1.8f : 1f;
            SetAction(index, baselineAction, baselineScore, AgentBattleConfig.DefaultCommitTicks);
            return;
        }

        LocalPerception perception = SenseLocalArea(index);
        float stuck = _stuckSeconds[index];
        bool approachingBarrier = IsApproachingScenarioBarrier(index);

        if (_routeIntents[index] != AgentBattleConfig.RouteCenter && !HasCompletedRoutePassage(index))
        {
            int committedFlank = _routeIntents[index] == AgentBattleConfig.RouteLeft
                ? AgentBattleConfig.ActionFlankLeft
                : AgentBattleConfig.ActionFlankRight;
            SetAction(index, committedFlank, 3f, AgentBattleConfig.FlankCommitTicks);
            return;
        }

        float advanceScore = 1f + MathF.Min(stuck, 2f) * 0.04f;
        float engageScore = combatTarget >= 0 ? 1.72f : perception.HostilesNear > 0 ? 0.72f : 0.08f;
        bool hasRecentGap = TryGetRecentFriendlyGap(index, out _);
        float fillGapScore = hasRecentGap
            ? 1.92f
            : 0.42f + MathF.Abs(perception.FriendlyLeft - perception.FriendlyRight) * 0.08f;
        float congestion = perception.FriendlyAhead + perception.HostilesNear * 0.5f;
        float flankBase = approachingBarrier
            ? AgentBattleConfig.FlankBaseUtility
                + congestion * AgentBattleConfig.FlankCongestionWeight
                + MathF.Min(stuck, 3f) * AgentBattleConfig.FlankStuckWeight
            : 0.12f;
        int mirroredUnit = index % AgentBattleConfig.TeamSize;
        float personality = DeterministicSigned(_seed ^ 0x34D1B54, mirroredUnit) * 0.12f;
        float leftScore = flankBase + personality;
        float rightScore = flankBase - personality;

        if (perception.FriendlyLeft > perception.FriendlyRight)
            rightScore += 0.18f;
        else if (perception.FriendlyRight > perception.FriendlyLeft)
            leftScore += 0.18f;

        float yieldScore = perception.LowerForwardPriority
            ? 1.34f + MathF.Min(stuck, 2f) * 0.16f
            : 0.1f;
        bool reserveOpportunity = combatTarget < 0 && HasPurposefulHoldContext(index);
        float holdScore = reserveOpportunity
            ? 1.52f
            : 0.18f;

        int bestAction = AgentBattleConfig.ActionAdvance;
        float bestScore = advanceScore;
        ConsiderAction(AgentBattleConfig.ActionEngage, engageScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionFillGap, fillGapScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionFlankLeft, leftScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionFlankRight, rightScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionYield, yieldScore, ref bestAction, ref bestScore);
        ConsiderAction(AgentBattleConfig.ActionHold, holdScore, ref bestAction, ref bestScore);

        int currentAction = _actions[index];
        bool commitmentExpired = _actionCommitTicks[index] <= 0;
        bool decisivelyBetter = bestScore > _selectedActionScores[index] + AgentBattleConfig.ActionHysteresis;
        if (bestAction != currentAction && !commitmentExpired && !decisivelyBetter)
            return;

        if (bestAction == AgentBattleConfig.ActionFlankLeft)
        {
            if (_routeIntents[index] != AgentBattleConfig.RouteLeft)
                _routeWaypointCursors[index] = 0;
            _routeIntents[index] = AgentBattleConfig.RouteLeft;
        }
        else if (bestAction == AgentBattleConfig.ActionFlankRight)
        {
            if (_routeIntents[index] != AgentBattleConfig.RouteRight)
                _routeWaypointCursors[index] = 0;
            _routeIntents[index] = AgentBattleConfig.RouteRight;
        }

        int commitTicks = bestAction switch
        {
            AgentBattleConfig.ActionFlankLeft or AgentBattleConfig.ActionFlankRight => AgentBattleConfig.FlankCommitTicks,
            AgentBattleConfig.ActionYield => AgentBattleConfig.YieldCommitTicks,
            _ => AgentBattleConfig.DefaultCommitTicks,
        };
        SetAction(index, bestAction, bestScore, commitTicks);
    }

    private bool ShouldRetreat(int index) =>
        _mode == AgentBattleConfig.ModeAgent
        && _hp[index] < AgentBattleConfig.UnitMaxHp * AgentBattleConfig.RetreatHpRatio;

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
                                        if (RequiresYield(index, neighbor, distanceSquared))
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

    private bool RequiresYield(int index, int ahead, float currentDistanceSquared)
    {
        if (_tickCount < AgentBattleConfig.DecisionIntervalTicks)
            return false;

        float slowSpeed = AgentBattleConfig.MoveSpeed * AgentBattleConfig.YieldSlowSpeedRatio;
        bool aheadIsBlocked = _velocities[ahead].LengthSquared() < slowSpeed * slowSpeed
            || _stuckSeconds[ahead] >= AgentBattleConfig.DecisionInterval;
        if (aheadIsBlocked)
            return true;

        Vector2 ownVelocity = _velocities[index];
        if (ownVelocity.LengthSquared() < 0.01f)
        {
            Vector2 intended = _desiredDirections[index];
            if (intended.LengthSquared() < 0.01f)
                intended = new Vector2(0f, TeamForward(index));
            ownVelocity = intended.Normalized() * _moveSpeeds[index];
        }

        float prediction = AgentBattleConfig.YieldPredictionSeconds;
        Vector2 ownFuture = _positions[index] + ownVelocity * prediction;
        Vector2 aheadFuture = _positions[ahead] + _velocities[ahead] * prediction;
        float futureDistanceSquared = ownFuture.DistanceSquaredTo(aheadFuture);
        float collisionDistance = AgentBattleConfig.SeparationDistance * 1.05f;
        return futureDistanceSquared < collisionDistance * collisionDistance
            && futureDistanceSquared < currentDistanceSquared;
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
            if (action == AgentBattleConfig.ActionRetreat
                || _actions[index] == AgentBattleConfig.ActionRetreat)
            {
                _stuckSeconds[index] = 0f;
                _progressSampleTicks[index] = 0;
                _progressSampleY[index] = _positions[index].Y;
                _progressSamplePositions[index] = _positions[index];
            }
            if (action == AgentBattleConfig.ActionRetreat)
                PrepareRetreatRoute(index);
            if (action == AgentBattleConfig.ActionFlankLeft || action == AgentBattleConfig.ActionFlankRight)
            {
                _flankDecisions++;
                _hasFlanked[index] = true;
            }
            else if (action == AgentBattleConfig.ActionYield)
            {
                // Report unique agents whose verified blocking episode caused a negotiation.
                if (!_hasYielded[index])
                {
                    _yieldDecisions++;
                    _hasYielded[index] = true;
                }
            }
        }

        _actions[index] = action;
        _selectedActionScores[index] = score;
        _actionCommitTicks[index] = commitTicks;
    }
}
