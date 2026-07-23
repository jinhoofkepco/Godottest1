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
        Vector2 position = _positions[index];
        bool blue = _teams[index] == AgentBattleConfig.TeamBlue;
        int route = _routeIntents[index];
        float destinationY = blue ? 0.7f : AgentBattleConfig.ArenaHeight - 0.7f;

        if (route == AgentBattleConfig.RouteLeft)
        {
            float laneX = BypassLaneX(index, false);
            float stagingY = BypassStagingY(index, blue);
            if (!_hasReachedBypassLane[index])
            {
                if (MathF.Abs(position.X - laneX) <= 0.22f)
                    _hasReachedBypassLane[index] = true;
                else
                    return new Vector2(laneX, stagingY);
            }

            if (blue)
            {
                if (position.Y > 16.65f)
                    return new Vector2(laneX, 16.45f - BypassDepth(index));
            }
            else
            {
                if (position.Y < 19.35f)
                    return new Vector2(laneX, 19.55f + BypassDepth(index));
            }

            return new Vector2(13.5f, destinationY);
        }

        if (route == AgentBattleConfig.RouteRight)
        {
            float laneX = BypassLaneX(index, true);
            float stagingY = BypassStagingY(index, blue);
            if (!_hasReachedBypassLane[index])
            {
                if (MathF.Abs(position.X - laneX) <= 0.22f)
                    _hasReachedBypassLane[index] = true;
                else
                    return new Vector2(laneX, stagingY);
            }

            if (blue)
            {
                if (position.Y > 16.65f)
                    return new Vector2(laneX, 16.45f - BypassDepth(index));
            }
            else
            {
                if (position.Y < 19.35f)
                    return new Vector2(laneX, 19.55f + BypassDepth(index));
            }

            return new Vector2(13.5f, destinationY);
        }

        if (blue)
        {
            if (position.Y > 19.3f)
                return new Vector2(14f, 19.3f);
            if (position.Y > 16.65f)
                return new Vector2(14f, 16.55f);
        }
        else
        {
            if (position.Y < 16.7f)
                return new Vector2(14f, 16.7f);
            if (position.Y < 19.35f)
                return new Vector2(14f, 19.45f);
        }

        return new Vector2(13.5f, destinationY);
    }

    private float BypassLaneX(int index, bool right)
    {
        int localIndex = index % AgentBattleConfig.TeamSize;
        float laneOffset = (localIndex % 2) * 0.62f;
        bool blue = _teams[index] == AgentBattleConfig.TeamBlue;
        if (right)
            return blue ? 25.45f + laneOffset : 26.72f + laneOffset;
        return blue ? 2.55f - laneOffset : 0.66f + laneOffset;
    }

    private static float BypassDepth(int index)
    {
        int localIndex = index % AgentBattleConfig.TeamSize;
        return ((localIndex / 3) % 3) * 0.18f;
    }

    private static float BypassStagingY(int index, bool blue)
    {
        float depth = BypassDepth(index);
        return blue ? 19.45f + depth : 16.55f - depth;
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

            if (!_hasCrossedSideRoute[index] && _routeIntents[index] != AgentBattleConfig.RouteCenter)
            {
                bool outsideWall = _positions[index].X < AgentBattleConfig.FortificationMinX
                    || _positions[index].X > AgentBattleConfig.FortificationMaxX + 1f;
                if (outsideWall && HasPassedFortification(index))
                {
                    _hasCrossedSideRoute[index] = true;
                    _sideCrossings++;
                    _routeIntents[index] = AgentBattleConfig.RouteCenter;
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
                    float forwardProgress = (_positions[index].Y - _progressSampleY[index]) * TeamForward(index);
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

    private bool IsTerrainOpen(Vector2 position)
    {
        float radius = AgentBattleConfig.UnitRadius;
        if (position.X < radius
            || position.X > AgentBattleConfig.ArenaWidth - radius
            || position.Y < radius
            || position.Y > AgentBattleConfig.ArenaHeight - radius)
        {
            return false;
        }

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
                    return false;
            }
        }

        return true;
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
        Vector2 position = _positions[index];
        bool blue = _teams[index] == AgentBattleConfig.TeamBlue;
        float passageX = NearestRetreatPassageX(index);
        if (blue && position.Y < 19.55f)
        {
            if (MathF.Abs(position.X - passageX) > 0.24f)
                return new Vector2(passageX, 16.45f);
            return new Vector2(passageX, 19.65f);
        }
        if (!blue && position.Y > 16.45f)
        {
            if (MathF.Abs(position.X - passageX) > 0.24f)
                return new Vector2(passageX, 19.55f);
            return new Vector2(passageX, 16.35f);
        }

        int localIndex = index % AgentBattleConfig.TeamSize;
        float x = 1.4f + (localIndex % 10) * 2.8f;
        float y = blue
            ? AgentBattleConfig.ArenaHeight - 2f
            : 2f;
        return new Vector2(x, y);
    }

    private float NearestRetreatPassageX(int index)
    {
        float currentX = _positions[index].X;
        float left = BypassLaneX(index, false);
        float center = _teams[index] == AgentBattleConfig.TeamBlue ? 14.35f : 13.65f;
        float right = BypassLaneX(index, true);
        float best = center;
        float bestDistance = MathF.Abs(currentX - center);
        float leftDistance = MathF.Abs(currentX - left);
        if (leftDistance < bestDistance)
        {
            best = left;
            bestDistance = leftDistance;
        }
        if (MathF.Abs(currentX - right) < bestDistance)
            best = right;
        return best;
    }

    private static int CellX(float x) => Math.Clamp((int)MathF.Floor(x), 0, AgentBattleConfig.ArenaWidth - 1);

    private static int CellY(float y) => Math.Clamp((int)MathF.Floor(y), 0, AgentBattleConfig.ArenaHeight - 1);
}
