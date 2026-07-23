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
    public const float UnitMaxHp = 80f;
    public const float FixedDelta = 1f / 30f;

    public const int FortificationMinX = 3;
    public const int FortificationMaxX = 24;
    public const int FortificationTopY = 17;
    public const int FortificationBottomY = 18;
    public const int GateMinX = 13;
    public const int GateMaxX = 14;
    public const int BlockedCellCount = 40;
}
