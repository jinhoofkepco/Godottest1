using Godot;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Collections.Generic;

public partial class BattleSimulation
{
    private void UpdateShieldMode(int unitIndex)
    {
        if (_kinds[unitIndex] != UnitMelee)
        {
            _shieldModes[unitIndex] = 0;
            return;
        }
        Vector2 position = _positions[unitIndex];
        float radius = _shieldModes[unitIndex] != 0 ? _settings.ShieldReleaseRange : _settings.ShieldEnterRange;
        float radiusSq = radius * radius;
        List<int>[] hostileBuckets = _teams[unitIndex] == TeamEnemy ? _allyBuckets : _enemyBuckets;
        Vector2I center = CellAt(position);
        int bucketRadius = Mathf.CeilToInt(radius);
        for (int row = Math.Max(0, center.Y - bucketRadius); row <= Math.Min(BattleConfig.GridRows - 1, center.Y + bucketRadius); row++)
            for (int col = Math.Max(0, center.X - bucketRadius); col <= Math.Min(BattleConfig.GridColumns - 1, center.X + bucketRadius); col++)
                foreach (int candidate in hostileBuckets[Index(new Vector2I(col, row))])
                {
                    if (_hp[candidate] <= 0f || _kinds[candidate] != UnitRanged
                        || position.DistanceSquaredTo(_positions[candidate]) > radiusSq) continue;
                    _shieldModes[unitIndex] = 1;
                    return;
                }
        _shieldModes[unitIndex] = 0;
    }

    private void FindTarget(int unitIndex)
    {
        Vector2 position = _positions[unitIndex];
        int team = _teams[unitIndex];
        bool focusFire = _kinds[unitIndex] == UnitRanged;
        bool canTargetAir = _kinds[unitIndex] != UnitMelee;
        float detectRange = UnitDetectRange(_kinds[unitIndex]);
        SeedRetainedTarget(_targetIds[unitIndex], team, position, canTargetAir, detectRange, out float bestDistanceSq);
        float bestHealthRatio = focusFire && _foundUnitIndex >= 0
            ? _hp[_foundUnitIndex] / UnitMaxHp(_kinds[_foundUnitIndex])
            : float.PositiveInfinity;
        int bestFocusId = focusFire && _foundUnitIndex >= 0 ? _ids[_foundUnitIndex] : int.MaxValue;
        List<int>[] buckets = team == TeamEnemy ? _allyBuckets : _enemyBuckets;
        Vector2I cell = CellAt(position);
        int radius = Mathf.CeilToInt(detectRange);
        for (int row = Math.Max(0, cell.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + radius); row++)
            for (int col = Math.Max(0, cell.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + radius); col++)
            {
                if (!focusFire && !BucketCanContainNearer(position, col, row, bestDistanceSq)) continue;
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    _targetCandidateChecks++;
                    if (_hp[candidate] <= 0f || (!canTargetAir && _kinds[candidate] == UnitDragon)) continue;
                    float distanceSq = position.DistanceSquaredTo(_positions[candidate]);
                    if (distanceSq > detectRange * detectRange) continue;
                    if (focusFire)
                    {
                        float healthRatio = _hp[candidate] / UnitMaxHp(_kinds[candidate]);
                        if (healthRatio > bestHealthRatio + 0.0001f
                            || (Mathf.IsEqualApprox(healthRatio, bestHealthRatio) && _ids[candidate] >= bestFocusId)) continue;
                        bestHealthRatio = healthRatio;
                        bestFocusId = _ids[candidate];
                    }
                    else if (distanceSq > bestDistanceSq) continue;
                    bestDistanceSq = distanceSq;
                    _foundTargetId = _ids[candidate];
                    _foundUnitIndex = candidate;
                    _foundBuildingIndex = -1;
                    _foundTargetPosition = _positions[candidate];
                }
            }
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            if (building.Destroyed || building.Team == team) continue;
            Vector2 at = new(building.Cell.X + 0.5f, building.Cell.Y + 0.5f);
            float distanceSq = position.DistanceSquaredTo(at);
            if (focusFire && _foundUnitIndex >= 0 || distanceSq > bestDistanceSq) continue;
            bestDistanceSq = distanceSq;
            _foundTargetId = -building.Id;
            _foundUnitIndex = -1;
            _foundBuildingIndex = i;
            _foundTargetPosition = at;
        }
        if (_foundTargetId == 0) AssignHqFallback(team, position);
    }

    private void SeedRetainedTarget(int targetId, int team, Vector2 position, bool canTargetAir, float detectRange, out float bestDistanceSq)
    {
        bestDistanceSq = detectRange * detectRange;
        _foundTargetId = 0;
        _foundUnitIndex = -1;
        _foundBuildingIndex = -1;
        _foundTargetPosition = Vector2.Zero;
        if (targetId > 0 && targetId < _indexById.Length)
        {
            int index = _indexById[targetId];
            if (index >= 0 && index < _unitCount)
            {
                float distanceSq = position.DistanceSquaredTo(_positions[index]);
                if (_hp[index] > 0f && _teams[index] != team && (canTargetAir || _kinds[index] != UnitDragon) && distanceSq <= bestDistanceSq)
                {
                    bestDistanceSq = distanceSq;
                    _foundTargetId = targetId;
                    _foundUnitIndex = index;
                    _foundTargetPosition = _positions[index];
                }
            }
        }
        else if (targetId < 0 && targetId != SiegeTargetSentinel)
        {
            int buildingIndex = BuildingIndexFromId(-targetId);
            if (buildingIndex >= 0)
            {
                Building building = _buildings[buildingIndex];
                Vector2 at = new(building.Cell.X + 0.5f, building.Cell.Y + 0.5f);
                float distanceSq = position.DistanceSquaredTo(at);
                if (!building.Destroyed && building.Team != team && distanceSq <= bestDistanceSq)
                {
                    bestDistanceSq = distanceSq;
                    _foundTargetId = targetId;
                    _foundBuildingIndex = buildingIndex;
                    _foundTargetPosition = at;
                }
            }
        }
    }

    private void FindSiegeTarget(int unitIndex)
    {
        _foundUnitIndex = -1;
        _foundBuildingIndex = -1;
        _foundTargetPosition = SiegeTargetPoint(unitIndex);
        _foundTargetId = _foundTargetPosition.X >= 0f ? SiegeTargetSentinel : 0;
    }

    private Vector2 SiegeTargetPoint(int unitIndex)
    {
        if (unitIndex < 0 || unitIndex >= _unitCount || _kinds[unitIndex] != UnitSiege || _hp[unitIndex] <= 0f)
            return new Vector2(-1f, -1f);
        Vector2 origin = _positions[unitIndex];
        int[] density = _teams[unitIndex] == TeamEnemy ? _allySiegeDensity : _enemySiegeDensity;
        List<int>[] hostileBuckets = _teams[unitIndex] == TeamEnemy ? _allyBuckets : _enemyBuckets;
        int[] occupiedCells = _teams[unitIndex] == TeamEnemy ? _allyOccupiedBucketCells : _enemyOccupiedBucketCells;
        int occupiedCount = _teams[unitIndex] == TeamEnemy ? _allyOccupiedBucketCount : _enemyOccupiedBucketCount;
        Vector2I originCell = CellAt(origin);
        float siegeRange = UnitAttackRange(UnitSiege, origin);
        float detectRange = Math.Max(siegeRange, UnitDetectRange(UnitSiege));
        float minimumSq = _settings.SiegeMinRange * _settings.SiegeMinRange;
        float rangeSq = siegeRange * siegeRange;
        float detectRangeSq = detectRange * detectRange;
        float predictionHorizon = MaximumUnitSpeed() * (1f + BattleConfig.UnitSpeedVariation) * _settings.SiegeFlightSeconds;
        float queryRange = detectRange + predictionHorizon;
        float queryRangeSq = queryRange * queryRange;
        int radius = Mathf.CeilToInt(queryRange);
        int minimumRow = Math.Max(0, originCell.Y - radius);
        int maximumRow = Math.Min(BattleConfig.GridRows - 1, originCell.Y + radius);
        int occupiedIndex = LowerBound(occupiedCells, occupiedCount, minimumRow * BattleConfig.GridColumns);
        int occupiedEnd = (maximumRow + 1) * BattleConfig.GridColumns;
        int bestScore = -1;
        float bestDistanceSq = float.PositiveInfinity;
        int bestPointIndex = int.MaxValue;
        Vector2 bestPoint = new(-1f, -1f);
        float approachDistanceSq = float.PositiveInfinity;
        Vector2 approachPoint = new(-1f, -1f);
        int candidateGeneration = 0;
        for (; occupiedIndex < occupiedCount && occupiedCells[occupiedIndex] < occupiedEnd; occupiedIndex++)
        {
            int bucketIndex = occupiedCells[occupiedIndex];
            int col = bucketIndex % BattleConfig.GridColumns;
            if (Math.Abs(col - originCell.X) > radius) continue;
            foreach (int candidate in hostileBuckets[bucketIndex])
            {
                if (_hp[candidate] <= 0f) continue;
                float currentDistanceSq = origin.DistanceSquaredTo(_positions[candidate]);
                if (currentDistanceSq < minimumSq || currentDistanceSq > queryRangeSq) continue;
                Vector2 fallback = _teams[candidate] == TeamEnemy ? Vector2.Down : Vector2.Up;
                Vector2 predicted = PredictedSiegePosition(candidate, fallback, _settings.SiegeFlightSeconds);
                float predictedDistanceSq = origin.DistanceSquaredTo(predicted);
                if (predictedDistanceSq < minimumSq || predictedDistanceSq > detectRangeSq) continue;
                if (predictedDistanceSq <= rangeSq)
                {
                    if (candidateGeneration == 0) candidateGeneration = NextSiegeCandidateGeneration();
                    ScoreSiegeAimCells(origin, predicted, UnitRadius(_kinds[candidate]), density, minimumSq, rangeSq,
                        candidateGeneration, ref bestScore, ref bestDistanceSq, ref bestPointIndex, ref bestPoint);
                }
                else if (predictedDistanceSq < approachDistanceSq)
                {
                    approachDistanceSq = predictedDistanceSq;
                    approachPoint = predicted;
                }
            }
        }
        int team = _teams[unitIndex];
        for (int index = 0; index < _buildingCount; index++)
        {
            Building building = _buildings[index];
            if (building.Destroyed || building.Team == team) continue;
            Vector2 at = new(building.Cell.X + 0.5f, building.Cell.Y + 0.5f);
            float distanceSq = origin.DistanceSquaredTo(at);
            if (distanceSq < minimumSq || distanceSq > detectRangeSq) continue;
            if (distanceSq <= rangeSq)
            {
                if (candidateGeneration == 0) candidateGeneration = NextSiegeCandidateGeneration();
                ScoreSiegeAimCells(origin, at, BattleConfig.BuildingTargetRadius, density, minimumSq, rangeSq,
                    candidateGeneration, ref bestScore, ref bestDistanceSq, ref bestPointIndex, ref bestPoint);
            }
            else if (distanceSq < approachDistanceSq)
            {
                approachDistanceSq = distanceSq;
                approachPoint = at;
            }
        }
        return bestScore > 0 ? bestPoint : approachPoint;
    }

    private int NextSiegeCandidateGeneration()
    {
        if (_siegeCandidateGeneration == int.MaxValue)
        {
            Array.Clear(_siegeCandidateStamps);
            _siegeCandidateGeneration = 1;
        }
        else
        {
            _siegeCandidateGeneration++;
        }
        return _siegeCandidateGeneration;
    }

    private void ScoreSiegeAimCells(Vector2 origin, Vector2 target, float targetRadius, int[] density,
        float minimumSq, float rangeSq, int generation, ref int bestScore, ref float bestDistanceSq,
        ref int bestPointIndex, ref Vector2 bestPoint)
    {
        float influence = _settings.SiegeBlastRadius + targetRadius;
        float influenceSq = influence * influence;
        int radius = Mathf.CeilToInt(influence);
        Vector2I center = CellAt(target);
        for (int row = Math.Max(0, center.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, center.Y + radius); row++)
            for (int col = Math.Max(0, center.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, center.X + radius); col++)
            {
                Vector2 point = new(col + 0.5f, row + 0.5f);
                if (point.DistanceSquaredTo(target) > influenceSq) continue;
                float distanceSq = origin.DistanceSquaredTo(point);
                if (distanceSq < minimumSq || distanceSq > rangeSq) continue;
                int pointIndex = Index(new Vector2I(col, row));
                if (_siegeCandidateStamps[pointIndex] == generation) continue;
                _siegeCandidateStamps[pointIndex] = generation;
                int score = density[pointIndex];
                if (score <= 0) continue;
                bool improves = score > bestScore || score == bestScore
                    && (distanceSq < bestDistanceSq - 0.000001f || Mathf.IsEqualApprox(distanceSq, bestDistanceSq) && pointIndex < bestPointIndex);
                if (!improves) continue;
                bestScore = score;
                bestDistanceSq = distanceSq;
                bestPointIndex = pointIndex;
                bestPoint = point;
            }
    }

    private static int LowerBound(int[] values, int count, int target)
    {
        int low = 0;
        int high = count;
        while (low < high)
        {
            int middle = low + (high - low) / 2;
            if (values[middle] < target) low = middle + 1;
            else high = middle;
        }
        return low;
    }

    private void CacheFoundTarget(int index)
    {
        _targetIds[index] = _foundTargetId;
        _cachedTargetPositions[index] = _foundTargetId != 0 ? _foundTargetPosition : new Vector2(-1f, -1f);
        _cachedTargetRadii[index] = _foundTargetId != 0 ? FoundTargetRadius() : 0f;
        if (_kinds[index] == UnitSiege) _siegeTargetPositions[index] = _cachedTargetPositions[index];
    }

    private void RestoreCachedTarget(int index)
    {
        _foundTargetId = 0;
        _foundUnitIndex = -1;
        _foundBuildingIndex = -1;
        _foundTargetPosition = Vector2.Zero;
        int targetId = _targetIds[index];
        if (_kinds[index] == UnitSiege)
        {
            Vector2 point = _cachedTargetPositions[index];
            if (targetId != 0 && point.X >= 0f)
            {
                _foundTargetId = targetId;
                _foundTargetPosition = point;
                return;
            }
            ClearCachedTarget(index);
            return;
        }
        Vector2 position = _positions[index];
        int team = _teams[index];
        float detect = UnitDetectRange(_kinds[index]);
        float maxDistanceSq = detect * detect;
        if (targetId > 0 && targetId < _indexById.Length)
        {
            int targetIndex = _indexById[targetId];
            bool canTargetAir = _kinds[index] != UnitMelee;
            if (targetIndex >= 0 && targetIndex < _unitCount && _hp[targetIndex] > 0f && _teams[targetIndex] != team
                && (canTargetAir || _kinds[targetIndex] != UnitDragon) && position.DistanceSquaredTo(_positions[targetIndex]) <= maxDistanceSq)
            {
                _foundTargetId = targetId;
                _foundUnitIndex = targetIndex;
                _foundTargetPosition = _positions[targetIndex];
                _cachedTargetPositions[index] = _foundTargetPosition;
                _cachedTargetRadii[index] = UnitRadius(_kinds[targetIndex]);
                return;
            }
        }
        else if (targetId < 0)
        {
            int buildingIndex = BuildingIndexFromId(-targetId);
            if (buildingIndex >= 0)
            {
                Building building = _buildings[buildingIndex];
                Vector2 at = new(building.Cell.X + 0.5f, building.Cell.Y + 0.5f);
                if (!building.Destroyed && building.Team != team && position.DistanceSquaredTo(at) <= maxDistanceSq)
                {
                    _foundTargetId = targetId;
                    _foundBuildingIndex = buildingIndex;
                    _foundTargetPosition = at;
                    _cachedTargetPositions[index] = at;
                    _cachedTargetRadii[index] = BattleConfig.BuildingTargetRadius;
                    return;
                }
            }
        }
        ClearCachedTarget(index);
    }

    private void ClearCachedTarget(int index)
    {
        _targetIds[index] = 0;
        _cachedTargetPositions[index] = new Vector2(-1f, -1f);
        _cachedTargetRadii[index] = 0f;
        if (_kinds[index] == UnitSiege) _siegeTargetPositions[index] = new Vector2(-1f, -1f);
    }

    private float FoundTargetRadius() => _foundUnitIndex >= 0 && _foundUnitIndex < _unitCount ? UnitRadius(_kinds[_foundUnitIndex]) : _foundBuildingIndex >= 0 ? BattleConfig.BuildingTargetRadius : 0f;

    private int NearestHostileUnitIndex(int team, Vector2 position, float radius, bool canTargetAir)
    {
        List<int>[] buckets = team == TeamEnemy ? _allyBuckets : _enemyBuckets;
        Vector2I cell = CellAt(position);
        int bucketRadius = Mathf.CeilToInt(radius + MaximumUnitRadius());
        float bestSurface = float.PositiveInfinity;
        int best = -1;
        for (int row = Math.Max(0, cell.Y - bucketRadius); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + bucketRadius); row++)
            for (int col = Math.Max(0, cell.X - bucketRadius); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + bucketRadius); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    if (_hp[candidate] <= 0f || (!canTargetAir && _kinds[candidate] == UnitDragon)) continue;
                    float surface = Mathf.Max(0f, position.DistanceTo(_positions[candidate]) - UnitRadius(_kinds[candidate]));
                    if (surface <= radius && surface <= bestSurface) { bestSurface = surface; best = candidate; }
                }
        return best;
    }

    private Vector2 CalculateSeparation(int index)
    {
        Vector2 position = _positions[index];
        List<int>[] buckets = _teams[index] == TeamEnemy ? _enemyBuckets : _allyBuckets;
        Vector2I cell = CellAt(position);
        Vector2 separation = Vector2.Zero;
        float queryDistance = (UnitRadius(_kinds[index]) + MaximumUnitRadius()) * BattleConfig.UnitSeparationSpacingMultiplier;
        int maximumHorizon = Mathf.CeilToInt(BattleConfig.MaxTunableUnitRadius * 2f * BattleConfig.UnitSeparationSpacingMultiplier);
        int bucketRadius = Math.Min(maximumHorizon, Mathf.CeilToInt(queryDistance));
        for (int row = Math.Max(0, cell.Y - bucketRadius); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + bucketRadius); row++)
            for (int col = Math.Max(0, cell.X - bucketRadius); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + bucketRadius); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    if (candidate == index || _hp[candidate] <= 0f) continue;
                    float desired = SeparationDistance(_kinds[index], _kinds[candidate]);
                    Vector2 offset = position - _positions[candidate];
                    float distanceSq = offset.LengthSquared();
                    if (distanceSq >= desired * desired) continue;
                    if (distanceSq <= 0.000001f) separation += new Vector2(_ids[index] < _ids[candidate] ? 1f : -1f, 0f);
                    else
                    {
                        float distance = Mathf.Sqrt(distanceSq);
                        separation += offset / distance * (1f - distance / desired);
                    }
                }
        return separation.LengthSquared() > 0.000001f ? separation.Normalized() : Vector2.Zero;
    }

    private Vector2 CalculateObstacleRepulsion(Vector2 position)
    {
        Vector2I cell = CellAt(position);
        int radius = Mathf.CeilToInt(BattleConfig.GroundBlockRepulsionRadius);
        Vector2 result = Vector2.Zero;
        for (int row = Math.Max(0, cell.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + radius); row++)
            for (int col = Math.Max(0, cell.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + radius); col++)
            {
                Vector2I obstacle = new(col, row);
                if (!CellBlocksGround(obstacle)) continue;
                Vector2 offset = position - new Vector2(col + 0.5f, row + 0.5f);
                float distance = offset.Length();
                if (distance >= BattleConfig.GroundBlockRepulsionRadius) continue;
                result += distance <= 0.000001f ? Vector2.Right : offset / distance * (1f - distance / BattleConfig.GroundBlockRepulsionRadius);
            }
        return result.LengthSquared() > 0.000001f ? result.Normalized() : Vector2.Zero;
    }

    private bool ShouldWait(int index, Vector2 forward)
    {
        if (forward.LengthSquared() <= 0.000001f) return false;
        Vector2 position = _positions[index];
        forward = forward.Normalized();
        Vector2 probe = position + forward * BattleConfig.WaitCheckRadius;
        List<int>[] buckets = _teams[index] == TeamEnemy ? _enemyBuckets : _allyBuckets;
        Vector2I cell = CellAt(probe);
        for (int row = Math.Max(0, cell.Y - 1); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + 1); row++)
            for (int col = Math.Max(0, cell.X - 1); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + 1); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    if (candidate == index || _hp[candidate] <= 0f || _kinds[candidate] == UnitDragon) continue;
                    Vector2 offset = _positions[candidate] - position;
                    if (offset.Dot(forward) <= 0f || probe.DistanceTo(_positions[candidate]) > BattleConfig.WaitCheckRadius) continue;
                    if (_velocities[candidate].Length() <= BattleConfig.WaitSlowSpeed) return true;
                }
        return false;
    }

    private Vector2 AdvanceDirection(int index)
    {
        int team = _teams[index];
        Vector2 direction;
        bool suppressFlowNoise = false;
        if (_kinds[index] == UnitDragon)
        {
            int hqId = team == TeamAlly ? _enemyHqId : _allyHqId;
            Vector2I hq = BuildingCell(hqId);
            direction = _positions[index].DirectionTo(new Vector2(hq.X + 0.5f, hq.Y + 0.5f));
        }
        else
        {
            FlowField flow = SelectFlow(index);
            Vector2I cell = CellAt(_positions[index]);
            bool nearObstacle = flow.NearObstacleAt(cell);
            direction = nearObstacle ? flow.PortalDirectionAt(_positions[index]) : flow.DirectionAt(cell);
            if (direction == Vector2.Zero) direction = flow.DirectionAt(cell);
            if (direction == Vector2.Zero) direction = team == TeamAlly ? Vector2.Up : Vector2.Down;
            suppressFlowNoise = _recoveryActive[index] != 0 || nearObstacle;
        }
        return suppressFlowNoise ? direction : direction.Rotated(_flowBiasRadians[index]);
    }

    private Vector2 MoveGround(Vector2 position, Vector2 motion, float radius)
    {
        Vector2I from = CellAt(position);
        Span<Vector2> candidates = stackalloc Vector2[3] { motion, new Vector2(motion.X, 0f), new Vector2(0f, motion.Y) };
        foreach (Vector2 candidateMotion in candidates)
        {
            Vector2 candidate = position + candidateMotion;
            float safeRadius = Mathf.Clamp(radius, 0.001f, Math.Min(BattleConfig.GridColumns, BattleConfig.GridRows) * 0.5f);
            candidate.X = Mathf.Clamp(candidate.X, safeRadius, BattleConfig.GridColumns - safeRadius);
            candidate.Y = Mathf.Clamp(candidate.Y, safeRadius, BattleConfig.GridRows - safeRadius);
            Vector2I cell = CellAt(candidate);
            if (cell == from && radius <= 0.5f && _groundBlocked[Index(cell)] == 0)
            {
                float localX = candidate.X - cell.X;
                float localY = candidate.Y - cell.Y;
                if (localX >= radius && localX <= 1f - radius && localY >= radius && localY <= 1f - radius)
                    return candidate;
            }
            bool transitionClear = cell == from || GroundNavigation.CanTransition(from, cell, _groundBlocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows);
            if (transitionClear && GroundNavigation.CanOccupyPosition(candidate, radius, _groundBlocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows))
                return candidate;
        }
        return position;
    }

    private FlowField SelectFlow(int index) => SelectFlow(_teams[index], _kinds[index]);

    private FlowField SelectFlow(int team, int kind)
    {
        bool heavy = kind == UnitSiege;
        if (team == TeamAlly) return heavy && !_allyHeavySharesInfantry ? _allyHeavyFlow : _allyFlow;
        return heavy && !_enemyHeavySharesInfantry ? _enemyHeavyFlow : _enemyFlow;
    }

    private byte[] SelectFlowBlocked(int index) => SelectFlowBlocked(_teams[index], _kinds[index]);

    private byte[] SelectFlowBlocked(int team, int kind)
    {
        bool heavy = kind == UnitSiege;
        if (team == TeamAlly) return heavy && !_allyHeavySharesInfantry ? _allyHeavyBlocked : _allyInfantryBlocked;
        return heavy && !_enemyHeavySharesInfantry ? _enemyHeavyBlocked : _enemyInfantryBlocked;
    }

    private float InfantryClearanceRadius() => Math.Max(UnitRadius(UnitMelee), UnitRadius(UnitRanged));

    private float HeavyClearanceRadius() => Math.Max(InfantryClearanceRadius(), UnitRadius(UnitSiege));

    private Vector2 RecoveryDirection(int index)
    {
        Vector2 position = _positions[index];
        Vector2 target = _recoveryTargets[index];
        if (_recoveryActive[index] != 0 && position.DistanceSquaredTo(target) > BattleConfig.RecoveryArrivalRadius * BattleConfig.RecoveryArrivalRadius)
            return position.DirectionTo(target);
        if (_recoveryActive[index] != 0)
        {
            _recoveryActive[index] = 0;
            return Vector2.Zero;
        }

        FlowField flow = SelectFlow(index);
        byte[] blocked = SelectFlowBlocked(index);
        Vector2I start = CellAt(position);
        float startCost = flow.CostAt(start);
        Vector2I best = new(-1, -1);
        float bestCost = startCost;
        int parity = _ids[index] & 1;
        for (int y = -1; y <= 1; y++)
            for (int x = -1; x <= 1; x++)
            {
                if (x == 0 && y == 0) continue;
                Vector2I candidate = start + new Vector2I(x, y);
                if (!GroundNavigation.CanTransition(start, candidate, blocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows)) continue;
                float cost = flow.CostAt(candidate);
                if (cost >= startCost - 0.0001f) continue;
                int candidateTie = candidate.Y * BattleConfig.GridColumns + candidate.X;
                int bestTie = best.Y * BattleConfig.GridColumns + best.X;
                if (cost < bestCost - 0.0001f || Mathf.IsEqualApprox(cost, bestCost) && ((candidateTie + parity) & 1) < ((bestTie + parity) & 1))
                {
                    best = candidate;
                    bestCost = cost;
                }
            }
        if (best.X < 0) best = BoundedRecoveryCell(start, flow, blocked, parity);
        if (best.X < 0) return Vector2.Zero;
        _recoveryTargets[index] = new Vector2(best.X + 0.5f, best.Y + 0.5f);
        _recoveryActive[index] = 1;
        _navigationRecoveryCount++;
        return position.DirectionTo(_recoveryTargets[index]);
    }

    private Vector2I BoundedRecoveryCell(Vector2I start, FlowField flow, byte[] blocked, int parity)
    {
        const int diameter = BattleConfig.RecoveryWindowRadius * 2 + 1;
        Span<int> queue = stackalloc int[diameter * diameter];
        Span<byte> visited = stackalloc byte[diameter * diameter];
        int minCol = Math.Max(0, start.X - BattleConfig.RecoveryWindowRadius);
        int minRow = Math.Max(0, start.Y - BattleConfig.RecoveryWindowRadius);
        int maxCol = Math.Min(BattleConfig.GridColumns - 1, start.X + BattleConfig.RecoveryWindowRadius);
        int maxRow = Math.Min(BattleConfig.GridRows - 1, start.Y + BattleConfig.RecoveryWindowRadius);
        int localWidth = maxCol - minCol + 1;
        int head = 0;
        int tail = 0;
        int startLocal = (start.Y - minRow) * localWidth + start.X - minCol;
        queue[tail++] = Index(start);
        visited[startLocal] = 1;
        Vector2I best = new(-1, -1);
        float startCost = flow.CostAt(start);
        float bestCost = startCost;
        while (head < tail)
        {
            int cellIndex = queue[head++];
            Vector2I cell = new(cellIndex % BattleConfig.GridColumns, cellIndex / BattleConfig.GridColumns);
            float cost = flow.CostAt(cell);
            int candidateTie = cellIndex;
            int bestTie = best.Y * BattleConfig.GridColumns + best.X;
            if (cost < bestCost - 0.0001f || cost < startCost - 0.0001f && Mathf.IsEqualApprox(cost, bestCost) && ((candidateTie + parity) & 1) < ((bestTie + parity) & 1))
            {
                best = cell;
                bestCost = cost;
            }
            for (int y = -1; y <= 1; y++)
                for (int x = -1; x <= 1; x++)
                {
                    if (x == 0 && y == 0) continue;
                    Vector2I next = cell + new Vector2I(x, y);
                    if (next.X < minCol || next.X > maxCol || next.Y < minRow || next.Y > maxRow) continue;
                    int local = (next.Y - minRow) * localWidth + next.X - minCol;
                    if (visited[local] != 0 || !GroundNavigation.CanTransition(cell, next, blocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows)) continue;
                    visited[local] = 1;
                    queue[tail++] = Index(next);
                }
        }
        return best;
    }

    private void UpdateNavigationProgress(int index, Vector2 movedPosition, float desiredSpeedSq, float elapsed)
    {
        if (_kinds[index] == UnitDragon || desiredSpeedSq <= 0.0001f)
        {
            _stuckTimers[index] = 0f;
            _progressOrigins[index] = movedPosition;
            return;
        }
        Vector2 origin = _progressOrigins[index];
        float dx = movedPosition.X - origin.X;
        float dy = movedPosition.Y - origin.Y;
        if (dx * dx + dy * dy >= BattleConfig.NavigationProgressEpsilon * BattleConfig.NavigationProgressEpsilon)
        {
            _stuckTimers[index] = 0f;
            _progressOrigins[index] = movedPosition;
            if (_recoveryActive[index] != 0 && movedPosition.DistanceSquaredTo(_recoveryTargets[index]) <= BattleConfig.RecoveryArrivalRadius * BattleConfig.RecoveryArrivalRadius)
                _recoveryActive[index] = 0;
            return;
        }
        _stuckTimers[index] += elapsed;
        if (_stuckTimers[index] < BattleConfig.StuckTriggerSeconds) return;
        _stuckTimers[index] = 0f;
        _cachedWaiting[index] = 0;
        RecoveryDirection(index);
    }

    private void ClearNavigationProgress(int index, Vector2 position)
    {
        _stuckTimers[index] = 0f;
        _progressOrigins[index] = position;
        _recoveryActive[index] = 0;
        _recoveryTargets[index] = position;
    }

    private static Vector2 MoveFlying(Vector2 position, Vector2 motion)
    {
        Vector2 candidate = position + motion;
        candidate.X = Mathf.Clamp(candidate.X, 0.2f, BattleConfig.GridColumns - 0.2f);
        candidate.Y = Mathf.Clamp(candidate.Y, 0.5f, BattleConfig.GridRows - 0.5f);
        return candidate;
    }

    private void AttackTarget(int attacker, int targetUnit, int buildingIndex)
    {
        int kind = _kinds[attacker];
        _cooldowns[attacker] = UnitAttackInterval(kind);
        _lungeTimers[attacker] = BattleConfig.UnitLungeDuration;
        int team = _teams[attacker];
        Vector2 origin = _positions[attacker];
        if (targetUnit >= 0 && targetUnit < _unitCount)
        {
            if (kind == UnitRanged) QueueShot(ShotRanged, team, origin, _positions[targetUnit], _ids[attacker]);
            if (kind == UnitRanged && _kinds[targetUnit] == UnitMelee)
                _shieldModes[targetUnit] = 1;
            float classMultiplier = EffectiveClassDamageMultiplier(kind, _kinds[targetUnit], _shieldModes[targetUnit] != 0);
            float multiplier = ElevationDamageMultiplier(origin, _positions[targetUnit]) * classMultiplier;
            _hp[targetUnit] -= UnitAttackDamage(kind) * multiplier;
            _lastAttackerTeams[targetUnit] = team;
            QueueHit(targetUnit, ElevationDamageMultiplier(origin, _positions[targetUnit]) > 1f, classMultiplier > 1f);
        }
        else if (buildingIndex >= 0 && buildingIndex < _buildingCount)
        {
            Vector2I cell = _buildings[buildingIndex].Cell;
            Vector2 at = new(cell.X + 0.5f, cell.Y + 0.5f);
            if (kind == UnitRanged) QueueShot(ShotRanged, team, origin, at, _ids[attacker]);
            ApplyBuildingDamage(_buildings[buildingIndex].Id, UnitAttackDamage(kind) * ElevationDamageMultiplier(origin, at), team);
        }
    }

    private void LaunchSiege(int attacker, Vector2 target)
    {
        _cooldowns[attacker] = UnitAttackInterval(UnitSiege);
        _lungeTimers[attacker] = BattleConfig.UnitLungeDuration;
        float duration = SiegeFlightSeconds(_positions[attacker].DistanceTo(target));
        ScheduleSiegeImpact(_teams[attacker], _positions[attacker], target, UnitAttackDamage(UnitSiege), duration);
    }

    private void ScheduleSiegeImpact(int team, Vector2 origin, Vector2 target, float damage, float duration)
    {
        if (_impactCount >= MaxImpacts) return;
        float flight = Mathf.Max(0.001f, duration);
        _impacts[_impactCount++] = new SiegeImpact { Team = team, Origin = origin, Target = target, Damage = damage, Remaining = flight, Duration = flight };
        var e = new GDictionary { ["type"] = "siege_projectile", ["team"] = team, ["origin"] = origin, ["position"] = target, ["duration"] = flight };
        _events.Add(e);
    }

    private void AdvanceSiegeImpacts(float delta)
    {
        int index = _impactCount - 1;
        while (index >= 0)
        {
            _impacts[index].Remaining -= delta;
            if (_impacts[index].Remaining <= 0f)
            {
                ResolveSiegeImpact(_impacts[index]);
                _impacts[index] = _impacts[--_impactCount];
            }
            index--;
        }
    }

    private void ResolveSiegeImpact(SiegeImpact impact)
    {
        _siegeImpactsResolved++;
        List<int>[] buckets = impact.Team == TeamEnemy ? _allyBuckets : _enemyBuckets;
        Vector2I cell = CellAt(impact.Target);
        int radius = Mathf.CeilToInt(_settings.SiegeBlastRadius + MaximumUnitRadius());
        for (int row = Math.Max(0, cell.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + radius); row++)
            for (int col = Math.Max(0, cell.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + radius); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    _aoeCandidateChecks++;
                    if (_hp[candidate] <= 0f) continue;
                    float damage = SiegeDamageAtDistance(impact.Target.DistanceTo(_positions[candidate]), UnitRadius(_kinds[candidate]), impact.Damage);
                    if (damage <= 0f) continue;
                    float classMultiplier = GetClassDamageMultiplier(UnitSiege, _kinds[candidate]);
                    float multiplier = ElevationDamageMultiplier(impact.Origin, _positions[candidate]) * classMultiplier;
                    _hp[candidate] -= damage * multiplier;
                    _lastAttackerTeams[candidate] = impact.Team;
                    QueueHit(candidate, ElevationDamageMultiplier(impact.Origin, _positions[candidate]) > 1f, classMultiplier > 1f);
                }
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            if (building.Destroyed || building.Team == impact.Team) continue;
            Vector2 at = new(building.Cell.X + 0.5f, building.Cell.Y + 0.5f);
            float damage = SiegeDamageAtDistance(impact.Target.DistanceTo(at), BattleConfig.BuildingTargetRadius, impact.Damage);
            if (damage > 0f) ApplyBuildingDamage(building.Id, damage * ElevationDamageMultiplier(impact.Origin, at), impact.Team);
        }
        _events.Add(new GDictionary { ["type"] = "siege_impact", ["team"] = impact.Team, ["position"] = impact.Target, ["radius"] = _settings.SiegeBlastRadius });
    }

    private void ApplyBuildingDamage(int id, float damage, int attackerTeam)
    {
        int index = BuildingIndexFromId(id);
        if (index < 0 || _buildings[index].Destroyed) return;
        ref Building building = ref _buildings[index];
        building.Hp = Mathf.Max(0f, building.Hp - damage);
        _boardVersion++;
        string type = building.Kind == BuildingHq ? "hq_hit" : building.Kind == BuildingRallyPoint ? "rally_hit" : "building_hit";
        _events.Add(new GDictionary { ["type"] = type, ["team"] = building.Team, ["building_id"] = id, ["cell"] = building.Cell });
        if (building.Hp > 0f) return;
        building.Destroyed = true;
        if (building.Kind == BuildingRallyPoint) HandleRallyDestroyed(building.Id);
        QueueBlockedDelta(Index(building.Cell));
        _events.Add(new GDictionary { ["type"] = "building_destroyed", ["team"] = building.Team, ["building_id"] = id, ["cell"] = building.Cell, ["kind"] = building.Kind });
        RebuildFlowFields();
        if (building.Kind == BuildingHq) _result = attackerTeam == TeamAlly ? "VICTORY" : "DEFEAT";
        else RecalculateTerritory(true, true);
    }

    private void RemoveDeadUnits()
    {
        for (int index = _unitCount - 1; index >= 0; index--)
        {
            if (_hp[index] > 0f) continue;
            Vector2 direction = _velocities[index].LengthSquared() > 0.000001f ? _velocities[index] : _lungeDirections[index];
            QueueDeath(index, direction);
            AwardKill(_lastAttackerTeams[index]);
            if (_kinds[index] != UnitDragon && _ghostCount < MaxGhosts)
                _ghosts[_ghostCount++] = new DeathGhost { Position = _positions[index], Direction = direction, Team = _teams[index], Kind = _kinds[index], Remaining = BattleConfig.DeathDuration };
            RemoveUnitAt(index);
        }
    }

    private void RemoveUnitAt(int index)
    {
        int legionIndex = LegionIndexFromId(_legionIds[index]);
        if (legionIndex >= 0)
        {
            _legionLiveCounts[legionIndex] = Math.Max(0, _legionLiveCounts[legionIndex] - 1);
            EvaluateLegionBroken(legionIndex);
        }
        int deadId = _ids[index];
        _teamUnitCounts[_teams[index]] = Math.Max(0, _teamUnitCounts[_teams[index]] - 1);
        int last = --_unitCount;
        _indexById[deadId] = -1;
        if (index == last) return;
        _ids[index] = _ids[last]; _teams[index] = _teams[last]; _kinds[index] = _kinds[last]; _states[index] = _states[last];
        _targetIds[index] = _targetIds[last]; _lastAttackerTeams[index] = _lastAttackerTeams[last];
        _positions[index] = _positions[last]; _velocities[index] = _velocities[last]; _lungeDirections[index] = _lungeDirections[last];
        _cachedTargetPositions[index] = _cachedTargetPositions[last]; _cachedSteering[index] = _cachedSteering[last]; _siegeTargetPositions[index] = _siegeTargetPositions[last];
        _hp[index] = _hp[last]; _cooldowns[index] = _cooldowns[last]; _speedScales[index] = _speedScales[last]; _lungeTimers[index] = _lungeTimers[last];
        _flowBiasRadians[index] = _flowBiasRadians[last]; _cachedTargetRadii[index] = _cachedTargetRadii[last]; _hpBarTimers[index] = _hpBarTimers[last]; _cachedWaiting[index] = _cachedWaiting[last];
        _shieldModes[index] = _shieldModes[last]; _stuckTimers[index] = _stuckTimers[last]; _recoveryActive[index] = _recoveryActive[last];
        _progressOrigins[index] = _progressOrigins[last]; _recoveryTargets[index] = _recoveryTargets[last];
        _firingTargetIds[index] = _firingTargetIds[last]; _firingPositions[index] = _firingPositions[last];
        _firingSlotIndices[index] = _firingSlotIndices[last]; _firingLateral[index] = _firingLateral[last];
        _yieldCorrections[index] = _yieldCorrections[last]; _yieldTouched[index] = _yieldTouched[last];
        _legionIds[index] = _legionIds[last]; _rallyPointIds[index] = _rallyPointIds[last]; _slotOffsets[index] = _slotOffsets[last];
        _indexById[_ids[index]] = index;
    }

    private void CheckTerminalState()
    {
        if (_result.Length != 0) return;
        if (_allyOccupancy >= BattleConfig.OccupancyWinRatio) { _result = "VICTORY"; return; }
        if (_allyOccupancy <= 1f - BattleConfig.OccupancyWinRatio) { _result = "DEFEAT"; return; }
        if (_timeRemaining > 0f) return;
        if (!Mathf.IsEqualApprox(_allyOccupancy, _enemyOccupancy)) { _result = _allyOccupancy > _enemyOccupancy ? "VICTORY" : "DEFEAT"; return; }
        float allyHq = BuildingHpRatio(_allyHqId), enemyHq = BuildingHpRatio(_enemyHqId);
        if (!Mathf.IsEqualApprox(allyHq, enemyHq)) { _result = allyHq > enemyHq ? "VICTORY" : "DEFEAT"; return; }
        float allyHp = 0f, enemyHp = 0f;
        for (int i = 0; i < _unitCount; i++) if (_teams[i] == TeamAlly) allyHp += _hp[i]; else enemyHp += _hp[i];
        _result = allyHp > enemyHp ? "VICTORY" : "DEFEAT";
    }

    private void AssignHqFallback(int team, Vector2 position)
    {
        bool terminal = (team == TeamAlly && position.Y <= BattleConfig.HqFallbackBand) || (team == TeamEnemy && position.Y >= BattleConfig.GridRows - BattleConfig.HqFallbackBand);
        if (!terminal) return;
        int hqId = team == TeamAlly ? _enemyHqId : _allyHqId;
        int index = BuildingIndexFromId(hqId);
        if (index < 0 || _buildings[index].Destroyed) return;
        _foundTargetId = -hqId;
        _foundUnitIndex = -1;
        _foundBuildingIndex = index;
        Vector2I cell = _buildings[index].Cell;
        _foundTargetPosition = new Vector2(cell.X + 0.5f, cell.Y + 0.5f);
    }

    private Vector2 FindSpawnPosition(Vector2I cell, int team, int unitKind)
    {
        bool flying = unitKind == UnitDragon;
        int forward = team == TeamAlly ? -1 : 1;
        float radius = UnitRadius(unitKind);
        int maximumRing = flying ? 1 : Math.Max(1, Mathf.CeilToInt(radius + 0.5f) + 2);
        for (int ring = 1; ring <= maximumRing; ring++)
        {
            if (TrySpawnPosition(cell, cell + new Vector2I(0, forward * ring), unitKind, flying, radius, out Vector2 position))
                return position;
            for (int lateral = 1; lateral <= ring; lateral++)
            {
                if (TrySpawnPosition(cell, cell + new Vector2I(-lateral, forward * ring), unitKind, flying, radius, out position))
                    return position;
                if (TrySpawnPosition(cell, cell + new Vector2I(lateral, forward * ring), unitKind, flying, radius, out position))
                    return position;
            }
            for (int depth = ring - 1; depth >= -ring + 1; depth--)
            {
                if (TrySpawnPosition(cell, cell + new Vector2I(-ring, forward * depth), unitKind, flying, radius, out position))
                    return position;
                if (TrySpawnPosition(cell, cell + new Vector2I(ring, forward * depth), unitKind, flying, radius, out position))
                    return position;
            }
            if (TrySpawnPosition(cell, cell + new Vector2I(0, -forward * ring), unitKind, flying, radius, out position))
                return position;
            for (int lateral = 1; lateral <= ring; lateral++)
            {
                if (TrySpawnPosition(cell, cell + new Vector2I(-lateral, -forward * ring), unitKind, flying, radius, out position))
                    return position;
                if (TrySpawnPosition(cell, cell + new Vector2I(lateral, -forward * ring), unitKind, flying, radius, out position))
                    return position;
            }
        }
        return new Vector2(-1f, -1f);
    }

    private bool TrySpawnPosition(Vector2I source, Vector2I candidate, int unitKind, bool flying, float radius, out Vector2 position)
    {
        position = new Vector2(-1f, -1f);
        if (!Valid(candidate)) return false;
        Vector2 center = new(candidate.X + 0.5f, candidate.Y + 0.5f);
        if (!flying)
        {
            int dx = Math.Abs(candidate.X - source.X);
            int dy = Math.Abs(candidate.Y - source.Y);
            if (Math.Max(dx, dy) == 1 && !_terrain.CanStep(source, candidate))
                return false;
            if (!GroundNavigation.CanOccupyPosition(center, radius, _groundBlocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows))
                return false;
        }
        position = center;
        return true;
    }

    private bool BucketCanContainNearer(Vector2 position, int col, int row, float bestDistanceSq)
    {
        float slop = MaximumUnitSpeed() * (1f + BattleConfig.UnitSpeedVariation) / BattleConfig.SimTickRate;
        Vector2 minimum = new Vector2(col, row) - Vector2.One * slop;
        Vector2 maximum = new Vector2(col + 1, row + 1) + Vector2.One * slop;
        Vector2 closest = position.Clamp(minimum, maximum);
        return position.DistanceSquaredTo(closest) <= bestDistanceSq;
    }

    private Vector2 PredictedSiegePosition(int index, Vector2 fallback, float seconds)
    {
        Vector2 velocity = _velocities[index];
        if (velocity.LengthSquared() <= 0.0001f && _states[index] == StateAdvance)
            velocity = fallback * UnitSpeed(_kinds[index]) * _speedScales[index];
        return MoveFlying(_positions[index], velocity * seconds);
    }

    private float GroundSpeedMultiplier(Vector2 from, Vector2 toward) => ElevationAt(toward) > ElevationAt(from) ? BattleConfig.UphillSpeedMultiplier : 1f;
    private float ElevationDamageMultiplier(Vector2 attacker, Vector2 target) => ElevationAt(attacker) > ElevationAt(target) ? BattleConfig.HighGroundDamageMultiplier : ElevationAt(attacker) < ElevationAt(target) ? BattleConfig.LowGroundDamageMultiplier : 1f;
    public float GetClassDamageMultiplier(int attackerKind, int targetKind) =>
        attackerKind >= UnitMelee && attackerKind <= UnitSiege && targetKind >= UnitMelee && targetKind <= UnitSiege
            ? _settings.Units[attackerKind].DamageVs[targetKind]
            : 1f;
    public float GetEffectiveClassDamageMultiplier(int attackerKind, int targetKind, bool shielded) =>
        EffectiveClassDamageMultiplier(attackerKind, targetKind, shielded);
    private float EffectiveClassDamageMultiplier(int attackerKind, int targetKind, bool shielded)
    {
        float multiplier = GetClassDamageMultiplier(attackerKind, targetKind);
        if (shielded && attackerKind == UnitRanged && targetKind == UnitMelee)
            multiplier *= _settings.ShieldRangedDamageTakenMultiplier;
        return multiplier;
    }
    private int ElevationAt(Vector2 position) => _elevation[Index(CellAt(position))];
    private bool CanGroundStepInternal(Vector2I from, Vector2I to) =>
        GroundNavigation.CanTransition(from, to, _groundBlocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows);
    private bool CellBlocksGround(Vector2I cell) => IsBlocked(cell) || BuildingAt(cell) >= 0;
    private float SeparationDistance(int first, int second) => (UnitRadius(first) + UnitRadius(second)) * BattleConfig.UnitSeparationSpacingMultiplier;
    private float SiegeDamageAtDistance(float centerDistance, float targetRadius, float baseDamage)
    {
        float surface = Mathf.Max(0f, centerDistance - targetRadius);
        if (surface > _settings.SiegeBlastRadius) return 0f;
        float falloff = Mathf.Clamp(surface / _settings.SiegeBlastRadius, 0f, 1f);
        return baseDamage * Mathf.Lerp(1f, _settings.SiegeEdgeDamageMultiplier, falloff);
    }
    private float SiegeFlightSeconds(float distance) => _settings.SiegeFlightSeconds * Mathf.Lerp(BattleConfig.SiegeFlightMinMultiplier, BattleConfig.SiegeFlightMaxMultiplier, Mathf.Clamp(distance / UnitAttackRange(UnitSiege, Vector2.Zero), 0f, 1f));
    private float UnitAttackRange(int kind, Vector2 position) => _settings.Units[kind].AttackRange + (kind == UnitRanged && ElevationAt(position) >= 1 ? _settings.RangedHighGroundBonus : 0f);
    private float UnitDetectRange(int kind) => _settings.Units[kind].DetectRange;
    private float UnitRadius(int kind) => _settings.Units[kind].Radius;
    private float UnitMaxHp(int kind) => _settings.Units[kind].MaxHp;
    private float UnitSpeed(int kind) => _settings.Units[kind].Speed;
    private float UnitAttackDamage(int kind) => _settings.Units[kind].Damage;
    private float UnitAttackInterval(int kind) => _settings.Units[kind].AttackInterval;
    private float ProductionInterval(int kind) => _settings.Units[kind].ProductionInterval;
    private int ProductionBatch(int kind) => _settings.Units[kind].ProductionBatch;
    private float MaximumUnitRadius()
    {
        float maximum = 0f;
        for (int kind = UnitMelee; kind <= UnitSiege; kind++) maximum = Math.Max(maximum, UnitRadius(kind));
        return maximum;
    }
    private float MaximumUnitSpeed()
    {
        float maximum = 0f;
        for (int kind = UnitMelee; kind <= UnitSiege; kind++) maximum = Math.Max(maximum, UnitSpeed(kind));
        return maximum;
    }
    private int BuildCost(int kind) => kind switch
    {
        BuildRangedSpawner => _settings.Units[UnitRanged].SpawnerCost,
        BuildDefenseTower => BattleConfig.DefenseTowerCost,
        BuildDragonLair => _settings.Units[UnitDragon].SpawnerCost,
        BuildSiegeSpawner => _settings.Units[UnitSiege].SpawnerCost,
        BuildRallyPoint => BattleConfig.RallyPointCost,
        _ => _settings.Units[UnitMelee].SpawnerCost,
    };
    private int CountSpawners(int team) { int count = 0; for (int i = 0; i < _buildingCount; i++) if (!_buildings[i].Destroyed && _buildings[i].Team == team && (_buildings[i].Kind == BuildingSpawner || _buildings[i].Kind == BuildingDragonLair)) count++; return count; }
    private int BuildingAt(Vector2I cell) { for (int i = 0; i < _buildingCount; i++) if (!_buildings[i].Destroyed && _buildings[i].Cell == cell) return i; return -1; }
    private int BuildingIndexFromId(int id) { for (int i = 0; i < _buildingCount; i++) if (_buildings[i].Id == id) return i; return -1; }
    private Vector2I BuildingCell(int id) { int index = BuildingIndexFromId(id); return index >= 0 ? _buildings[index].Cell : new Vector2I(-1, -1); }
    private float BuildingHpRatio(int id) { int index = BuildingIndexFromId(id); return index >= 0 ? _buildings[index].Hp / _buildings[index].MaxHp : 0f; }
    private bool InsideHqBuildZone(int team, Vector2I cell) { Vector2I hq = BuildingCell(team == TeamAlly ? _allyHqId : _enemyHqId); return Math.Abs(cell.X - hq.X) <= 2 && Math.Abs(cell.Y - hq.Y) <= 2; }
    private float PopulationIncomeMultiplier(int team)
    {
        int steps = Math.Clamp(_teamUnitCounts[team] / BattleConfig.PopulationIncomeStepUnits, 0, 10);
        return Mathf.Max(0f, 1f - steps * BattleConfig.PopulationIncomePenaltyPerStep);
    }

    private float AiIncomeMultiplier() => _aiIncomeLevel switch
    {
        1 => 1f,
        2 => 1.25f,
        3 => 1.5f,
        4 => 1.75f,
        _ => 2f,
    };

    private void AwardKill(int team)
    {
        if (team == TeamAlly)
        {
            _allyIncomeRemainder += BattleConfig.KillReward * PopulationIncomeMultiplier(TeamAlly);
            int payout = Mathf.FloorToInt(_allyIncomeRemainder + 0.000001f);
            _allyGold += payout;
            _allyIncomeRemainder -= payout;
        }
        else if (team == TeamEnemy)
        {
            _enemyIncomeRemainder += BattleConfig.KillReward * PopulationIncomeMultiplier(TeamEnemy) * AiIncomeMultiplier();
            int payout = Mathf.FloorToInt(_enemyIncomeRemainder + 0.000001f);
            _enemyGold += payout;
            _enemyIncomeRemainder -= payout;
        }
    }
}
