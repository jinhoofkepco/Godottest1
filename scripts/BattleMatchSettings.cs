using System;

internal sealed class BattleMatchSettings
{
    internal sealed class UnitTuning
    {
        public float MaxHp;
        public float Damage;
        public float AttackInterval;
        public float AttackRange;
        public float DetectRange;
        public float Speed;
        public float Radius;
        public float ProductionInterval;
        public int ProductionBatch;
        public int SpawnerCost;
        public readonly float[] DamageVs = new float[4];

        public UnitTuning Clone()
        {
            var copy = new UnitTuning
            {
                MaxHp = MaxHp,
                Damage = Damage,
                AttackInterval = AttackInterval,
                AttackRange = AttackRange,
                DetectRange = DetectRange,
                Speed = Speed,
                Radius = Radius,
                ProductionInterval = ProductionInterval,
                ProductionBatch = ProductionBatch,
                SpawnerCost = SpawnerCost,
            };
            Array.Copy(DamageVs, copy.DamageVs, DamageVs.Length);
            return copy;
        }
    }

    public readonly UnitTuning[] Units = new UnitTuning[4];
    public float ShieldEnterRange;
    public float ShieldReleaseRange;
    public float ShieldSpeedMultiplier;
    public float ShieldRangedDamageTakenMultiplier;
    public float RangedStandoffDistance;
    public float RangedHighGroundBonus;
    public float PreferredFiringRangeRatio;
    public float SiegeMinRange;
    public float SiegeBlastRadius;
    public float SiegeEdgeDamageMultiplier;
    public float SiegeFlightSeconds;

    public static BattleMatchSettings CreateDefault()
    {
        var settings = new BattleMatchSettings();
        settings.Units[BattleSimulation.UnitMelee] = Unit(
            BattleConfig.MeleeHp, BattleConfig.MeleeDamage, BattleConfig.MeleeAttackInterval,
            BattleConfig.MeleeRange, BattleConfig.UnitDetectRange, BattleConfig.MeleeSpeed,
            BattleConfig.MeleeRadius, BattleConfig.SpawnerProductionInterval,
            BattleConfig.MeleeProductionBatch, BattleConfig.MeleeSpawnerCost);
        settings.Units[BattleSimulation.UnitRanged] = Unit(
            BattleConfig.RangedHp, BattleConfig.RangedDamage, BattleConfig.RangedAttackInterval,
            BattleConfig.RangedRange, BattleConfig.RangedDetectRange, BattleConfig.RangedSpeed,
            BattleConfig.RangedRadius, BattleConfig.SpawnerProductionInterval,
            BattleConfig.RangedProductionBatch, BattleConfig.RangedSpawnerCost);
        settings.Units[BattleSimulation.UnitDragon] = Unit(
            BattleConfig.DragonHp, BattleConfig.DragonDamage, BattleConfig.DragonAttackInterval,
            BattleConfig.DragonRange, BattleConfig.DragonDetectRange, BattleConfig.DragonSpeed,
            BattleConfig.DragonRadius, BattleConfig.DragonProductionInterval,
            BattleConfig.DragonProductionBatch, BattleConfig.DragonLairCost);
        settings.Units[BattleSimulation.UnitSiege] = Unit(
            BattleConfig.SiegeHp, BattleConfig.SiegeDamage, BattleConfig.SiegeAttackInterval,
            BattleConfig.SiegeRange, BattleConfig.SiegeRange, BattleConfig.SiegeSpeed,
            BattleConfig.SiegeRadius, BattleConfig.SiegeProductionInterval,
            BattleConfig.SiegeProductionBatch, BattleConfig.SiegeSpawnerCost);

        for (int attacker = 0; attacker < settings.Units.Length; attacker++)
            Array.Fill(settings.Units[attacker].DamageVs, 1f);
        settings.Units[BattleSimulation.UnitRanged].DamageVs[BattleSimulation.UnitMelee] = BattleConfig.RangedVsMelee;
        settings.Units[BattleSimulation.UnitMelee].DamageVs[BattleSimulation.UnitSiege] = BattleConfig.MeleeVsSiege;
        settings.Units[BattleSimulation.UnitMelee].DamageVs[BattleSimulation.UnitRanged] = BattleConfig.MeleeVsRanged;
        settings.Units[BattleSimulation.UnitRanged].DamageVs[BattleSimulation.UnitSiege] = BattleConfig.RangedVsSiege;
        settings.Units[BattleSimulation.UnitRanged].DamageVs[BattleSimulation.UnitDragon] = BattleConfig.RangedVsDragon;
        settings.Units[BattleSimulation.UnitDragon].DamageVs[BattleSimulation.UnitRanged] = BattleConfig.DragonVsRanged;
        settings.Units[BattleSimulation.UnitDragon].DamageVs[BattleSimulation.UnitSiege] = BattleConfig.DragonVsSiege;
        settings.Units[BattleSimulation.UnitMelee].DamageVs[BattleSimulation.UnitDragon] = BattleConfig.MeleeVsDragon;
        settings.Units[BattleSimulation.UnitSiege].DamageVs[BattleSimulation.UnitMelee] = BattleConfig.SiegeVsMelee;

        settings.ShieldEnterRange = BattleConfig.ShieldEnterRange;
        settings.ShieldReleaseRange = BattleConfig.ShieldReleaseRange;
        settings.ShieldSpeedMultiplier = BattleConfig.ShieldSpeedMultiplier;
        settings.ShieldRangedDamageTakenMultiplier = BattleConfig.ShieldRangedDamageTakenMultiplier;
        settings.RangedStandoffDistance = BattleConfig.RangedStandoffDistance;
        settings.RangedHighGroundBonus = BattleConfig.RangedHighGroundRangeBonus;
        settings.PreferredFiringRangeRatio = BattleConfig.PreferredFiringRangeRatio;
        settings.SiegeMinRange = BattleConfig.SiegeMinRange;
        settings.SiegeBlastRadius = BattleConfig.SiegeBlastRadius;
        settings.SiegeEdgeDamageMultiplier = BattleConfig.SiegeEdgeDamageMultiplier;
        settings.SiegeFlightSeconds = BattleConfig.SiegeFlightSeconds;
        return settings;
    }

    public BattleMatchSettings Clone()
    {
        var copy = new BattleMatchSettings
        {
            ShieldEnterRange = ShieldEnterRange,
            ShieldReleaseRange = ShieldReleaseRange,
            ShieldSpeedMultiplier = ShieldSpeedMultiplier,
            ShieldRangedDamageTakenMultiplier = ShieldRangedDamageTakenMultiplier,
            RangedStandoffDistance = RangedStandoffDistance,
            RangedHighGroundBonus = RangedHighGroundBonus,
            PreferredFiringRangeRatio = PreferredFiringRangeRatio,
            SiegeMinRange = SiegeMinRange,
            SiegeBlastRadius = SiegeBlastRadius,
            SiegeEdgeDamageMultiplier = SiegeEdgeDamageMultiplier,
            SiegeFlightSeconds = SiegeFlightSeconds,
        };
        for (int kind = 0; kind < Units.Length; kind++)
            copy.Units[kind] = Units[kind].Clone();
        return copy;
    }

    private static UnitTuning Unit(float hp, float damage, float interval, float range, float detect,
        float speed, float radius, float production, int batch, int cost) => new()
    {
        MaxHp = hp,
        Damage = damage,
        AttackInterval = interval,
        AttackRange = range,
        DetectRange = detect,
        Speed = speed,
        Radius = radius,
        ProductionInterval = production,
        ProductionBatch = batch,
        SpawnerCost = cost,
    };
}
