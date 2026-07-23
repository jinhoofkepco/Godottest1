internal static class AgentBattleConfig
{
    public const int ArenaWidth = 28;
    public const int ArenaHeight = 36;
    public const int TeamSize = 30;
    public const int UnitCount = TeamSize * 2;

    public const int TeamBlue = 0;
    public const int TeamRed = 1;

    public const int ModeBaseline = 0;
    public const int ModeAgent = 1;
    public const int DefaultSeed = 230723;

    public const int ActionAdvance = 0;
    public const int ActionEngage = 1;
    public const int ActionFillGap = 2;
    public const int ActionFlankLeft = 3;
    public const int ActionFlankRight = 4;
    public const int ActionYield = 5;
    public const int ActionHold = 6;
    public const int ActionRetreat = 7;
    public const int ActionCount = 8;

    public const int RouteCenter = 0;
    public const int RouteLeft = 1;
    public const int RouteRight = 2;

    public const float UnitMaxHp = 80f;
    public const float FixedDelta = 1f / 30f;
    public const float DecisionInterval = 0.2f;
    public const int DecisionIntervalTicks = 6;
    public const int DecisionGroupCount = 5;
    public const float MoveSpeed = 2.15f;
    public const float UnitRadius = 0.27f;
    public const float SeparationDistance = UnitRadius * 2.08f;
    public const float PerceptionRange = 2.6f;
    public const int PerceptionCellRadius = 3;
    public const float ForwardBlockRange = 0.95f;
    public const float ActionHysteresis = 0.18f;
    public const int DefaultCommitTicks = 9;
    public const int FlankCommitTicks = 24;
    public const int YieldCommitTicks = 15;
    public const int ProgressSampleTicks = 15;
    public const float MinimumForwardProgressPerSample = 0.12f;
    public const float IdleThresholdSeconds = 2f;
    public const float YieldPredictionSeconds = 0.28f;
    public const float YieldSlowSpeedRatio = 0.3f;
    public const float ObjectiveMargin = 1.1f;
    public const float CandidateCollisionRange = 0.72f;
    public const int PositionCorrectionPasses = 2;
    public const float CombatDetectionRange = 4.5f;
    public const int CombatDetectionCellRadius = 5;
    public const float AttackReach = 0.18f;
    public const float AttackRange = UnitRadius * 2f + AttackReach;
    public const float AttackDamage = 8f;
    public const float AttackInterval = 0.68f;
    public const float AttackPulseSeconds = 0.14f;
    public const int MaxAttackersPerTarget = 3;
    public const float RetreatHpRatio = 0.24f;
    // Wounded units disperse into a rear reserve band instead of queuing at an exact edge point.
    public const float RetreatReserveDepth = 5f;
    public const int RecentDeathTicks = 75;
    public const float GapFillDetectionRange = 5.5f;
    public const float ReplacementRadius = 1.35f;
    public const float PurposefulHoldRange = 3.2f;
    public const int MaximumBattleTicks = 120 * 30;

    public const int FortificationMinX = 3;
    public const int FortificationMaxX = 24;
    public const int FortificationTopY = 17;
    public const int FortificationBottomY = 18;
    public const int GateMinX = 13;
    public const int GateMaxX = 14;
    public const int BlockedCellCount = 40;
}
