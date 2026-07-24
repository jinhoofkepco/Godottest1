using Godot;
using System;

public partial class AgentBattleSimulation
{
    private static readonly float[] CandidateAngles =
    {
        0f,
        MathF.PI * 0.125f,
        -MathF.PI * 0.125f,
        MathF.PI * 0.25f,
        -MathF.PI * 0.25f,
        MathF.PI * 0.5f,
        -MathF.PI * 0.5f,
        MathF.PI,
    };

    private void RebuildSpatialBuckets()
    {
        Array.Fill(_bucketHeads, -1);
        Array.Clear(_bucketCounts);

        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
            {
                _bucketNext[index] = -1;
                continue;
            }

            int cell = CellY(_positions[index].Y) * AgentBattleConfig.ArenaWidth + CellX(_positions[index].X);
            _bucketNext[index] = _bucketHeads[cell];
            _bucketHeads[cell] = index;
            _bucketCounts[cell]++;
        }
    }

    private void IntegrateMovement()
    {
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
                continue;

            Vector2 desired = DesiredDirection(index);
            _desiredDirections[index] = desired;
            Vector2 velocity = ChooseCandidateVelocity(index, desired);
            Vector2 next = _positions[index] + velocity * AgentBattleConfig.FixedDelta;

            if (IsTerrainOpen(next))
            {
                _positions[index] = next;
                _velocities[index] = velocity;
            }
            else
            {
                _velocities[index] = Vector2.Zero;
            }
        }

        for (int pass = 0; pass < AgentBattleConfig.PositionCorrectionPasses; pass++)
        {
            RebuildSpatialBuckets();
            CorrectPairOverlaps();
        }
        RebuildSpatialBuckets();
    }

    private Vector2 DesiredDirection(int index)
    {
        int action = _actions[index];
        float forward = TeamForward(index);
        if (action == AgentBattleConfig.ActionRetreat)
        {
            if (IsAtRetreatObjective(index))
                return Vector2.Zero;
            Vector2 retreatOffset = RetreatTarget(index) - _positions[index];
            return retreatOffset.LengthSquared() > 0.0001f ? retreatOffset.Normalized() : new Vector2(0f, -forward);
        }
        if (IsAtObjective(index))
            return Vector2.Zero;
        if (action == AgentBattleConfig.ActionHold)
            return Vector2.Zero;
        if (action == AgentBattleConfig.ActionYield)
            return new Vector2(_yieldSides[index], forward * 0.22f).Normalized();
        if (action == AgentBattleConfig.ActionEngage && IsCombatTargetValid(index, _targets[index]))
        {
            Vector2 targetOffset = _positions[_targets[index]] - _positions[index];
            if (targetOffset.LengthSquared() <= AgentBattleConfig.AttackRange * AgentBattleConfig.AttackRange)
                return Vector2.Zero;
            return targetOffset.Normalized();
        }
        if (action == AgentBattleConfig.ActionFillGap && TryGetRecentFriendlyGap(index, out Vector2 gap))
        {
            Vector2 gapOffset = gap - _positions[index];
            if (gapOffset.LengthSquared() > 0.04f)
                return gapOffset.Normalized();
        }

        Vector2 target = RouteTarget(index);
        if (action == AgentBattleConfig.ActionFillGap)
            target.X += _yieldSides[index] * 0.7f;

        Vector2 offset = target - _positions[index];
        return offset.LengthSquared() > 0.0001f ? offset.Normalized() : new Vector2(0f, forward);
    }

    private Vector2 RouteTarget(int index)
    {
        bool blue = _teams[index] == AgentBattleConfig.TeamBlue;
        float destinationY = blue ? 0.7f : AgentBattleConfig.ArenaHeight - 0.7f;

        int route = Math.Clamp(_routeIntents[index], 0, AgentBattleConfig.RouteCount - 1);
        AdvanceRouteWaypointCursor(index, false);
        int cursor = _routeWaypointCursors[index];
        if (cursor < _routeWaypointCounts[route])
            return RouteWaypoint(index, route, cursor, false);
        return new Vector2(13.5f, destinationY);
    }

    private Vector2 ChooseCandidateVelocity(int index, Vector2 desired)
    {
        if (desired.LengthSquared() < 0.0001f)
            return Vector2.Zero;

        float speed = _moveSpeeds[index];
        Vector2 bestVelocity = Vector2.Zero;
        float bestScore = _mode == AgentBattleConfig.ModeBaseline ? -0.12f : -0.34f;
        int movingCandidateCount = _mode == AgentBattleConfig.ModeBaseline ? 1 : CandidateAngles.Length;

        for (int candidate = 0; candidate < movingCandidateCount; candidate++)
        {
            Vector2 direction = desired.Rotated(CandidateAngles[candidate]);
            Vector2 velocity = direction * speed;
            Vector2 next = _positions[index] + velocity * AgentBattleConfig.FixedDelta;
            if (!IsTerrainOpen(next))
                continue;

            float alignment = direction.Dot(desired);
            float smoothness = _velocities[index].LengthSquared() > 0.001f
                ? direction.Dot(_velocities[index].Normalized())
                : 0f;
            float collisionPenalty = PredictedCollisionPenalty(index, next);
            float score = alignment * 1.7f + smoothness * 0.18f - collisionPenalty;
            if (_actions[index] == AgentBattleConfig.ActionYield && MathF.Sign(direction.X) == MathF.Sign(_yieldSides[index]))
                score += 0.38f;

            if (score > bestScore)
            {
                bestScore = score;
                bestVelocity = velocity;
            }
        }

        return bestVelocity;
    }

    private float PredictedCollisionPenalty(int index, Vector2 predicted)
    {
        int cellX = CellX(predicted.X);
        int cellY = CellY(predicted.Y);
        float penalty = 0f;
        float rangeSquared = AgentBattleConfig.CandidateCollisionRange * AgentBattleConfig.CandidateCollisionRange;

        int minX = Math.Max(0, cellX - 1);
        int maxX = Math.Min(AgentBattleConfig.ArenaWidth - 1, cellX + 1);
        int minY = Math.Max(0, cellY - 1);
        int maxY = Math.Min(AgentBattleConfig.ArenaHeight - 1, cellY + 1);

        for (int y = minY; y <= maxY; y++)
        {
            for (int x = minX; x <= maxX; x++)
            {
                int neighbor = _bucketHeads[y * AgentBattleConfig.ArenaWidth + x];
                while (neighbor >= 0)
                {
                    if (neighbor != index && _hp[neighbor] > 0f)
                    {
                        float distanceSquared = predicted.DistanceSquaredTo(_positions[neighbor]);
                        if (distanceSquared < rangeSquared)
                        {
                            float distance = MathF.Sqrt(MathF.Max(distanceSquared, 0.000001f));
                            float pressure = 1f - distance / AgentBattleConfig.CandidateCollisionRange;
                            float teamWeight = _teams[neighbor] == _teams[index] ? 2.3f : 2.8f;
                            penalty += pressure * teamWeight;
                        }
                    }
                    neighbor = _bucketNext[neighbor];
                }
            }
        }

        return penalty;
    }

    private void CorrectPairOverlaps()
    {
        float minimum = AgentBattleConfig.SeparationDistance;
        float minimumSquared = minimum * minimum;

        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
                continue;

            Vector2 origin = _positions[index];
            int cellX = CellX(origin.X);
            int cellY = CellY(origin.Y);
            int minX = Math.Max(0, cellX - 1);
            int maxX = Math.Min(AgentBattleConfig.ArenaWidth - 1, cellX + 1);
            int minY = Math.Max(0, cellY - 1);
            int maxY = Math.Min(AgentBattleConfig.ArenaHeight - 1, cellY + 1);

            for (int y = minY; y <= maxY; y++)
            {
                for (int x = minX; x <= maxX; x++)
                {
                    int neighbor = _bucketHeads[y * AgentBattleConfig.ArenaWidth + x];
                    while (neighbor >= 0)
                    {
                        if (neighbor > index && _hp[neighbor] > 0f)
                            CorrectPair(index, neighbor, minimum, minimumSquared);
                        neighbor = _bucketNext[neighbor];
                    }
                }
            }
        }
    }

    private void CorrectPair(int first, int second, float minimum, float minimumSquared)
    {
        Vector2 delta = _positions[second] - _positions[first];
        float distanceSquared = delta.LengthSquared();
        if (distanceSquared >= minimumSquared)
            return;

        Vector2 normal;
        float distance;
        if (distanceSquared < 0.000001f)
        {
            normal = ((first + second) & 1) == 0 ? Vector2.Right : Vector2.Left;
            distance = 0f;
        }
        else
        {
            distance = MathF.Sqrt(distanceSquared);
            normal = delta / distance;
        }

        Vector2 correction = normal * ((minimum - distance) * 0.505f);
        Vector2 firstCandidate = _positions[first] - correction;
        Vector2 secondCandidate = _positions[second] + correction;
        bool firstOpen = IsTerrainOpen(firstCandidate);
        bool secondOpen = IsTerrainOpen(secondCandidate);

        if (firstOpen && secondOpen)
        {
            _positions[first] = firstCandidate;
            _positions[second] = secondCandidate;
        }
        else if (firstOpen)
        {
            Vector2 full = _positions[first] - correction * 1.98f;
            if (IsTerrainOpen(full))
                _positions[first] = full;
        }
        else if (secondOpen)
        {
            Vector2 full = _positions[second] + correction * 1.98f;
            if (IsTerrainOpen(full))
                _positions[second] = full;
        }
    }

    private void UpdateMovementMetrics()
    {
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
                continue;

            bool purposefulHold = IsPurposefulHold(index);
            if (purposefulHold)
            {
                _intentionalHoldSeconds += AgentBattleConfig.FixedDelta;
                _hasPurposefullyHeld[index] = true;
            }

            if (_actions[index] != AgentBattleConfig.ActionRetreat
                && !_hasCrossedSideRoute[index]
                && _routeIntents[index] != AgentBattleConfig.RouteCenter)
            {
                if (HasCompletedRoutePassage(index))
                {
                    _hasCrossedSideRoute[index] = true;
                    _sideCrossings++;
                    _routeIntents[index] = AgentBattleConfig.RouteCenter;
                    _routeWaypointCursors[index] =
                        Math.Max(0, _routeWaypointCounts[AgentBattleConfig.RouteCenter] - 1);
                    SetAction(index, AgentBattleConfig.ActionAdvance, 1f, AgentBattleConfig.DefaultCommitTicks);
                }
            }

            if (_actions[index] == AgentBattleConfig.ActionRetreat && IsAtRetreatObjective(index))
            {
                _stuckSeconds[index] = 0f;
                _progressSampleTicks[index] = 0;
                _progressSampleY[index] = _positions[index].Y;
            }
            else if (IsActivelyEngaged(index))
            {
                _stuckSeconds[index] = 0f;
                _progressSampleTicks[index] = 0;
                _progressSampleY[index] = _positions[index].Y;
            }
            else if (IsAtObjective(index))
            {
                _stuckSeconds[index] = 0f;
                _progressSampleTicks[index] = 0;
                _progressSampleY[index] = _positions[index].Y;
            }
            else
            {
                _progressSampleTicks[index]++;
                if (_progressSampleTicks[index] >= AgentBattleConfig.ProgressSampleTicks)
                {
                    float progressDirection = _actions[index] == AgentBattleConfig.ActionRetreat
                        ? -TeamForward(index)
                        : TeamForward(index);
                    float forwardProgress = (_positions[index].Y - _progressSampleY[index]) * progressDirection;
                    float sampleSeconds = _progressSampleTicks[index] * AgentBattleConfig.FixedDelta;
                    if (forwardProgress >= AgentBattleConfig.MinimumForwardProgressPerSample)
                    {
                        _stuckSeconds[index] = 0f;
                    }
                    else
                    {
                        _stuckSeconds[index] += sampleSeconds;
                        if (_stuckSeconds[index] >= AgentBattleConfig.IdleThresholdSeconds && !purposefulHold)
                            _idleAgentSeconds += sampleSeconds;
                    }

                    _progressSampleY[index] = _positions[index].Y;
                    _progressSampleTicks[index] = 0;
                }
            }

            if (_stuckSeconds[index] > _maximumStuckSeconds)
            {
                _maximumStuckSeconds = _stuckSeconds[index];
                _maximumStuckUnit = index;
                _maximumStuckPosition = _positions[index];
                _maximumStuckAction = _actions[index];
            }
        }

        _overlapViolations = CountSevereOverlaps();
    }

    private int CountSevereOverlaps()
    {
        int violations = 0;
        float threshold = AgentBattleConfig.SeparationDistance * 0.76f;
        float thresholdSquared = threshold * threshold;

        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
                continue;
            int cellX = CellX(_positions[index].X);
            int cellY = CellY(_positions[index].Y);
            int minX = Math.Max(0, cellX - 1);
            int maxX = Math.Min(AgentBattleConfig.ArenaWidth - 1, cellX + 1);
            int minY = Math.Max(0, cellY - 1);
            int maxY = Math.Min(AgentBattleConfig.ArenaHeight - 1, cellY + 1);

            for (int y = minY; y <= maxY; y++)
            {
                for (int x = minX; x <= maxX; x++)
                {
                    int neighbor = _bucketHeads[y * AgentBattleConfig.ArenaWidth + x];
                    while (neighbor >= 0)
                    {
                        if (neighbor > index
                            && _hp[neighbor] > 0f
                            && _positions[index].DistanceSquaredTo(_positions[neighbor]) < thresholdSquared)
                        {
                            violations++;
                        }
                        neighbor = _bucketNext[neighbor];
                    }
                }
            }
        }

        return violations;
    }

    private bool IsTerrainOpen(Vector2 position) =>
        IsTerrainOpen(position, AgentBattleConfig.UnitRadius);

    private bool IsTerrainOpen(Vector2 position, float radius)
    {
        if (position.X < radius
            || position.X > AgentBattleConfig.ArenaWidth - radius
            || position.Y < radius
            || position.Y > AgentBattleConfig.ArenaHeight - radius)
        {
            return false;
        }

        return !IsBlockedPoint(position, radius);
    }

    private bool IsBlockedPoint(Vector2 position, float radius)
    {
        int minX = Math.Max(0, (int)MathF.Floor(position.X - radius));
        int maxX = Math.Min(AgentBattleConfig.ArenaWidth - 1, (int)MathF.Floor(position.X + radius));
        int minY = Math.Max(0, (int)MathF.Floor(position.Y - radius));
        int maxY = Math.Min(AgentBattleConfig.ArenaHeight - 1, (int)MathF.Floor(position.Y + radius));

        for (int y = minY; y <= maxY; y++)
        {
            for (int x = minX; x <= maxX; x++)
            {
                int cell = y * AgentBattleConfig.ArenaWidth + x;
                if (!_blockedMask[cell])
                    continue;

                float nearestX = Math.Clamp(position.X, x, x + 1f);
                float nearestY = Math.Clamp(position.Y, y, y + 1f);
                float dx = position.X - nearestX;
                float dy = position.Y - nearestY;
                if (dx * dx + dy * dy < radius * radius)
                    return true;
            }
        }

        return false;
    }

    private bool IsAtObjective(int index)
    {
        return _teams[index] == AgentBattleConfig.TeamBlue
            ? _positions[index].Y <= AgentBattleConfig.ObjectiveMargin
            : _positions[index].Y >= AgentBattleConfig.ArenaHeight - AgentBattleConfig.ObjectiveMargin;
    }

    private bool IsAtRetreatObjective(int index)
    {
        return _teams[index] == AgentBattleConfig.TeamBlue
            ? _positions[index].Y >= AgentBattleConfig.ArenaHeight - AgentBattleConfig.RetreatReserveDepth
            : _positions[index].Y <= AgentBattleConfig.RetreatReserveDepth;
    }

    private Vector2 RetreatTarget(int index)
    {
        bool blue = _teams[index] == AgentBattleConfig.TeamBlue;
        bool needsPassage = _hasBarrier
            && (blue
                ? _positions[index].Y < _barrierBottomY + 0.35f
                : _positions[index].Y > _barrierTopY - 0.35f);
        if (needsPassage)
        {
            int route = Math.Clamp(_routeIntents[index], 0, AgentBattleConfig.RouteCount - 1);
            AdvanceRouteWaypointCursor(index, true);
            int cursor = _routeWaypointCursors[index];
            if (cursor < _routeWaypointCounts[route])
                return RouteWaypoint(index, route, cursor, true);
        }

        int localIndex = index % AgentBattleConfig.TeamSize;
        float x = 1.4f + (localIndex % 10) * 2.8f;
        float y = blue
            ? AgentBattleConfig.ArenaHeight - 2f
            : 2f;
        return new Vector2(x, y);
    }

    private static int CellX(float x) => Math.Clamp((int)MathF.Floor(x), 0, AgentBattleConfig.ArenaWidth - 1);

    private static int CellY(float y) => Math.Clamp((int)MathF.Floor(y), 0, AgentBattleConfig.ArenaHeight - 1);
}
