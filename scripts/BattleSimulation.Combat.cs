using Godot;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Collections.Generic;

public partial class BattleSimulation
{
    private void FindTarget(int unitIndex)
    {
        Vector2 position = _positions[unitIndex];
        int team = _teams[unitIndex];
        bool canTargetAir = _kinds[unitIndex] != UnitMelee;
        float detectRange = UnitDetectRange(_kinds[unitIndex]);
        SeedRetainedTarget(_targetIds[unitIndex], team, position, canTargetAir, detectRange, out float bestDistanceSq);
        List<int>[] buckets = team == TeamEnemy ? _allyBuckets : _enemyBuckets;
        Vector2I cell = CellAt(position);
        int radius = Mathf.CeilToInt(detectRange);
        for (int row = Math.Max(0, cell.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + radius); row++)
            for (int col = Math.Max(0, cell.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + radius); col++)
            {
                if (!BucketCanContainNearer(position, col, row, bestDistanceSq)) continue;
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    _targetCandidateChecks++;
                    if (_hp[candidate] <= 0f || (!canTargetAir && _kinds[candidate] == UnitDragon)) continue;
                    float distanceSq = position.DistanceSquaredTo(_positions[candidate]);
                    if (distanceSq > bestDistanceSq) continue;
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
            if (distanceSq > bestDistanceSq) continue;
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
        Vector2I originCell = CellAt(origin);
        int radius = Mathf.CeilToInt(BattleConfig.SiegeRange);
        int bestScore = -1;
        float bestDistanceSq = float.PositiveInfinity;
        int bestPointIndex = int.MaxValue;
        Vector2 bestPoint = new(-1f, -1f);
        for (int row = Math.Max(0, originCell.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, originCell.Y + radius); row++)
            for (int col = Math.Max(0, originCell.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, originCell.X + radius); col++)
            {
                Vector2 point = new(col + 0.5f, row + 0.5f);
                float distanceSq = origin.DistanceSquaredTo(point);
                if (distanceSq < BattleConfig.SiegeMinRange * BattleConfig.SiegeMinRange || distanceSq > BattleConfig.SiegeRange * BattleConfig.SiegeRange)
                    continue;
                int pointIndex = Index(new Vector2I(col, row));
                int score = density[pointIndex];
                if (score > bestScore || (score == bestScore && score > 0 && (distanceSq < bestDistanceSq - 0.000001f || (Mathf.IsEqualApprox(distanceSq, bestDistanceSq) && pointIndex < bestPointIndex))))
                {
                    bestScore = score;
                    bestDistanceSq = distanceSq;
                    bestPointIndex = pointIndex;
                    bestPoint = point;
                }
            }
        return bestScore > 0 ? bestPoint : new Vector2(-1f, -1f);
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
        int bucketRadius = Mathf.CeilToInt(radius + BattleConfig.DragonRadius);
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
        for (int row = Math.Max(0, cell.Y - 1); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + 1); row++)
            for (int col = Math.Max(0, cell.X - 1); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + 1); col++)
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
        if (_kinds[index] == UnitDragon)
        {
            int hqId = team == TeamAlly ? _enemyHqId : _allyHqId;
            Vector2I hq = BuildingCell(hqId);
            direction = _positions[index].DirectionTo(new Vector2(hq.X + 0.5f, hq.Y + 0.5f));
        }
        else
        {
            direction = team == TeamAlly ? _allyFlow.DirectionAt(CellAt(_positions[index])) : _enemyFlow.DirectionAt(CellAt(_positions[index]));
            if (direction == Vector2.Zero) direction = team == TeamAlly ? Vector2.Up : Vector2.Down;
        }
        return direction.Rotated(_flowBiasRadians[index]);
    }

    private Vector2 MoveGround(Vector2 position, Vector2 motion)
    {
        Vector2I from = CellAt(position);
        Span<Vector2> candidates = stackalloc Vector2[3] { motion, new Vector2(motion.X, 0f), new Vector2(0f, motion.Y) };
        foreach (Vector2 candidateMotion in candidates)
        {
            Vector2 candidate = position + candidateMotion;
            candidate.X = Mathf.Clamp(candidate.X, 0.2f, BattleConfig.GridColumns - 0.2f);
            candidate.Y = Mathf.Clamp(candidate.Y, 0.5f, BattleConfig.GridRows - 0.5f);
            Vector2I cell = CellAt(candidate);
            if (!CellBlocksGround(cell) && CanGroundStepInternal(from, cell)) return candidate;
        }
        return position;
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
            if (kind == UnitRanged) QueueShot(ShotRanged, team, origin, _positions[targetUnit]);
            float multiplier = ElevationDamageMultiplier(origin, _positions[targetUnit]);
            _hp[targetUnit] -= UnitAttackDamage(kind) * multiplier;
            _lastAttackerTeams[targetUnit] = team;
            QueueHit(targetUnit, multiplier > 1f);
        }
        else if (buildingIndex >= 0 && buildingIndex < _buildingCount)
        {
            Vector2I cell = _buildings[buildingIndex].Cell;
            Vector2 at = new(cell.X + 0.5f, cell.Y + 0.5f);
            if (kind == UnitRanged) QueueShot(ShotRanged, team, origin, at);
            ApplyBuildingDamage(_buildings[buildingIndex].Id, UnitAttackDamage(kind) * ElevationDamageMultiplier(origin, at), team);
        }
    }

    private void LaunchSiege(int attacker, Vector2 target)
    {
        _cooldowns[attacker] = BattleConfig.SiegeAttackInterval;
        _lungeTimers[attacker] = BattleConfig.UnitLungeDuration;
        float duration = SiegeFlightSeconds(_positions[attacker].DistanceTo(target));
        ScheduleSiegeImpact(_teams[attacker], _positions[attacker], target, BattleConfig.SiegeDamage, duration);
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
        int radius = Mathf.CeilToInt(BattleConfig.SiegeBlastRadius + BattleConfig.DragonRadius);
        for (int row = Math.Max(0, cell.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, cell.Y + radius); row++)
            for (int col = Math.Max(0, cell.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, cell.X + radius); col++)
                foreach (int candidate in buckets[Index(new Vector2I(col, row))])
                {
                    _aoeCandidateChecks++;
                    if (_hp[candidate] <= 0f) continue;
                    float damage = SiegeDamageAtDistance(impact.Target.DistanceTo(_positions[candidate]), UnitRadius(_kinds[candidate]), impact.Damage);
                    if (damage <= 0f) continue;
                    float multiplier = ElevationDamageMultiplier(impact.Origin, _positions[candidate]);
                    _hp[candidate] -= damage * multiplier;
                    _lastAttackerTeams[candidate] = impact.Team;
                    QueueHit(candidate, multiplier > 1f);
                }
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            if (building.Destroyed || building.Team == impact.Team) continue;
            Vector2 at = new(building.Cell.X + 0.5f, building.Cell.Y + 0.5f);
            float damage = SiegeDamageAtDistance(impact.Target.DistanceTo(at), BattleConfig.BuildingTargetRadius, impact.Damage);
            if (damage > 0f) ApplyBuildingDamage(building.Id, damage * ElevationDamageMultiplier(impact.Origin, at), impact.Team);
        }
        _events.Add(new GDictionary { ["type"] = "siege_impact", ["team"] = impact.Team, ["position"] = impact.Target, ["radius"] = BattleConfig.SiegeBlastRadius });
    }

    private void ApplyBuildingDamage(int id, float damage, int attackerTeam)
    {
        int index = BuildingIndexFromId(id);
        if (index < 0 || _buildings[index].Destroyed) return;
        ref Building building = ref _buildings[index];
        building.Hp = Mathf.Max(0f, building.Hp - damage);
        _boardVersion++;
        string type = building.Kind == BuildingHq ? "hq_hit" : "spawner_hit";
        _events.Add(new GDictionary { ["type"] = type, ["team"] = building.Team, ["building_id"] = id, ["cell"] = building.Cell });
        if (building.Hp > 0f) return;
        building.Destroyed = true;
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
        int deadId = _ids[index];
        int last = --_unitCount;
        _indexById[deadId] = -1;
        if (index == last) return;
        _ids[index] = _ids[last]; _teams[index] = _teams[last]; _kinds[index] = _kinds[last]; _states[index] = _states[last];
        _targetIds[index] = _targetIds[last]; _lastAttackerTeams[index] = _lastAttackerTeams[last];
        _positions[index] = _positions[last]; _velocities[index] = _velocities[last]; _lungeDirections[index] = _lungeDirections[last];
        _cachedTargetPositions[index] = _cachedTargetPositions[last]; _cachedSteering[index] = _cachedSteering[last]; _siegeTargetPositions[index] = _siegeTargetPositions[last];
        _hp[index] = _hp[last]; _cooldowns[index] = _cooldowns[last]; _speedScales[index] = _speedScales[last]; _lungeTimers[index] = _lungeTimers[last];
        _flowBiasRadians[index] = _flowBiasRadians[last]; _cachedTargetRadii[index] = _cachedTargetRadii[last]; _hpBarTimers[index] = _hpBarTimers[last]; _cachedWaiting[index] = _cachedWaiting[last];
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

    private Vector2 FindSpawnPosition(Vector2I cell, int team, bool flying)
    {
        int forward = team == TeamAlly ? -1 : 1;
        Span<Vector2I> candidates = stackalloc Vector2I[6]
        {
            cell + new Vector2I(0, forward), cell + new Vector2I(-1, forward), cell + new Vector2I(1, forward),
            cell + Vector2I.Left, cell + Vector2I.Right, cell + new Vector2I(0, -forward),
        };
        foreach (Vector2I candidate in candidates)
            if (Valid(candidate) && (flying || (!CellBlocksGround(candidate) && CanGroundStepInternal(cell, candidate))))
                return new Vector2(candidate.X + 0.5f, candidate.Y + 0.5f);
        return new Vector2(-1f, -1f);
    }

    private bool BucketCanContainNearer(Vector2 position, int col, int row, float bestDistanceSq)
    {
        float slop = BattleConfig.MeleeSpeed * (1f + BattleConfig.UnitSpeedVariation) / BattleConfig.SimTickRate;
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
    private int ElevationAt(Vector2 position) => _elevation[Index(CellAt(position))];
    private bool CanGroundStepInternal(Vector2I from, Vector2I to) => Valid(from) && Valid(to) && Math.Abs(_elevation[Index(from)] - _elevation[Index(to)]) <= 1;
    private bool CellBlocksGround(Vector2I cell) => IsBlocked(cell) || BuildingAt(cell) >= 0;
    private float SeparationDistance(int first, int second) => (UnitRadius(first) + UnitRadius(second)) * BattleConfig.UnitSeparationSpacingMultiplier;
    private float SiegeDamageAtDistance(float centerDistance, float targetRadius, float baseDamage)
    {
        float surface = Mathf.Max(0f, centerDistance - targetRadius);
        if (surface > BattleConfig.SiegeBlastRadius) return 0f;
        float falloff = Mathf.Clamp(surface / BattleConfig.SiegeBlastRadius, 0f, 1f);
        return baseDamage * Mathf.Lerp(1f, BattleConfig.SiegeEdgeDamageMultiplier, falloff);
    }
    private float SiegeFlightSeconds(float distance) => BattleConfig.SiegeFlightSeconds * Mathf.Lerp(BattleConfig.SiegeFlightMinMultiplier, BattleConfig.SiegeFlightMaxMultiplier, Mathf.Clamp(distance / BattleConfig.SiegeRange, 0f, 1f));
    private float UnitAttackRange(int kind, Vector2 position) => kind == UnitDragon ? BattleConfig.DragonRange : kind == UnitRanged ? BattleConfig.RangedRange + (ElevationAt(position) >= 1 ? BattleConfig.RangedHighGroundRangeBonus : 0f) : kind == UnitSiege ? BattleConfig.SiegeRange : BattleConfig.MeleeRange;
    private static float UnitDetectRange(int kind) => kind == UnitDragon ? BattleConfig.DragonDetectRange : kind == UnitRanged ? BattleConfig.RangedDetectRange : kind == UnitSiege ? BattleConfig.SiegeRange : BattleConfig.UnitDetectRange;
    private static float UnitRadius(int kind) => kind == UnitRanged ? BattleConfig.RangedRadius : kind == UnitDragon ? BattleConfig.DragonRadius : kind == UnitSiege ? BattleConfig.SiegeRadius : BattleConfig.MeleeRadius;
    private static float UnitMaxHp(int kind) => kind == UnitRanged ? BattleConfig.RangedHp : kind == UnitDragon ? BattleConfig.DragonHp : kind == UnitSiege ? BattleConfig.SiegeHp : BattleConfig.MeleeHp;
    private static float UnitSpeed(int kind) => kind == UnitRanged ? BattleConfig.RangedSpeed : kind == UnitDragon ? BattleConfig.DragonSpeed : kind == UnitSiege ? BattleConfig.SiegeSpeed : BattleConfig.MeleeSpeed;
    private static float UnitAttackDamage(int kind) => kind == UnitRanged ? BattleConfig.RangedDamage : kind == UnitDragon ? BattleConfig.DragonDamage : kind == UnitSiege ? BattleConfig.SiegeDamage : BattleConfig.MeleeDamage;
    private static float UnitAttackInterval(int kind) => kind == UnitRanged ? BattleConfig.RangedAttackInterval : kind == UnitDragon ? BattleConfig.DragonAttackInterval : kind == UnitSiege ? BattleConfig.SiegeAttackInterval : BattleConfig.MeleeAttackInterval;
    private static int SpawnerCost(int kind) => kind == UnitSiege ? BattleConfig.SiegeSpawnerCost : kind == UnitRanged ? BattleConfig.RangedSpawnerCost : BattleConfig.SpawnerCost;
    private static int BuildCost(int kind) => kind == BuildRangedSpawner ? BattleConfig.RangedSpawnerCost : kind == BuildSiegeSpawner ? BattleConfig.SiegeSpawnerCost : kind == BuildDefenseTower ? BattleConfig.DefenseTowerCost : kind == BuildDragonLair ? BattleConfig.DragonLairCost : BattleConfig.SpawnerCost;
    private int CountSpawners(int team) { int count = 0; for (int i = 0; i < _buildingCount; i++) if (!_buildings[i].Destroyed && _buildings[i].Team == team && _buildings[i].Kind == BuildingSpawner) count++; return count; }
    private int BuildingAt(Vector2I cell) { for (int i = 0; i < _buildingCount; i++) if (!_buildings[i].Destroyed && _buildings[i].Cell == cell) return i; return -1; }
    private int BuildingIndexFromId(int id) { for (int i = 0; i < _buildingCount; i++) if (_buildings[i].Id == id) return i; return -1; }
    private Vector2I BuildingCell(int id) { int index = BuildingIndexFromId(id); return index >= 0 ? _buildings[index].Cell : new Vector2I(-1, -1); }
    private float BuildingHpRatio(int id) { int index = BuildingIndexFromId(id); return index >= 0 ? _buildings[index].Hp / _buildings[index].MaxHp : 0f; }
    private bool InsideHqBuildZone(int team, Vector2I cell) { Vector2I hq = BuildingCell(team == TeamAlly ? _allyHqId : _enemyHqId); return Math.Abs(cell.X - hq.X) <= 2 && Math.Abs(cell.Y - hq.Y) <= 2; }
    private void AwardKill(int team) { if (team == TeamAlly) _allyGold += BattleConfig.KillReward; else if (team == TeamEnemy) _enemyGold += BattleConfig.KillReward; }
}
