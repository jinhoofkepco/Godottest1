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

    private static readonly float[] TerrainDetourAngles =
    {
        MathF.PI * 0.25f,
        -MathF.PI * 0.25f,
        MathF.PI * 0.375f,
        -MathF.PI * 0.375f,
        MathF.PI * 0.5f,
        -MathF.PI * 0.5f,
        MathF.PI * 0.625f,
        -MathF.PI * 0.625f,
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
        // Every unit chooses from the same pre-move snapshot. Mutating positions while
        // iterating gave the second team newer information and introduced a team-order bias.
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
            {
                _nextPositions[index] = _positions[index];
                _nextVelocities[index] = Vector2.Zero;
                continue;
            }

            Vector2 desired = DesiredDirection(index);
            _desiredDirections[index] = desired;
            Vector2 velocity = ChooseCandidateVelocity(index, desired);
            Vector2 next = _positions[index] + velocity * AgentBattleConfig.FixedDelta;

            if (IsTerrainOpen(next))
            {
                _nextPositions[index] = next;
                _nextVelocities[index] = velocity;
            }
            else
            {
                _nextPositions[index] = _positions[index];
                _nextVelocities[index] = Vector2.Zero;
            }
        }

        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            _positions[index] = _nextPositions[index];
            _velocities[index] = _nextVelocities[index];
        }

        for (int pass = 0; pass < AgentBattleConfig.PositionCorrectionPasses; pass++)
        {
            RebuildSpatialBuckets();
            AccumulatePairCorrections();
            ApplyPairCorrections();
        }
        ResolveRemainingSevereOverlaps();
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
            Vector2 retreatTarget = RetreatTarget(index);
            Vector2 retreatOffset = retreatTarget - _positions[index];
            Vector2 retreatDirection = retreatOffset.LengthSquared() > 0.0001f
                ? retreatOffset.Normalized()
                : new Vector2(0f, -forward);
            return ResolveTerrainDetour(index, retreatTarget, retreatDirection);
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
        Vector2 routeDirection = offset.LengthSquared() > 0.0001f
            ? offset.Normalized()
            : new Vector2(0f, forward);
        return ResolveTerrainDetour(index, target, routeDirection);
    }

    private Vector2 RouteTarget(int index)
    {
        bool blue = _teams[index] == AgentBattleConfig.TeamBlue;
        float destinationY = blue ? 0.7f : AgentBattleConfig.ArenaHeight - 0.7f;

        int route = Math.Clamp(_routeIntents[index], 0, AgentBattleConfig.RouteCount - 1);
        AdvanceRouteWaypointCursor(index, false);
        SkipPassedRouteWaypoints(index, route);
        int cursor = _routeWaypointCursors[index];
        if (cursor < _routeWaypointCounts[route])
            return NavigationRouteWaypoint(index, route, cursor, false);
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
            float mirroredAngle = CandidateAngles[candidate] * -TeamForward(index);
            Vector2 direction = desired.Rotated(mirroredAngle);
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
        if (_actions[index] == AgentBattleConfig.ActionRetreat)
            return 0f;

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
                        if (neighbor == _targets[index])
                        {
                            neighbor = _bucketNext[neighbor];
                            continue;
                        }
                        float distanceSquared = predicted.DistanceSquaredTo(_positions[neighbor]);
                        if (distanceSquared < rangeSquared)
                        {
                            float distance = MathF.Sqrt(MathF.Max(distanceSquared, 0.000001f));
                            float pressure = 1f - distance / AgentBattleConfig.CandidateCollisionRange;
                            bool friendly = _teams[neighbor] == _teams[index];
                            float teamWeight = friendly
                                ? AgentBattleConfig.FriendlyCollisionPenalty
                                : AgentBattleConfig.HostileCollisionPenalty;
                            if (friendly
                                && _mode == AgentBattleConfig.ModeAgent
                                && _actions[index] == AgentBattleConfig.ActionEngage
                                && _stuckSeconds[index] >= 0.5f
                                && IsCombatTargetValid(index, _targets[index])
                                && _positions[index].DistanceSquaredTo(_positions[_targets[index]])
                                    > AgentBattleConfig.AttackRange * AgentBattleConfig.AttackRange)
                            {
                                teamWeight *= AgentBattleConfig.EngageReliefCollisionScale;
                            }
                            penalty += pressure * teamWeight;
                        }
                    }
                    neighbor = _bucketNext[neighbor];
                }
            }
        }

        return penalty;
    }

    private void AccumulatePairCorrections()
    {
        Array.Clear(_positionCorrections);
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
                            AccumulatePairCorrection(index, neighbor, minimum, minimumSquared);
                        neighbor = _bucketNext[neighbor];
                    }
                }
            }
        }
    }

    private void AccumulatePairCorrection(int first, int second, float minimum, float minimumSquared)
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
        _positionCorrections[first] -= correction;
        _positionCorrections[second] += correction;
    }

    private void ApplyPairCorrections()
    {
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
                continue;

            Vector2 correction = _positionCorrections[index];
            float maximum = AgentBattleConfig.SeparationDistance * 0.72f;
            if (correction.LengthSquared() > maximum * maximum)
                correction = correction.Normalized() * maximum;

            Vector2 candidate = _positions[index] + correction;
            if (IsTerrainOpen(candidate))
            {
                _positions[index] = candidate;
                continue;
            }

            candidate = _positions[index] + correction * 0.5f;
            if (IsTerrainOpen(candidate))
                _positions[index] = candidate;
        }
    }

    private void ResolveRemainingSevereOverlaps()
    {
        for (int pass = 0; pass < AgentBattleConfig.SevereOverlapBufferedPasses; pass++)
        {
            RebuildSpatialBuckets();
            if (CountSevereOverlaps() == 0)
                break;
            AccumulatePairCorrections();
            ApplyPairCorrections();
        }

        for (int pass = 0; pass < AgentBattleConfig.SevereOverlapFallbackPasses; pass++)
        {
            RebuildSpatialBuckets();
            if (!ResolveSevereOverlapPass(pass))
                break;
        }
    }

    private bool ResolveSevereOverlapPass(int pass)
    {
        float severeDistance = AgentBattleConfig.SeparationDistance * 0.76f;
        float severeDistanceSquared = severeDistance * severeDistance;
        bool corrected = false;
        bool reverseOrder = ((_tickCount + pass) & 1L) != 0L;
        for (int order = 0; order < AgentBattleConfig.UnitCount; order++)
        {
            int ordered = reverseOrder
                ? AgentBattleConfig.UnitCount - 1 - order
                : order;
            int first = InterleavedUnitIndex(ordered);
            if (_hp[first] <= 0f)
                continue;

            int firstKey = InterleavedOrderKey(first);
            Vector2 origin = _positions[first];
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
                    int second = _bucketHeads[y * AgentBattleConfig.ArenaWidth + x];
                    while (second >= 0)
                    {
                        int secondKey = InterleavedOrderKey(second);
                        bool ownsPair = reverseOrder
                            ? secondKey < firstKey
                            : secondKey > firstKey;
                        if (ownsPair
                            && _hp[second] > 0f
                            && _positions[first].DistanceSquaredTo(_positions[second])
                                < severeDistanceSquared)
                        {
                            corrected |= ResolveSeverePair(first, second);
                        }
                        second = _bucketNext[second];
                    }
                }
            }
        }
        return corrected;
    }

    private static int InterleavedUnitIndex(int order)
    {
        int local = order >> 1;
        int team = order & 1;
        return local + team * AgentBattleConfig.TeamSize;
    }

    private static int InterleavedOrderKey(int index)
    {
        int team = index / AgentBattleConfig.TeamSize;
        int local = index % AgentBattleConfig.TeamSize;
        return (local << 1) + team;
    }

    private bool ResolveSeverePair(int first, int second)
    {
        Vector2 delta = _positions[second] - _positions[first];
        float distanceSquared = delta.LengthSquared();
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

        float penetration = AgentBattleConfig.SeparationDistance - distance;
        if (penetration <= 0f)
            return false;

        Vector2 halfCorrection = normal * (penetration * 0.505f);
        Vector2 firstCandidate = _positions[first] - halfCorrection;
        Vector2 secondCandidate = _positions[second] + halfCorrection;
        bool firstOpen = IsTerrainOpen(firstCandidate);
        bool secondOpen = IsTerrainOpen(secondCandidate);
        if (firstOpen && secondOpen)
        {
            _positions[first] = firstCandidate;
            _positions[second] = secondCandidate;
            return true;
        }

        Vector2 fullCorrection = normal * (penetration * 1.01f);
        if (firstOpen && IsTerrainOpen(_positions[first] - fullCorrection))
        {
            _positions[first] -= fullCorrection;
            return true;
        }
        if (secondOpen && IsTerrainOpen(_positions[second] + fullCorrection))
        {
            _positions[second] += fullCorrection;
            return true;
        }
        return false;
    }

    private Vector2 ResolveTerrainDetour(int index, Vector2 target, Vector2 desired)
    {
        if (!_hasBarrier || desired.LengthSquared() < 0.0001f)
        {
            ClearTerrainDetour(index);
            return desired;
        }

        Vector2 origin = _positions[index];
        if (HasTerrainPassage(origin, target))
        {
            ClearTerrainDetour(index);
            return desired;
        }

        if (TryGetTerrainPathDirection(origin, target, out Vector2 pathDirection))
        {
            ClearTerrainDetour(index);
            return pathDirection;
        }

        if (_terrainDetourTicks[index] > 0)
        {
            Vector2 committed = _terrainDetourDirections[index];
            _terrainDetourTicks[index]--;
            if (TerrainClearance(origin, committed) >= AgentBattleConfig.TerrainDetourSampleStep)
                return committed;
        }

        Vector2 detour = SelectTerrainDetour(index, desired);
        _terrainDetourDirections[index] = detour;
        _terrainDetourTicks[index] = AgentBattleConfig.TerrainDetourCommitTicks;
        return detour;
    }

    private bool TryGetTerrainPathDirection(Vector2 origin, Vector2 target, out Vector2 direction)
    {
        direction = Vector2.Zero;
        int start = CellY(origin.Y) * AgentBattleConfig.ArenaWidth + CellX(origin.X);
        int goal = CellY(target.Y) * AgentBattleConfig.ArenaWidth + CellX(target.X);
        if (_blockedMask[start] || _blockedMask[goal])
            return false;
        if (start == goal)
        {
            Vector2 direct = target - origin;
            direction = direct.LengthSquared() > 0.0001f ? direct.Normalized() : Vector2.Zero;
            return direction.LengthSquared() > 0.0001f;
        }

        Array.Fill(_terrainPathParents, -1);
        int read = 0;
        int write = 0;
        _terrainPathQueue[write++] = goal;
        _terrainPathParents[goal] = goal;

        while (read < write && _terrainPathParents[start] < 0)
        {
            int cell = _terrainPathQueue[read++];
            int x = cell % AgentBattleConfig.ArenaWidth;
            int y = cell / AgentBattleConfig.ArenaWidth;
            VisitTerrainPathNeighbor(cell, x - 1, y, ref write);
            VisitTerrainPathNeighbor(cell, x + 1, y, ref write);
            VisitTerrainPathNeighbor(cell, x, y - 1, ref write);
            VisitTerrainPathNeighbor(cell, x, y + 1, ref write);
        }

        int next = _terrainPathParents[start];
        if (next < 0)
            return false;

        Vector2 nextCenter = new(
            next % AgentBattleConfig.ArenaWidth + 0.5f,
            next / AgentBattleConfig.ArenaWidth + 0.5f);
        Vector2 offset = nextCenter - origin;
        if (offset.LengthSquared() < 0.04f)
        {
            int following = _terrainPathParents[next];
            if (following >= 0 && following != next)
            {
                nextCenter = new Vector2(
                    following % AgentBattleConfig.ArenaWidth + 0.5f,
                    following / AgentBattleConfig.ArenaWidth + 0.5f);
                offset = nextCenter - origin;
            }
        }

        direction = offset.LengthSquared() > 0.0001f ? offset.Normalized() : Vector2.Zero;
        return direction.LengthSquared() > 0.0001f;
    }

    private void VisitTerrainPathNeighbor(int parent, int x, int y, ref int write)
    {
        if ((uint)x >= AgentBattleConfig.ArenaWidth || (uint)y >= AgentBattleConfig.ArenaHeight)
            return;
        int cell = y * AgentBattleConfig.ArenaWidth + x;
        if (_blockedMask[cell] || _terrainPathParents[cell] >= 0)
            return;
        _terrainPathParents[cell] = parent;
        _terrainPathQueue[write++] = cell;
    }

    private Vector2 SelectTerrainDetour(int index, Vector2 desired)
    {
        float teamMirror = -TeamForward(index);
        float preferredSide = _terrainDetourSides[index];
        if (MathF.Abs(preferredSide) < 0.5f)
        {
            int localIndex = index % AgentBattleConfig.TeamSize;
            preferredSide = DeterministicSigned(_seed ^ 0x2C9277B5, localIndex) < 0f ? -1f : 1f;
        }

        Vector2 bestDirection = desired;
        float bestScore = float.NegativeInfinity;
        float bestSide = preferredSide;
        for (int candidate = 0; candidate < TerrainDetourAngles.Length; candidate++)
        {
            float canonicalAngle = TerrainDetourAngles[candidate];
            Vector2 direction = desired.Rotated(canonicalAngle * teamMirror);
            float clearance = TerrainClearance(_positions[index], direction);
            if (clearance < AgentBattleConfig.TerrainDetourSampleStep)
                continue;

            float side = MathF.Sign(canonicalAngle);
            float sideContinuity = side == preferredSide ? 0.34f : 0f;
            float forwardProgress = direction.Y * TeamForward(index);
            float score = clearance * 1.8f
                + direction.Dot(desired) * 0.42f
                + forwardProgress * 0.12f
                + sideContinuity;
            if (score <= bestScore)
                continue;

            bestScore = score;
            bestDirection = direction;
            bestSide = side;
        }

        _terrainDetourSides[index] = bestSide;
        return bestDirection.Normalized();
    }

    private float TerrainClearance(Vector2 origin, Vector2 direction)
    {
        Vector2 normalized = direction.Normalized();
        float distance = AgentBattleConfig.TerrainDetourSampleStep;
        float lastOpen = 0f;
        while (distance <= AgentBattleConfig.TerrainDetourProbeDistance + 0.0001f)
        {
            if (!IsTerrainOpen(origin + normalized * distance))
                break;
            lastOpen = distance;
            distance += AgentBattleConfig.TerrainDetourSampleStep;
        }
        return lastOpen;
    }

    private bool HasTerrainPassage(Vector2 from, Vector2 to)
    {
        float distance = from.DistanceTo(to);
        int steps = Math.Max(1, Mathf.CeilToInt(distance / AgentBattleConfig.TerrainDetourSampleStep));
        for (int step = 1; step < steps; step++)
        {
            Vector2 sample = from.Lerp(to, step / (float)steps);
            if (!IsTerrainOpen(sample))
                return false;
        }
        return true;
    }

    private void ClearTerrainDetour(int index)
    {
        _terrainDetourDirections[index] = Vector2.Zero;
        _terrainDetourTicks[index] = 0;
        _terrainDetourSides[index] = 0f;
    }

    private void SkipPassedRouteWaypoints(int index, int route)
    {
        int cursor = _routeWaypointCursors[index];
        int count = _routeWaypointCounts[route];
        float forward = TeamForward(index);
        while (cursor < count)
        {
            Vector2 waypoint = NavigationRouteWaypoint(index, route, cursor, false);
            if ((waypoint.Y - _positions[index].Y) * forward >= -0.35f)
                break;
            cursor++;
        }
        _routeWaypointCursors[index] = cursor;
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
                _progressSamplePositions[index] = _positions[index];
            }
            else if (IsActivelyEngaged(index))
            {
                _stuckSeconds[index] = 0f;
                _progressSampleTicks[index] = 0;
                _progressSampleY[index] = _positions[index].Y;
                _progressSamplePositions[index] = _positions[index];
            }
            else if (IsAtObjective(index))
            {
                _stuckSeconds[index] = 0f;
                _progressSampleTicks[index] = 0;
                _progressSampleY[index] = _positions[index].Y;
                _progressSamplePositions[index] = _positions[index];
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
                    if (_actions[index] == AgentBattleConfig.ActionRetreat
                        || (_mode == AgentBattleConfig.ModeAgent
                            && _actions[index] == AgentBattleConfig.ActionEngage
                            && IsCombatTargetValid(index, _targets[index])))
                    {
                        forwardProgress = _positions[index].DistanceTo(_progressSamplePositions[index]);
                    }
                    float sampleSeconds = _progressSampleTicks[index] * AgentBattleConfig.FixedDelta;
                    float requiredProgress = _mode == AgentBattleConfig.ModeAgent
                        && _actions[index] == AgentBattleConfig.ActionEngage
                        ? AgentBattleConfig.MinimumForwardProgressPerSample * 0.5f
                        : AgentBattleConfig.MinimumForwardProgressPerSample;
                    if (forwardProgress >= requiredProgress)
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
                    _progressSamplePositions[index] = _positions[index];
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

        _overlapViolations = Math.Max(_overlapViolations, CountSevereOverlaps());
    }

    private void UpdateScenarioRegionMetrics()
    {
        for (int index = 0; index < AgentBattleConfig.UnitCount; index++)
        {
            if (_hp[index] <= 0f)
                continue;

            if (_scenario == AgentBattleConfig.ScenarioCornerTrap)
                UpdateCornerTrapMetric(index);

            if (_scenario == AgentBattleConfig.ScenarioOpenControl
                || _actions[index] == AgentBattleConfig.ActionRetreat
                || _routeCrossed[index]
                || !HasPassedScenarioBarrier(index))
            {
                continue;
            }

            int route = ClassifyPhysicalPassage(_positions[index].X);
            _routeCrossed[index] = true;
            _physicalRoutes[index] = route;
            _routeCrossingPositions[index] = _positions[index];
            _routeCrossings[route]++;
        }
    }

    private void UpdateCornerTrapMetric(int index)
    {
        Vector2 position = _positions[index];
        if (!_trapEntered[index] && IsCornerTrapRegion(position))
        {
            _trapEntered[index] = true;
            _trapEntryTicks[index] = _tickCount;
            if (_teams[index] == AgentBattleConfig.TeamBlue)
                _trapEntriesBlue++;
            else
                _trapEntriesRed++;
        }

        if (!_trapEntered[index] || _trapEscaped[index])
            return;

        float dwell = (_tickCount - _trapEntryTicks[index]) * AgentBattleConfig.FixedDelta;
        _maximumTrapDwellSeconds = MathF.Max(_maximumTrapDwellSeconds, dwell);
        if (!HasPassedScenarioBarrier(index))
            return;

        _trapEscaped[index] = true;
        if (dwell <= AgentBattleConfig.TimelyTrapEscapeSeconds)
            _trapEscapesWithin12Seconds++;
    }

    private static bool IsCornerTrapRegion(Vector2 position) =>
        position.X >= AgentBattleConfig.TrapMinX
        && position.X <= AgentBattleConfig.TrapMaxX
        && position.Y >= AgentBattleConfig.TrapMinY
        && position.Y <= AgentBattleConfig.TrapMaxY;

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
                return NavigationRouteWaypoint(index, route, cursor, true);
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
