using Godot;
using System;
using System.Collections.Generic;

public partial class BattleSimulation
{
    private static readonly Vector2[] FiringDirections =
    {
        new(1f, 0f), new(0.9238795f, 0.3826834f), new(0.7071068f, 0.7071068f), new(0.3826834f, 0.9238795f),
        new(0f, 1f), new(-0.3826834f, 0.9238795f), new(-0.7071068f, 0.7071068f), new(-0.9238795f, 0.3826834f),
        new(-1f, 0f), new(-0.9238795f, -0.3826834f), new(-0.7071068f, -0.7071068f), new(-0.3826834f, -0.9238795f),
        new(0f, -1f), new(0.3826834f, -0.9238795f), new(0.7071068f, -0.7071068f), new(0.9238795f, -0.3826834f),
    };

    private void BeginFiringYieldPass()
    {
        for (int touched = 0; touched < _yieldTouchedCount; touched++)
        {
            int index = _yieldTouchedIndices[touched];
            _yieldCorrections[index] = Vector2.Zero;
            _yieldTouched[index] = 0;
        }
        _yieldTouchedCount = 0;
    }

    private void RefreshFiringReservation(int index)
    {
        if (_kinds[index] != UnitRanged || _foundTargetId == 0)
        {
            ClearFiringReservation(index);
            return;
        }

        Vector2 position = _positions[index];
        Vector2 target = _foundTargetPosition;
        float attackRange = UnitAttackRange(UnitRanged, position);
        float preferredRange = attackRange * _settings.PreferredFiringRangeRatio;
        float contactRange = attackRange + FoundTargetRadius();
        Vector2 approach = target.DirectionTo(position);
        if (approach.LengthSquared() <= 0.000001f)
            approach = _teams[index] == TeamAlly ? Vector2.Down : Vector2.Up;

        Span<byte> reservations = stackalloc byte[BattleConfig.FiringCandidateCount];
        AggregateFiringReservations(index, _foundTargetId, target, reservations);
        const int reachabilitySize = (BattleConfig.RecoveryWindowRadius * 2 + 1) * (BattleConfig.RecoveryWindowRadius * 2 + 1);
        Span<byte> reachable = stackalloc byte[reachabilitySize];
        BuildLocalFiringReachability(index, reachable, out int minimumCol, out int minimumRow, out int localWidth, out int localHeight);
        int[] density = _teams[index] == TeamEnemy ? _enemyDensity : _allyDensity;
        FlowField flow = SelectFlow(index);
        int bestSlot = -1;
        float bestScore = float.PositiveInfinity;
        Vector2 bestPosition = position;
        int fallbackSlot = -1;
        float fallbackScore = float.PositiveInfinity;
        Vector2 fallbackPosition = position;
        for (int offset = 0; offset < BattleConfig.FiringCandidateCount; offset++)
        {
            int slot = (offset + (_ids[index] & 1) * 8) & 15;
            Vector2 radial = FiringDirections[slot];
            Vector2 candidate = target + radial * preferredRange;
            if (!FiringCandidateIsValid(index, candidate, target, contactRange, flow, reachable,
                minimumCol, minimumRow, localWidth, localHeight, out Vector2I cell, out float flowCost))
                continue;
            int previous = (slot + BattleConfig.FiringCandidateCount - 1) & 15;
            int next = (slot + 1) & 15;
            int previousTwo = (slot + BattleConfig.FiringCandidateCount - 2) & 15;
            int nextTwo = (slot + 2) & 15;
            float score = position.DistanceSquaredTo(candidate) * BattleConfig.FiringTravelScoreWeight
                + density[Index(cell)] * BattleConfig.FiringDensityScoreWeight
                + flowCost * BattleConfig.FiringFlowScoreWeight
                + reservations[slot] * BattleConfig.FiringReservationScoreWeight
                + (reservations[previous] + reservations[next]) * BattleConfig.FiringAdjacentReservationScoreWeight
                + (reservations[previousTwo] + reservations[nextTwo]) * (BattleConfig.FiringAdjacentReservationScoreWeight * 0.35f);
            if (radial.Dot(approach) >= -0.05f)
            {
                if (score < bestScore - 0.0001f || Mathf.IsEqualApprox(score, bestScore) && slot < bestSlot)
                {
                    bestScore = score;
                    bestSlot = slot;
                    bestPosition = candidate;
                }
            }
            else
            {
                score += BattleConfig.FiringApproachSidePenalty;
                if (score < fallbackScore - 0.0001f || Mathf.IsEqualApprox(score, fallbackScore) && slot < fallbackSlot)
                {
                    fallbackScore = score;
                    fallbackSlot = slot;
                    fallbackPosition = candidate;
                }
            }
        }

        if (bestSlot < 0 && fallbackSlot >= 0)
        {
            bestSlot = fallbackSlot;
            bestPosition = fallbackPosition;
        }
        if (bestSlot < 0)
        {
            ClearFiringReservation(index);
            return;
        }
        bool changed = _firingTargetIds[index] != _foundTargetId || _firingSlotIndices[index] != bestSlot
            || _firingPositions[index].DistanceSquaredTo(bestPosition) > BattleConfig.FiringLateralThreshold * BattleConfig.FiringLateralThreshold;
        _firingTargetIds[index] = _foundTargetId;
        _firingPositions[index] = bestPosition;
        _firingSlotIndices[index] = bestSlot;
        _firingLateral[index] = IsGenuinelyLateralReservation(position, target, bestPosition) ? (byte)1 : (byte)0;
        if (changed)
        {
            _recoveryActive[index] = 0;
            _stuckTimers[index] = 0f;
            _progressOrigins[index] = position;
        }
    }

    private void AggregateFiringReservations(int index, int targetId, Vector2 target, Span<byte> reservations)
    {
        List<int>[] buckets = _teams[index] == TeamEnemy ? _enemyBuckets : _allyBuckets;
        Vector2I center = CellAt(target);
        int radius = Mathf.CeilToInt(UnitDetectRange(UnitRanged) + MaximumUnitRadius());
        for (int row = Math.Max(0, center.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, center.Y + radius); row++)
            for (int col = Math.Max(0, center.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, center.X + radius); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    if (candidate == index || _hp[candidate] <= 0f || _kinds[candidate] != UnitRanged
                        || _firingTargetIds[candidate] != targetId) continue;
                    int slot = _firingSlotIndices[candidate];
                    if (slot >= 0 && slot < reservations.Length && reservations[slot] < byte.MaxValue)
                        reservations[slot]++;
                }
    }

    private bool FiringCandidateIsValid(int index, Vector2 candidate, Vector2 target, float contactRange,
        FlowField flow, ReadOnlySpan<byte> reachable, int minimumCol, int minimumRow, int localWidth, int localHeight,
        out Vector2I cell, out float flowCost)
    {
        cell = CellAt(candidate);
        flowCost = flow.CostAt(cell);
        if (!float.IsFinite(flowCost) || candidate.DistanceSquaredTo(target) > contactRange * contactRange)
            return false;
        return GroundNavigation.CanOccupyPosition(candidate, UnitRadius(_kinds[index]), _groundBlocked, _elevation,
            BattleConfig.GridColumns, BattleConfig.GridRows)
            && FiringCandidateIsLocallyReachable(cell, reachable, minimumCol, minimumRow, localWidth, localHeight);
    }

    private void BuildLocalFiringReachability(int index, Span<byte> reachable, out int minimumCol,
        out int minimumRow, out int localWidth, out int localHeight)
    {
        const int radius = BattleConfig.RecoveryWindowRadius;
        const int diameter = radius * 2 + 1;
        Vector2I start = CellAt(_positions[index]);
        minimumCol = Math.Max(0, start.X - radius);
        minimumRow = Math.Max(0, start.Y - radius);
        int maximumCol = Math.Min(BattleConfig.GridColumns - 1, start.X + radius);
        int maximumRow = Math.Min(BattleConfig.GridRows - 1, start.Y + radius);
        localWidth = maximumCol - minimumCol + 1;
        localHeight = maximumRow - minimumRow + 1;
        Span<int> queue = stackalloc int[diameter * diameter];
        reachable.Clear();
        int head = 0;
        int tail = 0;
        int startLocal = (start.Y - minimumRow) * localWidth + start.X - minimumCol;
        queue[tail++] = Index(start);
        reachable[startLocal] = 1;
        byte[] blocked = SelectFlowBlocked(index);
        while (head < tail)
        {
            int cellIndex = queue[head++];
            Vector2I cell = new(cellIndex % BattleConfig.GridColumns, cellIndex / BattleConfig.GridColumns);
            for (int y = -1; y <= 1; y++)
                for (int x = -1; x <= 1; x++)
                {
                    if (x == 0 && y == 0) continue;
                    Vector2I next = cell + new Vector2I(x, y);
                    if (next.X < minimumCol || next.X > maximumCol || next.Y < minimumRow || next.Y > maximumRow) continue;
                    int local = (next.Y - minimumRow) * localWidth + next.X - minimumCol;
                    if (reachable[local] != 0 || !GroundNavigation.CanTransition(cell, next, blocked, _elevation,
                        BattleConfig.GridColumns, BattleConfig.GridRows)) continue;
                    reachable[local] = 1;
                    queue[tail++] = Index(next);
                }
        }
    }

    private static bool FiringCandidateIsLocallyReachable(Vector2I goal, ReadOnlySpan<byte> reachable,
        int minimumCol, int minimumRow, int localWidth, int localHeight)
    {
        int localX = goal.X - minimumCol;
        int localY = goal.Y - minimumRow;
        return localX >= 0 && localX < localWidth && localY >= 0 && localY < localHeight
            && reachable[localY * localWidth + localX] != 0;
    }

    private static bool IsGenuinelyLateralReservation(Vector2 position, Vector2 target, Vector2 candidate)
    {
        Vector2 towardTarget = position.DirectionTo(target);
        if (towardTarget.LengthSquared() <= 0.000001f) return false;
        Vector2 tangent = new(-towardTarget.Y, towardTarget.X);
        return Mathf.Abs((candidate - position).Dot(tangent)) >= BattleConfig.FiringLateralThreshold;
    }

    private void ValidateFiringReservation(int index)
    {
        if (_kinds[index] != UnitRanged || _foundTargetId == 0 || _firingTargetIds[index] != _foundTargetId
            || _firingSlotIndices[index] < 0)
        {
            ClearFiringReservation(index);
            return;
        }
        FlowField flow = SelectFlow(index);
        Vector2 candidate = _firingPositions[index];
        Vector2I cell = CellAt(candidate);
        if (!float.IsFinite(flow.CostAt(cell)) || !GroundNavigation.CanOccupyPosition(candidate, UnitRadius(UnitRanged),
            _groundBlocked, _elevation, BattleConfig.GridColumns, BattleConfig.GridRows))
            ClearFiringReservation(index);
    }

    private void ClearFiringReservation(int index)
    {
        if (_firingTargetIds[index] == 0 && _firingSlotIndices[index] < 0 && _firingLateral[index] == 0) return;
        _firingTargetIds[index] = 0;
        _firingPositions[index] = _positions[index];
        _firingSlotIndices[index] = -1;
        _firingLateral[index] = 0;
    }

    private bool HasUsableLateralFiringSlot(int index) =>
        _kinds[index] == UnitRanged && _firingTargetIds[index] != 0 && _firingLateral[index] != 0
        && _firingSlotIndices[index] >= 0;

    private bool ShouldWaitForFiringQueue(int index, Vector2 forward)
    {
        if (_kinds[index] != UnitRanged || _foundTargetId == 0 || HasUsableLateralFiringSlot(index)
            || forward.LengthSquared() <= 0.000001f) return false;
        forward = forward.Normalized();
        Vector2 tangent = new(-forward.Y, forward.X);
        Vector2 position = _positions[index];
        List<int>[] buckets = _teams[index] == TeamEnemy ? _enemyBuckets : _allyBuckets;
        Vector2I center = CellAt(position);
        int radius = Mathf.CeilToInt(BattleConfig.FiringQueueLookahead);
        for (int row = Math.Max(0, center.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, center.Y + radius); row++)
            for (int col = Math.Max(0, center.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, center.X + radius); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    if (candidate == index || _hp[candidate] <= 0f || _kinds[candidate] != UnitRanged
                        || HasUsableLateralFiringSlot(candidate)) continue;
                    int candidateTarget = _firingTargetIds[candidate] != 0 ? _firingTargetIds[candidate] : _targetIds[candidate];
                    if (candidateTarget != _foundTargetId) continue;
                    Vector2 offset = _positions[candidate] - position;
                    float longitudinal = offset.Dot(forward);
                    float halfWidth = SeparationDistance(UnitRanged, UnitRanged) + BattleConfig.FiringQueueHalfWidthPadding;
                    if (longitudinal > 0f && longitudinal <= BattleConfig.FiringQueueLookahead
                        && Mathf.Abs(offset.Dot(tangent)) <= halfWidth)
                        return true;
                }
        return false;
    }

    private Vector2 FiringSeekDirection(int index, Vector2 fallbackTarget)
    {
        if (_kinds[index] != UnitRanged || _firingTargetIds[index] == 0 || _firingSlotIndices[index] < 0)
            return _positions[index].DirectionTo(fallbackTarget);
        Vector2 offset = _firingPositions[index] - _positions[index];
        return offset.LengthSquared() > BattleConfig.FiringSlotArrivalRadius * BattleConfig.FiringSlotArrivalRadius
            ? offset.Normalized() : Vector2.Zero;
    }

    private Vector2 FiringCombatDirection(int index, bool shouldKite, Vector2 targetPosition)
    {
        Vector2 result = shouldKite ? targetPosition.DirectionTo(_positions[index]) : Vector2.Zero;
        if (_firingTargetIds[index] != 0 && _firingSlotIndices[index] >= 0)
        {
            Vector2 offset = _firingPositions[index] - _positions[index];
            if (offset.LengthSquared() > BattleConfig.FiringSlotArrivalRadius * BattleConfig.FiringSlotArrivalRadius)
                result += offset.Normalized() * BattleConfig.FiringLateralCorrectionWeight;
        }
        result += CalculateSeparation(index) * BattleConfig.FiringCombatSeparationWeight;
        return result.LengthSquared() > 0.000001f ? result.Normalized() : Vector2.Zero;
    }

    private void AccumulateFiringYield(int index, Vector2 desired)
    {
        if (!HasUsableLateralFiringSlot(index) || desired.LengthSquared() <= 0.000001f) return;
        Vector2 position = _positions[index];
        Vector2 towardTarget = position.DirectionTo(_cachedTargetPositions[index]);
        if (towardTarget.LengthSquared() <= 0.000001f) return;
        Vector2 tangent = new(-towardTarget.Y, towardTarget.X);
        float tangentSign = Mathf.Sign(desired.Dot(tangent));
        if (Mathf.IsZeroApprox(tangentSign)) return;
        tangent *= tangentSign;
        List<int>[] buckets = _teams[index] == TeamEnemy ? _enemyBuckets : _allyBuckets;
        Vector2I center = CellAt(position);
        int blocker = -1;
        float bestDistanceSq = float.PositiveInfinity;
        float query = SeparationDistance(_kinds[index], UnitRanged) + BattleConfig.WaitCheckRadius;
        for (int row = Math.Max(0, center.Y - 1); row <= Math.Min(BattleConfig.GridRows - 1, center.Y + 1); row++)
            for (int col = Math.Max(0, center.X - 1); col <= Math.Min(BattleConfig.GridColumns - 1, center.X + 1); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    if (candidate == index || _hp[candidate] <= 0f || _kinds[candidate] == UnitDragon
                        || _states[candidate] != StateAttack || _velocities[candidate].LengthSquared() > BattleConfig.WaitSlowSpeed * BattleConfig.WaitSlowSpeed)
                        continue;
                    Vector2 offset = _positions[candidate] - position;
                    float distanceSq = offset.LengthSquared();
                    if (distanceSq > query * query || offset.Dot(desired) <= 0f || distanceSq >= bestDistanceSq) continue;
                    blocker = candidate;
                    bestDistanceSq = distanceSq;
                }
        if (blocker < 0) return;
        float distance = Mathf.Sqrt(bestDistanceSq);
        float strength = Mathf.Clamp(1f - distance / query, 0.15f, 1f);
        AddYieldCorrection(index, tangent * (BattleConfig.FiringYieldMoverWeight * strength));
        AddYieldCorrection(blocker, -tangent * (BattleConfig.FiringYieldBlockerWeight * strength));
    }

    private void AddYieldCorrection(int index, Vector2 correction)
    {
        if (_yieldTouched[index] == 0)
        {
            _yieldTouched[index] = 1;
            _yieldTouchedIndices[_yieldTouchedCount++] = index;
        }
        Vector2 combined = _yieldCorrections[index] + correction;
        if (combined.LengthSquared() > BattleConfig.FiringYieldMaximum * BattleConfig.FiringYieldMaximum)
            combined = combined.Normalized() * BattleConfig.FiringYieldMaximum;
        _yieldCorrections[index] = combined;
    }

    private void ApplyFiringYieldCorrections(float delta)
    {
        for (int touched = 0; touched < _yieldTouchedCount; touched++)
        {
            int index = _yieldTouchedIndices[touched];
            Vector2 correction = _yieldCorrections[index];
            if (_hp[index] > 0f && _kinds[index] != UnitDragon && correction.LengthSquared() > 0.000001f)
            {
                Vector2 motion = correction * (BattleConfig.FiringYieldSpeed * delta);
                _positions[index] = MoveGround(_positions[index], motion, UnitRadius(_kinds[index]));
            }
            _yieldCorrections[index] = Vector2.Zero;
            _yieldTouched[index] = 0;
        }
        _yieldTouchedCount = 0;
    }
}
