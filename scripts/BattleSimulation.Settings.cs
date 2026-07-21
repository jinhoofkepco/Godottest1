using Godot;
using GArray = Godot.Collections.Array;
using GDictionary = Godot.Collections.Dictionary;
using System;

public partial class BattleSimulation
{
    private static readonly string[] SettingGroupNames = { "melee", "ranged", "dragon", "siege" };

    public GArray GetMatchSettingsSchema()
    {
        BattleMatchSettings defaults = BattleMatchSettings.CreateDefault();
        var schema = new GArray();
        for (int kind = 0; kind < SettingGroupNames.Length; kind++)
        {
            string group = SettingGroupNames[kind];
            BattleMatchSettings.UnitTuning unit = defaults.Units[kind];
            AddSchemaField(schema, group, "max_hp", "MAX HP", 1f, 5000f, 1f, unit.MaxHp);
            AddSchemaField(schema, group, "damage", "DAMAGE", 0.1f, 1000f, 0.1f, unit.Damage);
            AddSchemaField(schema, group, "attack_interval", "ATTACK SECONDS", 0.05f, 30f, 0.05f, unit.AttackInterval);
            AddSchemaField(schema, group, "attack_range", "ATTACK RANGE", 0.1f, 64f, 0.1f, unit.AttackRange);
            AddSchemaField(schema, group, "detect_range", "DETECT RANGE", 0.1f, 96f, 0.1f, unit.DetectRange);
            AddSchemaField(schema, group, "speed", "MOVE SPEED", 0.05f, 10f, 0.05f, unit.Speed);
            AddSchemaField(schema, group, "radius", "UNIT RADIUS", 0.05f, 2f, 0.01f, unit.Radius);
            AddSchemaField(schema, group, "production_interval", "PRODUCTION SECONDS", 0.1f, 600f, 0.1f, unit.ProductionInterval);
            AddSchemaField(schema, group, "production_batch", "PRODUCTION BATCH", 1f, 50f, 1f, unit.ProductionBatch, true);
            AddSchemaField(schema, group, "spawner_cost", "BUILD COST", 1f, 10000f, 1f, unit.SpawnerCost, true);
            for (int target = 0; target < SettingGroupNames.Length; target++)
                AddSchemaField(schema, group, $"damage_vs.{SettingGroupNames[target]}", $"DAMAGE VS {SettingGroupNames[target].ToUpperInvariant()}", 0f, 10f, 0.05f, unit.DamageVs[target]);
        }
        AddSchemaField(schema, "melee", "shield_enter_range", "SHIELD ENTER RANGE", 0.1f, 32f, 0.1f, defaults.ShieldEnterRange);
        AddSchemaField(schema, "melee", "shield_release_range", "SHIELD RELEASE RANGE", 0.1f, 32f, 0.1f, defaults.ShieldReleaseRange);
        AddSchemaField(schema, "melee", "shield_speed_multiplier", "SHIELD SPEED MULTIPLIER", 0.01f, 2f, 0.01f, defaults.ShieldSpeedMultiplier);
        AddSchemaField(schema, "melee", "shield_ranged_damage_taken_multiplier", "RANGED DAMAGE TAKEN", 0f, 2f, 0.01f, defaults.ShieldRangedDamageTakenMultiplier);
        AddSchemaField(schema, "ranged", "standoff_distance", "STANDOFF DISTANCE", 0.1f, 64f, 0.1f, defaults.RangedStandoffDistance);
        AddSchemaField(schema, "ranged", "high_ground_bonus", "HIGH GROUND RANGE BONUS", 0f, 16f, 0.1f, defaults.RangedHighGroundBonus);
        AddSchemaField(schema, "ranged", "preferred_firing_range_ratio", "PREFERRED RANGE RATIO", 0.1f, 1f, 0.01f, defaults.PreferredFiringRangeRatio);
        AddSchemaField(schema, "siege", "min_range", "MINIMUM RANGE", 0f, 64f, 0.1f, defaults.SiegeMinRange);
        AddSchemaField(schema, "siege", "blast_radius", "BLAST RADIUS", 0.1f, 32f, 0.1f, defaults.SiegeBlastRadius);
        AddSchemaField(schema, "siege", "edge_damage_multiplier", "EDGE DAMAGE MULTIPLIER", 0f, 1f, 0.01f, defaults.SiegeEdgeDamageMultiplier);
        AddSchemaField(schema, "siege", "flight_seconds", "PROJECTILE FLIGHT SECONDS", 0.05f, 10f, 0.05f, defaults.SiegeFlightSeconds);
        return schema;
    }

    public GDictionary GetMatchSettings() => SettingsToDictionary(_settings);

    public GDictionary ConfigureAndReset(GDictionary values)
    {
        var errors = new GArray();
        BattleMatchSettings candidate = _settings.Clone();
        for (int kind = 0; kind < SettingGroupNames.Length; kind++)
        {
            string name = SettingGroupNames[kind];
            if (!TryDictionary(values, name, errors, out GDictionary group))
                continue;
            ReadUnit(group, name, candidate.Units[kind], errors);
        }
        if (TryDictionary(values, "melee", errors, out GDictionary melee))
        {
            ReadFloat(melee, "shield_enter_range", "melee.shield_enter_range", errors, value => candidate.ShieldEnterRange = value);
            ReadFloat(melee, "shield_release_range", "melee.shield_release_range", errors, value => candidate.ShieldReleaseRange = value);
            ReadFloat(melee, "shield_speed_multiplier", "melee.shield_speed_multiplier", errors, value => candidate.ShieldSpeedMultiplier = value);
            ReadFloat(melee, "shield_ranged_damage_taken_multiplier", "melee.shield_ranged_damage_taken_multiplier", errors, value => candidate.ShieldRangedDamageTakenMultiplier = value);
        }
        if (TryDictionary(values, "ranged", errors, out GDictionary ranged))
        {
            ReadFloat(ranged, "standoff_distance", "ranged.standoff_distance", errors, value => candidate.RangedStandoffDistance = value);
            ReadFloat(ranged, "high_ground_bonus", "ranged.high_ground_bonus", errors, value => candidate.RangedHighGroundBonus = value);
            ReadFloat(ranged, "preferred_firing_range_ratio", "ranged.preferred_firing_range_ratio", errors, value => candidate.PreferredFiringRangeRatio = value);
        }
        if (TryDictionary(values, "siege", errors, out GDictionary siege))
        {
            ReadFloat(siege, "min_range", "siege.min_range", errors, value => candidate.SiegeMinRange = value);
            ReadFloat(siege, "blast_radius", "siege.blast_radius", errors, value => candidate.SiegeBlastRadius = value);
            ReadFloat(siege, "edge_damage_multiplier", "siege.edge_damage_multiplier", errors, value => candidate.SiegeEdgeDamageMultiplier = value);
            ReadFloat(siege, "flight_seconds", "siege.flight_seconds", errors, value => candidate.SiegeFlightSeconds = value);
        }
        ValidateSettings(candidate, errors);
        if (errors.Count > 0)
            return new GDictionary { ["ok"] = false, ["errors"] = errors, ["normalized"] = SettingsToDictionary(_settings) };

        _settings = candidate;
        Reset();
        GDictionary normalized = SettingsToDictionary(_settings);
        return new GDictionary { ["ok"] = true, ["errors"] = errors, ["normalized"] = normalized };
    }

    private static void ReadUnit(GDictionary group, string name, BattleMatchSettings.UnitTuning unit, GArray errors)
    {
        ReadFloat(group, "max_hp", $"{name}.max_hp", errors, value => unit.MaxHp = value);
        ReadFloat(group, "damage", $"{name}.damage", errors, value => unit.Damage = value);
        ReadFloat(group, "attack_interval", $"{name}.attack_interval", errors, value => unit.AttackInterval = value);
        ReadFloat(group, "attack_range", $"{name}.attack_range", errors, value => unit.AttackRange = value);
        ReadFloat(group, "detect_range", $"{name}.detect_range", errors, value => unit.DetectRange = value);
        ReadFloat(group, "speed", $"{name}.speed", errors, value => unit.Speed = value);
        ReadFloat(group, "radius", $"{name}.radius", errors, value => unit.Radius = value);
        ReadFloat(group, "production_interval", $"{name}.production_interval", errors, value => unit.ProductionInterval = value);
        ReadInteger(group, "production_batch", $"{name}.production_batch", errors, value => unit.ProductionBatch = value);
        ReadInteger(group, "spawner_cost", $"{name}.spawner_cost", errors, value => unit.SpawnerCost = value);
        if (!TryDictionary(group, "damage_vs", errors, out GDictionary damageVs, name))
            return;
        for (int target = 0; target < SettingGroupNames.Length; target++)
        {
            int captured = target;
            string targetName = SettingGroupNames[target];
            ReadFloat(damageVs, targetName, $"{name}.damage_vs.{targetName}", errors, value => unit.DamageVs[captured] = value);
        }
    }

    private static void ValidateSettings(BattleMatchSettings settings, GArray errors)
    {
        for (int kind = 0; kind < SettingGroupNames.Length; kind++)
        {
            string name = SettingGroupNames[kind];
            BattleMatchSettings.UnitTuning unit = settings.Units[kind];
            ValidateRange(unit.MaxHp, 0.001f, 5000f, $"{name}.max_hp", errors);
            ValidateRange(unit.Damage, 0.001f, 1000f, $"{name}.damage", errors);
            ValidateRange(unit.AttackInterval, 0.01f, 30f, $"{name}.attack_interval", errors);
            ValidateRange(unit.AttackRange, 0.01f, 64f, $"{name}.attack_range", errors);
            ValidateRange(unit.DetectRange, 0.01f, 96f, $"{name}.detect_range", errors);
            ValidateRange(unit.Speed, 0.01f, 10f, $"{name}.speed", errors);
            ValidateRange(unit.Radius, 0.05f, 2f, $"{name}.radius", errors);
            ValidateRange(unit.ProductionInterval, 0.01f, 600f, $"{name}.production_interval", errors);
            ValidateRange(unit.ProductionBatch, 1, 50, $"{name}.production_batch", errors);
            ValidateRange(unit.SpawnerCost, 1, 10000, $"{name}.spawner_cost", errors);
            if (unit.DetectRange < unit.AttackRange)
                errors.Add($"{name}.detect_range must be at least attack_range");
            for (int target = 0; target < unit.DamageVs.Length; target++)
                ValidateRange(unit.DamageVs[target], 0f, 10f, $"{name}.damage_vs.{SettingGroupNames[target]}", errors);
        }
        ValidateRange(settings.ShieldEnterRange, 0.01f, 32f, "melee.shield_enter_range", errors);
        ValidateRange(settings.ShieldReleaseRange, 0.01f, 32f, "melee.shield_release_range", errors);
        ValidateRange(settings.ShieldSpeedMultiplier, 0.01f, 2f, "melee.shield_speed_multiplier", errors);
        ValidateRange(settings.ShieldRangedDamageTakenMultiplier, 0f, 2f, "melee.shield_ranged_damage_taken_multiplier", errors);
        if (settings.ShieldReleaseRange < settings.ShieldEnterRange)
            errors.Add("melee.shield_release_range must be at least shield_enter_range");
        ValidateRange(settings.RangedStandoffDistance, 0.01f, 64f, "ranged.standoff_distance", errors);
        ValidateRange(settings.RangedHighGroundBonus, 0f, 16f, "ranged.high_ground_bonus", errors);
        ValidateRange(settings.PreferredFiringRangeRatio, 0.1f, 1f, "ranged.preferred_firing_range_ratio", errors);
        if (settings.RangedStandoffDistance >= settings.Units[UnitRanged].AttackRange)
            errors.Add("ranged.standoff_distance must be less than attack_range");
        ValidateRange(settings.SiegeMinRange, 0f, 64f, "siege.min_range", errors);
        ValidateRange(settings.SiegeBlastRadius, 0.01f, 32f, "siege.blast_radius", errors);
        ValidateRange(settings.SiegeEdgeDamageMultiplier, 0f, 1f, "siege.edge_damage_multiplier", errors);
        ValidateRange(settings.SiegeFlightSeconds, 0.01f, 10f, "siege.flight_seconds", errors);
        if (settings.SiegeMinRange >= settings.Units[UnitSiege].AttackRange)
            errors.Add("siege.min_range must be less than attack_range");
    }

    private static GDictionary SettingsToDictionary(BattleMatchSettings settings)
    {
        var result = new GDictionary();
        for (int kind = 0; kind < SettingGroupNames.Length; kind++)
        {
            BattleMatchSettings.UnitTuning unit = settings.Units[kind];
            var damageVs = new GDictionary();
            for (int target = 0; target < SettingGroupNames.Length; target++)
                damageVs[SettingGroupNames[target]] = unit.DamageVs[target];
            result[SettingGroupNames[kind]] = new GDictionary
            {
                ["max_hp"] = unit.MaxHp,
                ["damage"] = unit.Damage,
                ["attack_interval"] = unit.AttackInterval,
                ["attack_range"] = unit.AttackRange,
                ["detect_range"] = unit.DetectRange,
                ["speed"] = unit.Speed,
                ["radius"] = unit.Radius,
                ["production_interval"] = unit.ProductionInterval,
                ["production_batch"] = unit.ProductionBatch,
                ["spawner_cost"] = unit.SpawnerCost,
                ["damage_vs"] = damageVs,
            };
        }
        GDictionary melee = result["melee"].AsGodotDictionary();
        melee["shield_enter_range"] = settings.ShieldEnterRange;
        melee["shield_release_range"] = settings.ShieldReleaseRange;
        melee["shield_speed_multiplier"] = settings.ShieldSpeedMultiplier;
        melee["shield_ranged_damage_taken_multiplier"] = settings.ShieldRangedDamageTakenMultiplier;
        GDictionary ranged = result["ranged"].AsGodotDictionary();
        ranged["standoff_distance"] = settings.RangedStandoffDistance;
        ranged["high_ground_bonus"] = settings.RangedHighGroundBonus;
        ranged["preferred_firing_range_ratio"] = settings.PreferredFiringRangeRatio;
        GDictionary siege = result["siege"].AsGodotDictionary();
        siege["min_range"] = settings.SiegeMinRange;
        siege["blast_radius"] = settings.SiegeBlastRadius;
        siege["edge_damage_multiplier"] = settings.SiegeEdgeDamageMultiplier;
        siege["flight_seconds"] = settings.SiegeFlightSeconds;
        return result;
    }

    private static void AddSchemaField(GArray schema, string group, string key, string label, float minimum, float maximum, float step, float defaultValue, bool integer = false) =>
        schema.Add(new GDictionary
        {
            ["group"] = group,
            ["key"] = key,
            ["label"] = label,
            ["minimum"] = minimum,
            ["maximum"] = maximum,
            ["step"] = step,
            ["default"] = integer ? Mathf.RoundToInt(defaultValue) : defaultValue,
            ["integer"] = integer,
        });

    private static bool TryDictionary(GDictionary source, string key, GArray errors, out GDictionary result, string prefix = "")
    {
        string path = prefix.Length == 0 ? key : $"{prefix}.{key}";
        if (!source.TryGetValue(key, out Variant value) || value.VariantType != Variant.Type.Dictionary)
        {
            errors.Add($"{path} is required and must be an object");
            result = new GDictionary();
            return false;
        }
        result = value.AsGodotDictionary();
        return true;
    }

    private static void ReadFloat(GDictionary source, string key, string path, GArray errors, Action<float> assign)
    {
        if (!source.TryGetValue(key, out Variant value) || (value.VariantType != Variant.Type.Float && value.VariantType != Variant.Type.Int))
        {
            errors.Add($"{path} is required and must be numeric");
            return;
        }
        float number = value.AsSingle();
        if (!float.IsFinite(number))
        {
            errors.Add($"{path} must be finite");
            return;
        }
        assign(number);
    }

    private static void ReadInteger(GDictionary source, string key, string path, GArray errors, Action<int> assign)
    {
        if (!source.TryGetValue(key, out Variant value) || (value.VariantType != Variant.Type.Float && value.VariantType != Variant.Type.Int))
        {
            errors.Add($"{path} is required and must be an integer");
            return;
        }
        double number = value.AsDouble();
        if (!double.IsFinite(number) || Math.Abs(number - Math.Round(number)) > 0.000001 || number < int.MinValue || number > int.MaxValue)
        {
            errors.Add($"{path} must be a finite integer");
            return;
        }
        assign((int)Math.Round(number));
    }

    private static void ValidateRange(float value, float minimum, float maximum, string path, GArray errors)
    {
        if (!float.IsFinite(value) || value < minimum || value > maximum)
            errors.Add($"{path} must be between {minimum} and {maximum}");
    }

    private static void ValidateRange(int value, int minimum, int maximum, string path, GArray errors)
    {
        if (value < minimum || value > maximum)
            errors.Add($"{path} must be between {minimum} and {maximum}");
    }
}
