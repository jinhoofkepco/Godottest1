using Godot;
using System;

public partial class AgentBattleSimulation
{
    private void RebuildTargetReservations()
    {
        Array.Clear(_targetReservations);
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            int target = _targets[index];
            if (_hp[index] <= 0f || !IsCombatTargetValid(index, target))
            {
                _targets[index] = -1;
                continue;
            }

            _targetReservations[target]++;
        }
    }

    private int SelectCombatTarget(int index)
    {
        int previous = _targets[index];
        if ((uint)previous < AgentBattleConfig.UnitCount && _targetReservations[previous] > 0)
            _targetReservations[previous]--;

        Vector2 origin = _positions[index];
        int originX = CellX(origin.X);
        int originY = CellY(origin.Y);
        int radius = AgentBattleConfig.CombatDetectionCellRadius;
        int minX = Math.Max(0, originX - radius);
        int maxX = Math.Min(AgentBattleConfig.ArenaWidth - 1, originX + radius);
        int minY = Math.Max(0, originY - radius);
        int maxY = Math.Min(AgentBattleConfig.ArenaHeight - 1, originY + radius);
        float rangeSquared = AgentBattleConfig.CombatDetectionRange * AgentBattleConfig.CombatDetectionRange;
        float bestScore = float.MaxValue;
        int bestTarget = -1;

        for (int y = minY; y <= maxY; y++)
        {
            for (int x = minX; x <= maxX; x++)
            {
                int candidate = _bucketHeads[y * AgentBattleConfig.ArenaWidth + x];
                while (candidate >= 0)
                {
                    if (_teams[candidate] != _teams[index]
                        && _hp[candidate] > 0f
                        && _targetReservations[candidate] < AgentBattleConfig.MaxAttackersPerTarget)
                    {
                        float distanceSquared = origin.DistanceSquaredTo(_positions[candidate]);
                        if (distanceSquared <= rangeSquared && HasCombatPassage(origin, _positions[candidate]))
                        {
                            float score = distanceSquared + _targetReservations[candidate] * 1.6f;
                            if (score < bestScore || (MathF.Abs(score - bestScore) < 0.0001f && candidate < bestTarget))
                            {
                                bestScore = score;
                                bestTarget = candidate;
                            }
                        }
                    }

                    candidate = _bucketNext[candidate];
                }
            }
        }

        _targets[index] = bestTarget;
        if (bestTarget >= 0)
            _targetReservations[bestTarget]++;
        return bestTarget;
    }

    private void ReleaseCombatTarget(int index)
    {
        int target = _targets[index];
        if ((uint)target < AgentBattleConfig.UnitCount && _targetReservations[target] > 0)
            _targetReservations[target]--;
        _targets[index] = -1;
    }

    private bool IsCombatTargetValid(int attacker, int target)
    {
        return (uint)target < AgentBattleConfig.UnitCount
            && _hp[target] > 0f
            && _teams[target] != _teams[attacker];
    }

    private bool HasCombatPassage(Vector2 from, Vector2 to)
    {
        float deltaY = to.Y - from.Y;
        if (MathF.Abs(deltaY) < 0.0001f)
            return true;

        float sampleY = 17.5f;
        float t = (sampleY - from.Y) / deltaY;
        if (t <= 0f || t >= 1f)
            return true;

        float crossingX = from.X + (to.X - from.X) * t;
        float radius = AgentBattleConfig.UnitRadius;
        bool leftBypass = crossingX <= AgentBattleConfig.FortificationMinX - radius;
        bool rightBypass = crossingX >= AgentBattleConfig.FortificationMaxX + 1f + radius;
        bool centralGate = crossingX >= AgentBattleConfig.GateMinX + radius
            && crossingX <= AgentBattleConfig.GateMaxX + 1f - radius;
        return leftBypass || rightBypass || centralGate;
    }

    private void UpdateCombat()
    {
        Array.Clear(_pendingDamage);
        Array.Clear(_diedThisTick);

        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_attackPulseTimers[index] > 0f)
                _attackPulseTimers[index] = MathF.Max(0f, _attackPulseTimers[index] - AgentBattleConfig.FixedDelta);
            if (_attackCooldowns[index] > 0f)
                _attackCooldowns[index] = MathF.Max(0f, _attackCooldowns[index] - AgentBattleConfig.FixedDelta);
            if (_hp[index] <= 0f)
                continue;

            int target = _targets[index];
            if (!IsCombatTargetValid(index, target))
                continue;
            if (_positions[index].DistanceSquaredTo(_positions[target])
                > AgentBattleConfig.AttackRange * AgentBattleConfig.AttackRange)
            {
                continue;
            }
            if (!HasCombatPassage(_positions[index], _positions[target]) || _attackCooldowns[index] > 0f)
                continue;

            _pendingDamage[target] += AgentBattleConfig.AttackDamage;
            _attackCooldowns[index] = AgentBattleConfig.AttackInterval;
            _attackPulseTimers[index] = AgentBattleConfig.AttackPulseSeconds;
            // Participation starts only when a unit lands a real, in-range hit.
            if (!_everAttacked[index])
            {
                _everAttacked[index] = true;
                _unitsEverAttacked++;
            }
            CountFrontlineReplacement(index);
        }

        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_pendingDamage[index] <= 0f || _hp[index] <= 0f)
                continue;
            _hp[index] = MathF.Max(0f, _hp[index] - _pendingDamage[index]);
            if (_hp[index] > 0f)
                continue;

            _diedThisTick[index] = true;
            if (_teams[index] == AgentBattleConfig.TeamBlue)
                _aliveBlue--;
            else
                _aliveRed--;
            _velocities[index] = Vector2.Zero;
            _targets[index] = -1;
        }

        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_diedThisTick[index])
                RecordFrontlineDeath(index);
        }
    }

    private void RecordFrontlineDeath(int dead)
    {
        // A gap owns one nearest living rear candidate for a bounded 2.5-second relief window.
        _deathTicks[dead] = _tickCount;
        _deathPositions[dead] = _positions[dead];
        _replacementCandidates[dead] = FindReplacementCandidate(dead);
        _replacementCounted[dead] = false;
    }

    private int FindReplacementCandidate(int dead)
    {
        int team = _teams[dead];
        Vector2 gap = _positions[dead];
        float forward = team == AgentBattleConfig.TeamBlue ? -1f : 1f;
        float rangeSquared = AgentBattleConfig.GapFillDetectionRange * AgentBattleConfig.GapFillDetectionRange;
        int best = -1;
        float bestDistanceSquared = float.MaxValue;

        for (int candidate = 0; candidate < AgentBattleConfig.UnitCount; candidate++)
        {
            if (_hp[candidate] <= 0f || _teams[candidate] != team)
                continue;
            Vector2 offset = gap - _positions[candidate];
            float distanceSquared = offset.LengthSquared();
            if (distanceSquared > rangeSquared || offset.Y * forward < -0.25f)
                continue;

            float assignmentPenalty = HasActiveReplacementAssignment(candidate) ? 4f : 0f;
            float score = distanceSquared + assignmentPenalty;
            if (score < bestDistanceSquared)
            {
                bestDistanceSquared = score;
                best = candidate;
            }
        }

        return best;
    }

    private bool HasActiveReplacementAssignment(int candidate)
    {
        for (int eventIndex = 0; eventIndex < AgentBattleConfig.UnitCount; eventIndex++)
        {
            if (_replacementCandidates[eventIndex] != candidate || _replacementCounted[eventIndex])
                continue;
            long age = _tickCount - _deathTicks[eventIndex];
            if (_deathTicks[eventIndex] >= 0 && age <= AgentBattleConfig.RecentDeathTicks)
                return true;
        }
        return false;
    }

    private bool TryGetRecentFriendlyGap(int index, out Vector2 gap)
    {
        gap = Vector2.Zero;
        float bestDistanceSquared = float.MaxValue;
        bool found = false;

        for (int eventIndex = 0; eventIndex < AgentBattleConfig.UnitCount; eventIndex++)
        {
            if (_replacementCandidates[eventIndex] != index || _replacementCounted[eventIndex])
                continue;
            long age = _tickCount - _deathTicks[eventIndex];
            if (_deathTicks[eventIndex] < 0 || age > AgentBattleConfig.RecentDeathTicks)
                continue;

            float distanceSquared = _positions[index].DistanceSquaredTo(_deathPositions[eventIndex]);
            if (distanceSquared < bestDistanceSquared)
            {
                bestDistanceSquared = distanceSquared;
                gap = _deathPositions[eventIndex];
                found = true;
            }
        }

        return found;
    }

    private void CountFrontlineReplacement(int attacker)
    {
        // A replacement is counted only when that assigned relief unit attacks near the death point.
        float radiusSquared = AgentBattleConfig.ReplacementRadius * AgentBattleConfig.ReplacementRadius;
        for (int eventIndex = 0; eventIndex < AgentBattleConfig.UnitCount; eventIndex++)
        {
            if (_replacementCandidates[eventIndex] != attacker || _replacementCounted[eventIndex])
                continue;
            long age = _tickCount - _deathTicks[eventIndex];
            if (_deathTicks[eventIndex] < 0 || age > AgentBattleConfig.RecentDeathTicks)
                continue;
            if (_positions[attacker].DistanceSquaredTo(_deathPositions[eventIndex]) > radiusSquared)
                continue;

            _replacementCounted[eventIndex] = true;
            _frontlineReplacements++;
        }
    }

    private bool IsActivelyEngaged(int index)
    {
        int action = _actions[index];
        if (action != AgentBattleConfig.ActionEngage && action != AgentBattleConfig.ActionFillGap)
            return false;
        int target = _targets[index];
        return IsCombatTargetValid(index, target)
            && _positions[index].DistanceSquaredTo(_positions[target])
                <= AgentBattleConfig.AttackRange * AgentBattleConfig.AttackRange;
    }

    private bool IsPurposefulHold(int index)
    {
        return _actions[index] == AgentBattleConfig.ActionHold && HasPurposefulHoldContext(index);
    }

    private bool HasPurposefulHoldContext(int index)
    {
        Vector2 origin = _positions[index];
        int cellX = CellX(origin.X);
        int cellY = CellY(origin.Y);
        int radius = 3;
        int minX = Math.Max(0, cellX - radius);
        int maxX = Math.Min(AgentBattleConfig.ArenaWidth - 1, cellX + radius);
        int minY = Math.Max(0, cellY - radius);
        int maxY = Math.Min(AgentBattleConfig.ArenaHeight - 1, cellY + radius);
        float rangeSquared = AgentBattleConfig.PurposefulHoldRange * AgentBattleConfig.PurposefulHoldRange;
        bool hostileNear = false;
        bool friendlyEngagedAhead = false;
        float forward = TeamForward(index);

        for (int y = minY; y <= maxY; y++)
        {
            for (int x = minX; x <= maxX; x++)
            {
                int neighbor = _bucketHeads[y * AgentBattleConfig.ArenaWidth + x];
                while (neighbor >= 0)
                {
                    if (neighbor != index
                        && _hp[neighbor] > 0f
                        && origin.DistanceSquaredTo(_positions[neighbor]) <= rangeSquared)
                    {
                        if (_teams[neighbor] != _teams[index])
                        {
                            hostileNear = true;
                        }
                        else if ((_positions[neighbor].Y - origin.Y) * forward > -1f
                            && IsActivelyEngaged(neighbor))
                        {
                            friendlyEngagedAhead = true;
                        }
                    }
                    neighbor = _bucketNext[neighbor];
                }
            }
        }

        // Tactical reserve time is not pathological idle: contact is near and an ally holds the front.
        return hostileNear && friendlyEngagedAhead;
    }

    private void UpdateCrossedCenter()
    {
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f || _hasCrossedCenter[index] || !HasPassedFortification(index))
                continue;
            _hasCrossedCenter[index] = true;
            _crossedCenter++;
        }
    }

    private float ActiveParticipationRatio()
    {
        // Each unit counts once after combat, penetration, flank, verified yield, or tactical reserve duty.
        int active = 0;
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_everAttacked[index]
                || _hasCrossedCenter[index]
                || _hasFlanked[index]
                || _hasYielded[index]
                || _hasPurposefullyHeld[index])
            {
                active++;
            }
        }
        return active / (float)AgentBattleConfig.UnitCount;
    }

    private void UpdateBattleResult()
    {
        if (_aliveBlue <= 0 || _aliveRed <= 0)
        {
            _result = _aliveBlue == _aliveRed
                ? "DRAW ELIMINATION"
                : _aliveBlue > _aliveRed ? "BLUE ELIMINATION" : "RED ELIMINATION";
            return;
        }

        if (_tickCount + 1 < AgentBattleConfig.MaximumBattleTicks)
            return;

        float blueHp = 0f;
        float redHp = 0f;
        int blueCrossed = 0;
        int redCrossed = 0;
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_teams[index] == AgentBattleConfig.TeamBlue)
            {
                blueHp += _hp[index];
                if (_hasCrossedCenter[index])
                    blueCrossed++;
            }
            else
            {
                redHp += _hp[index];
                if (_hasCrossedCenter[index])
                    redCrossed++;
            }
        }

        if (_aliveBlue != _aliveRed)
            _result = _aliveBlue > _aliveRed ? "BLUE TIME" : "RED TIME";
        else if (MathF.Abs(blueHp - redHp) > 0.01f)
            _result = blueHp > redHp ? "BLUE TIME" : "RED TIME";
        else if (blueCrossed != redCrossed)
            _result = blueCrossed > redCrossed ? "BLUE TIME" : "RED TIME";
        else
            _result = "DRAW TIME";
    }
}
