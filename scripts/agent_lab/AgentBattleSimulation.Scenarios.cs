using System;

public partial class AgentBattleSimulation
{
    private void BuildScenario(int scenario)
    {
        _blockedCellCount = 0;
        Array.Clear(_blockedCells);
        Array.Clear(_blockedMask);

        switch (scenario)
        {
            case AgentBattleConfig.ScenarioCornerTrap:
                BuildCornerTrap();
                break;
            case AgentBattleConfig.ScenarioRouteChoice:
                BuildRouteChoice();
                break;
            case AgentBattleConfig.ScenarioOpenControl:
                break;
            default:
                BuildBottleneck();
                break;
        }
    }

    private void BuildBottleneck()
    {
        for (int y = 17; y <= 18; y++)
        {
            for (int x = 3; x <= 24; x++)
            {
                if (x < 13 || x > 14)
                    BlockCell(x, y);
            }
        }
    }

    private void BuildCornerTrap()
    {
        for (int y = 17; y <= 18; y++)
        {
            for (int x = 3; x <= 24; x++)
            {
                if (x < 11 || x > 16)
                    BlockCell(x, y);
            }
        }

        for (int y = 14; y <= 16; y++)
        {
            for (int x = 11; x <= 13; x++)
                BlockCell(x, y);
        }

        for (int y = 19; y <= 21; y++)
        {
            for (int x = 14; x <= 16; x++)
                BlockCell(x, y);
        }
    }

    private void BuildRouteChoice()
    {
        for (int y = 16; y <= 19; y++)
        {
            for (int x = 0; x < AgentBattleConfig.ArenaWidth; x++)
            {
                bool isGate = (x >= 3 && x <= 6)
                    || (x >= 13 && x <= 14)
                    || (x >= 21 && x <= 24);
                if (!isGate)
                    BlockCell(x, y);
            }
        }
    }

    private void BlockCell(int x, int y)
    {
        int cell = y * AgentBattleConfig.ArenaWidth + x;
        if (_blockedMask[cell])
            return;
        _blockedMask[cell] = true;
        _blockedCells[_blockedCellCount++] = cell;
    }

    private static string ScenarioName(int scenario) => scenario switch
    {
        AgentBattleConfig.ScenarioCornerTrap => "CORNER_TRAP",
        AgentBattleConfig.ScenarioRouteChoice => "ROUTE_CHOICE",
        AgentBattleConfig.ScenarioOpenControl => "OPEN_CONTROL",
        _ => "BOTTLENECK",
    };
}
