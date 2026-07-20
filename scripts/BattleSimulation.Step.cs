using Godot;
using GDictionary = Godot.Collections.Dictionary;
using System;
using System.Collections.Generic;
using System.Diagnostics;

public partial class BattleSimulation
{
    private void FixedStep(float delta)
    {
        long tickStart = _profilingEnabled ? Stopwatch.GetTimestamp() : 0;
        ApplyIncome(delta);
        _timeRemaining = Mathf.Max(0f, _timeRemaining - delta);
        UpdateEnemyAi(delta);
        UpdateSpawners(delta);
        RebuildBuckets();
        _aoeCandidateChecks = 0;
        _siegeImpactsResolved = 0;
        long eventStart = _profilingEnabled ? Stopwatch.GetTimestamp() : 0;
        AdvanceSiegeImpacts(delta);
        if (_profilingEnabled) _profileEventUsec += Usec(eventStart);
        _congestionTimer -= delta;
        if (_congestionTimer <= 0f)
        {
            RebuildFlowForTeam(_nextFlowTeam);
            _nextFlowTeam = _nextFlowTeam == TeamEnemy ? TeamAlly : TeamEnemy;
            _congestionTimer += BattleConfig.CongestionRebuildInterval * 0.5f;
        }
        UpdateStaticDefenses(delta);
        _targetCandidateChecks = 0;
        for (int index = 0; index < _unitCount; index++)
        {
            if (_hp[index] <= 0f) continue;
            _cooldowns[index] = Mathf.Max(0f, _cooldowns[index] - delta);
            _lungeTimers[index] = Mathf.Max(0f, _lungeTimers[index] - delta);
            bool refresh = (_ids[index] - 1) % BattleConfig.DecisionGroupCount == _decisionCursor;
            long targetStart = _profilingEnabled ? Stopwatch.GetTimestamp() : 0;
            if (refresh)
            {
                _decisionRefreshCount++;
                if (_kinds[index] == UnitSiege)
                {
                    if (_cooldowns[index] <= 0f) FindSiegeTarget(index);
                    else RestoreCachedTarget(index);
                }
                else FindTarget(index);
                CacheFoundTarget(index);
            }
            else RestoreCachedTarget(index);
            if (_profilingEnabled) _profileTargetUsec += Usec(targetStart);

            Vector2 position = _positions[index];
            float range = UnitAttackRange(_kinds[index], position);
            float contactRange = range + FoundTargetRadius();
            float targetDistanceSq = position.DistanceSquaredTo(_foundTargetPosition);
            bool inRange = _foundTargetId != 0 && targetDistanceSq <= contactRange * contactRange;
            if (_kinds[index] == UnitSiege)
                inRange = _foundTargetId != 0 && targetDistanceSq >= BattleConfig.SiegeMinRange * BattleConfig.SiegeMinRange && targetDistanceSq <= range * range;
            if (inRange)
            {
                _states[index] = StateAttack;
                _lungeDirections[index] = position.DirectionTo(_foundTargetPosition);
                _velocities[index] = _velocities[index].MoveToward(Vector2.Zero, UnitSpeed(_kinds[index]) * BattleConfig.UnitTurnRate * delta);
                if (_cooldowns[index] <= 0f)
                {
                    if (_kinds[index] == UnitSiege) LaunchSiege(index, _foundTargetPosition);
                    else AttackTarget(index, _foundUnitIndex, _foundBuildingIndex);
                }
                continue;
            }

            long separationStart = _profilingEnabled ? Stopwatch.GetTimestamp() : 0;
            if (refresh)
            {
                Vector2 advance = AdvanceDirection(index);
                Vector2 seek = _foundTargetId != 0 ? position.DirectionTo(_foundTargetPosition) : Vector2.Zero;
                Vector2 separation = CalculateSeparation(index);
                bool waiting = _kinds[index] != UnitDragon && ShouldWait(index, advance);
                Vector2 steering = separation * (waiting ? BattleConfig.WaitSeparationWeight : BattleConfig.UnitSeparationWeight);
                if (!waiting)
                {
                    steering += advance * BattleConfig.UnitAdvanceWeight + seek * BattleConfig.UnitSeekWeight;
                    if (_kinds[index] != UnitDragon)
                        steering += CalculateObstacleRepulsion(position) * BattleConfig.GroundBlockRepulsionWeight;
                }
                _cachedSteering[index] = steering;
                _cachedWaiting[index] = waiting ? (byte)1 : (byte)0;
            }
            bool isWaiting = _cachedWaiting[index] != 0;
            Vector2 desired = _cachedSteering[index];
            _states[index] = isWaiting ? StateWait : StateAdvance;
            float maximumSpeed = UnitSpeed(_kinds[index]) * _speedScales[index];
            if (_kinds[index] != UnitDragon && desired.LengthSquared() > 0.000001f)
                maximumSpeed *= GroundSpeedMultiplier(position, position + desired.Normalized());
            Vector2 targetVelocity = desired.LengthSquared() > 0.000001f ? desired.Normalized() * maximumSpeed : Vector2.Zero;
            _velocities[index] = _velocities[index].MoveToward(targetVelocity, maximumSpeed * BattleConfig.UnitTurnRate * delta);
            _positions[index] = _kinds[index] == UnitDragon
                ? MoveFlying(position, _velocities[index] * delta)
                : MoveGround(position, _velocities[index] * delta);
            if (_profilingEnabled) _profileSeparationUsec += Usec(separationStart);
        }
        _decisionCursor = (_decisionCursor + 1) % BattleConfig.DecisionGroupCount;
        eventStart = _profilingEnabled ? Stopwatch.GetTimestamp() : 0;
        RemoveDeadUnits();
        if (_profilingEnabled) _profileEventUsec += Usec(eventStart);
        _territoryTimer -= delta;
        if (_territoryTimer <= 0.000001f)
        {
            long territoryStart = _profilingEnabled ? Stopwatch.GetTimestamp() : 0;
            RecalculateTerritory(true, false);
            if (_profilingEnabled) _profileTerritoryUsec += Usec(territoryStart);
        }
        CheckTerminalState();
        if (_profilingEnabled)
        {
            long elapsed = Usec(tickStart);
            _profileTickUsec += elapsed;
            _profileWorstTickUsec = Math.Max(_profileWorstTickUsec, elapsed);
            _profileTickCount++;
        }
    }

    private void ApplyIncome(float delta)
    {
        _allyIncomeRemainder += delta * BattleConfig.PassiveIncomePerSecond;
        _enemyIncomeRemainder += delta * BattleConfig.PassiveIncomePerSecond;
        int allyIncome = Mathf.FloorToInt(_allyIncomeRemainder + 0.000001f);
        int enemyIncome = Mathf.FloorToInt(_enemyIncomeRemainder + 0.000001f);
        if (allyIncome > 0) { _allyGold += allyIncome; _allyIncomeRemainder -= allyIncome; }
        if (enemyIncome > 0) { _enemyGold += enemyIncome; _enemyIncomeRemainder -= enemyIncome; }
    }

    private void UpdateEnemyAi(float delta)
    {
        _enemyBuildTimer -= delta;
        if (_enemyBuildTimer > 0f || CountSpawners(TeamEnemy) >= BattleConfig.EnemyMaxSpawners)
            return;
        _enemyBuildTimer += BattleConfig.EnemyBuildInterval;
        int unitKind = _enemyNextUnitKind;
        int cost = SpawnerCost(unitKind);
        if (_enemyGold < cost) return;
        for (int offset = 0; offset < BattleConfig.GridColumns; offset++)
        {
            int column = (_enemyBuildCursor + offset) % BattleConfig.GridColumns;
            int frontline = 0;
            for (int row = 0; row < BattleConfig.GridRows; row++)
                if (_ownership[Index(new Vector2I(column, row))] == TeamEnemy)
                    frontline = row;
            for (int row = Math.Min(frontline, BattleConfig.GridRows - 2); row > 0; row--)
            {
                var cell = new Vector2I(column, row);
                int buildKind = unitKind == UnitRanged ? BuildRangedSpawner : unitKind == UnitSiege ? BuildSiegeSpawner : BuildMeleeSpawner;
                if (!TryBuild(TeamEnemy, cell, buildKind)) continue;
                _enemyBuildCursor = (column + 3) % BattleConfig.GridColumns;
                _enemyNextUnitKind = unitKind == UnitMelee ? UnitRanged : unitKind == UnitRanged ? UnitSiege : UnitMelee;
                return;
            }
        }
    }

    private void UpdateSpawners(float delta)
    {
        for (int index = 0; index < _buildingCount; index++)
        {
            ref Building building = ref _buildings[index];
            if (building.Destroyed || (building.Kind != BuildingSpawner && building.Kind != BuildingDragonLair))
                continue;
            building.SpawnTimer -= delta;
            if (building.SpawnTimer > 0f) continue;
            float interval = building.Kind == BuildingDragonLair ? BattleConfig.DragonProductionInterval
                : building.UnitKind == UnitSiege ? BattleConfig.SiegeProductionInterval
                : BattleConfig.SpawnerProductionInterval;
            building.SpawnTimer += interval;
            Vector2 position = FindSpawnPosition(building.Cell, building.Team, building.UnitKind == UnitDragon);
            if (position.X < 0f) { building.SpawnTimer = 0.5f; continue; }
            int unitId = SpawnUnit(building.Team, position, building.UnitKind);
            if (unitId != 0)
                QueueStructural("unit_produced", building.Team, unitId, building.Cell, building.Kind, building.UnitKind);
        }
    }

    private void UpdateStaticDefenses(float delta)
    {
        for (int buildingIndex = 0; buildingIndex < _buildingCount; buildingIndex++)
        {
            ref Building building = ref _buildings[buildingIndex];
            if (building.Destroyed || (building.Kind != BuildingHq && building.Kind != BuildingDefenseTower))
                continue;
            building.AttackCooldown = Mathf.Max(0f, building.AttackCooldown - delta);
            if (building.AttackCooldown > 0f) continue;
            Vector2 origin = new Vector2(building.Cell.X + 0.5f, building.Cell.Y + 0.5f);
            float range = building.Kind == BuildingHq ? BattleConfig.HqRange : BattleConfig.DefenseTowerRange;
            int target = NearestHostileUnitIndex(building.Team, origin, range, true);
            if (target < 0) continue;
            building.AttackCooldown = building.Kind == BuildingHq ? BattleConfig.HqAttackInterval : BattleConfig.DefenseTowerAttackInterval;
            float damage = building.Kind == BuildingHq ? BattleConfig.HqDamage : BattleConfig.DefenseTowerDamage;
            float multiplier = ElevationDamageMultiplier(origin, _positions[target]);
            _hp[target] -= damage * multiplier;
            _lastAttackerTeams[target] = building.Team;
            QueueShot(building.Kind == BuildingHq ? ShotHq : ShotTower, building.Team, origin, _positions[target]);
            QueueHit(target, multiplier > 1f);
        }
    }

    private void RebuildBuckets()
    {
        for (int i = 0; i < BattleConfig.CellCount; i++)
        {
            _enemyBuckets[i].Clear();
            _allyBuckets[i].Clear();
            _enemyDensity[i] = _allyDensity[i] = 0;
            _enemySiegeDensity[i] = _allySiegeDensity[i] = 0;
        }
        for (int index = 0; index < _unitCount; index++)
        {
            if (_hp[index] <= 0f) continue;
            int cellIndex = Index(CellAt(_positions[index]));
            List<int>[] buckets = _teams[index] == TeamEnemy ? _enemyBuckets : _allyBuckets;
            buckets[cellIndex].Add(index);
            if (_kinds[index] != UnitDragon)
            {
                if (_teams[index] == TeamEnemy) _enemyDensity[cellIndex]++;
                else _allyDensity[cellIndex]++;
            }
            Vector2 fallback = _teams[index] == TeamEnemy ? Vector2.Down : Vector2.Up;
            AddSiegeDensity(_teams[index], PredictedSiegePosition(index, fallback, BattleConfig.SiegeFlightSeconds), UnitRadius(_kinds[index]));
        }
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            if (!building.Destroyed)
                AddSiegeDensity(building.Team, new Vector2(building.Cell.X + 0.5f, building.Cell.Y + 0.5f), BattleConfig.BuildingTargetRadius);
        }
    }

    private void AddSiegeDensity(int team, Vector2 position, float targetRadius)
    {
        float influence = BattleConfig.SiegeBlastRadius + targetRadius;
        int radius = Mathf.CeilToInt(influence);
        Vector2I center = CellAt(position);
        int[] density = team == TeamEnemy ? _enemySiegeDensity : _allySiegeDensity;
        for (int row = Math.Max(0, center.Y - radius); row <= Math.Min(BattleConfig.GridRows - 1, center.Y + radius); row++)
            for (int col = Math.Max(0, center.X - radius); col <= Math.Min(BattleConfig.GridColumns - 1, center.X + radius); col++)
            {
                Vector2 point = new(col + 0.5f, row + 0.5f);
                if (point.DistanceTo(position) <= influence)
                    density[Index(new Vector2I(col, row))]++;
            }
    }

    private void RebuildFlowFields()
    {
        RebuildBuckets();
        RebuildFlowForTeam(TeamEnemy);
        RebuildFlowForTeam(TeamAlly);
        _congestionTimer = BattleConfig.CongestionRebuildInterval * 0.5f;
        _nextFlowTeam = TeamEnemy;
    }

    private void RebuildFlowForTeam(int team)
    {
        Array.Copy(_blocked, _flowBlocked, _blocked.Length);
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            if (!building.Destroyed && building.Kind != BuildingHq)
                _flowBlocked[Index(building.Cell)] = 1;
        }
        if (team == TeamEnemy)
            _enemyFlow.Rebuild(BuildingCell(_allyHqId), _flowBlocked, _enemyDensity, BattleConfig.CongestionCostWeight, _elevation, BattleConfig.UphillCost);
        else
            _allyFlow.Rebuild(BuildingCell(_enemyHqId), _flowBlocked, _allyDensity, BattleConfig.CongestionCostWeight, _elevation, BattleConfig.UphillCost);
    }

    private void RecalculateTerritory(bool emitChanges, bool refreshBuckets)
    {
        if (refreshBuckets) RebuildBuckets();
        byte[] previous = emitChanges ? (byte[])_ownership.Clone() : Array.Empty<byte>();
        Span<int> red = stackalloc int[BattleConfig.GridColumns];
        Span<int> blue = stackalloc int[BattleConfig.GridColumns];
        red.Fill(-1);
        blue.Fill(BattleConfig.GridRows);
        for (int bucket = 0; bucket < BattleConfig.CellCount; bucket++)
        {
            int col = bucket % BattleConfig.GridColumns;
            int row = bucket / BattleConfig.GridColumns;
            if (_enemyBuckets[bucket].Count > 0) red[col] = Math.Max(red[col], row);
            if (_allyBuckets[bucket].Count > 0) blue[col] = Math.Min(blue[col], row);
        }
        for (int i = 0; i < _buildingCount; i++)
        {
            Building building = _buildings[i];
            if (building.Destroyed) continue;
            if (building.Team == TeamEnemy) red[building.Cell.X] = Math.Max(red[building.Cell.X], building.Cell.Y);
            else blue[building.Cell.X] = Math.Min(blue[building.Cell.X], building.Cell.Y);
        }
        int allyCells = 0;
        bool changed = false;
        for (int col = 0; col < BattleConfig.GridColumns; col++)
        {
            bool hasRed = red[col] >= 0;
            bool hasBlue = blue[col] < BattleConfig.GridRows;
            float midpoint = (red[col] + blue[col]) * 0.5f;
            for (int row = 0; row < BattleConfig.GridRows; row++)
            {
                bool redClaims = hasRed && row <= red[col];
                bool blueClaims = hasBlue && row >= blue[col];
                int owner = TeamNone;
                if (redClaims && blueClaims) owner = row <= midpoint ? TeamEnemy : TeamAlly;
                else if (redClaims) owner = TeamEnemy;
                else if (blueClaims) owner = TeamAlly;
                int cellIndex = Index(new Vector2I(col, row));
                if (owner != TeamNone) _ownership[cellIndex] = (byte)owner;
                if (_ownership[cellIndex] == TeamAlly) allyCells++;
                if (emitChanges && previous[cellIndex] != _ownership[cellIndex])
                {
                    changed = true;
                    var e = new GDictionary { ["type"] = "territory_changed", ["cell"] = new Vector2I(col, row), ["team"] = (int)_ownership[cellIndex] };
                    _events.Add(e);
                }
            }
        }
        _allyOccupancy = allyCells / (float)BattleConfig.CellCount;
        _enemyOccupancy = 1f - _allyOccupancy;
        _territoryTimer = BattleConfig.TerritoryUpdateInterval;
        _territoryUpdateCount++;
        if (changed) _boardVersion++;
    }
}
