using Godot;
using System;

public partial class AgentBattleSimulation
{
    private const int RouteWaypointCapacity = 5;
    private const float RouteWaypointReach = 0.32f;

    private readonly Vector2[] _routeWaypointsBlue =
        new Vector2[AgentBattleConfig.RouteCount * RouteWaypointCapacity];
    private readonly Vector2[] _routeWaypointsRed =
        new Vector2[AgentBattleConfig.RouteCount * RouteWaypointCapacity];
    private readonly Vector2[] _routeNavigationWaypointsBlue =
        new Vector2[AgentBattleConfig.RouteCount * RouteWaypointCapacity];
    private readonly Vector2[] _routeNavigationWaypointsRed =
        new Vector2[AgentBattleConfig.RouteCount * RouteWaypointCapacity];
    private readonly int[] _routeWaypointCounts = new int[AgentBattleConfig.RouteCount];
    private readonly int[] _routeWaypointCursors = new int[AgentBattleConfig.UnitCount];

    private float _barrierTopY;
    private float _barrierBottomY;
    private bool _hasBarrier;

    private void BuildScenario(int scenario)
    {
        _blockedCellCount = 0;
        Array.Clear(_blockedCells);
        Array.Clear(_blockedMask);
        Array.Clear(_routeWaypointsBlue);
        Array.Clear(_routeWaypointsRed);
        Array.Clear(_routeNavigationWaypointsBlue);
        Array.Clear(_routeNavigationWaypointsRed);
        Array.Clear(_routeWaypointCounts);
        Array.Clear(_routeWaypointCursors);
        _hasBarrier = true;

        switch (scenario)
        {
            case AgentBattleConfig.ScenarioCornerTrap:
                BuildCornerTrap();
                break;
            case AgentBattleConfig.ScenarioRouteChoice:
                BuildRouteChoice();
                break;
            case AgentBattleConfig.ScenarioOpenControl:
                BuildOpenControlRoutes();
                break;
            default:
                BuildBottleneck();
                break;
        }
    }

    private void BuildBottleneck()
    {
        _barrierTopY = 17f;
        _barrierBottomY = 19f;
        for (int y = 17; y <= 18; y++)
        {
            for (int x = 3; x <= 24; x++)
            {
                if (x < 13 || x > 14)
                    BlockCell(x, y);
            }
        }
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(14f, 19.3f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(14f, 16.55f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(13.5f, 0.7f));
        AddOuterRouteWaypoints();
    }

    private void BuildCornerTrap()
    {
        _barrierTopY = 14f;
        _barrierBottomY = 22f;
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

        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(12.25f, 22.1f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(12.25f, 18.7f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(15.25f, 17f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(15.25f, 13.7f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(13.5f, 0.7f));
        AddOuterRouteWaypoints();
    }

    private void BuildRouteChoice()
    {
        _barrierTopY = 16f;
        _barrierBottomY = 20f;
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

        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(13.5f, 20.45f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(13.5f, 15.55f));
        AddRouteWaypoint(AgentBattleConfig.RouteCenter, new Vector2(13.5f, 0.7f));
        AddRouteWaypoint(AgentBattleConfig.RouteLeft, new Vector2(4.5f, 20.45f));
        AddRouteWaypoint(AgentBattleConfig.RouteLeft, new Vector2(4.5f, 15.55f));
        AddRouteWaypoint(AgentBattleConfig.RouteLeft, new Vector2(13.5f, 0.7f));
        AddRouteWaypoint(AgentBattleConfig.RouteRight, new Vector2(22.5f, 20.45f));
        AddRouteWaypoint(AgentBattleConfig.RouteRight, new Vector2(22.5f, 15.55f));
        AddRouteWaypoint(AgentBattleConfig.RouteRight, new Vector2(13.5f, 0.7f));
    }

    private void BlockCell(int x, int y)
    {
        int cell = y * AgentBattleConfig.ArenaWidth + x;
        if (_blockedMask[cell])
            return;
        _blockedMask[cell] = true;
        _blockedCells[_blockedCellCount++] = cell;
    }

    private void AddOuterRouteWaypoints()
    {
        AddRouteWaypoint(AgentBattleConfig.RouteLeft, new Vector2(1.45f, 19.45f));
        AddRouteWaypoint(AgentBattleConfig.RouteLeft, new Vector2(1.45f, 16.45f));
        AddRouteWaypoint(AgentBattleConfig.RouteLeft, new Vector2(13.5f, 0.7f));
        AddRouteWaypoint(AgentBattleConfig.RouteRight, new Vector2(26.55f, 19.45f));
        AddRouteWaypoint(AgentBattleConfig.RouteRight, new Vector2(26.55f, 16.45f));
        AddRouteWaypoint(AgentBattleConfig.RouteRight, new Vector2(13.5f, 0.7f));
    }

    private void BuildOpenControlRoutes()
    {
        _hasBarrier = false;
        _barrierTopY = AgentBattleConfig.ArenaHeight * 0.5f;
        _barrierBottomY = _barrierTopY;
        for (int route = 0; route < AgentBattleConfig.RouteCount; route++)
            AddRouteWaypoint(route, new Vector2(13.5f, 0.7f));
    }

    private void AddRouteWaypoint(int route, Vector2 blue)
    {
        int waypoint = _routeWaypointCounts[route]++;
        int offset = RouteWaypointOffset(route, waypoint);
        _routeWaypointsBlue[offset] = blue;
        _routeWaypointsRed[offset] = new Vector2(blue.X, AgentBattleConfig.ArenaHeight - blue.Y);
        _routeNavigationWaypointsBlue[offset] = ProjectToOpenTerrain(_routeWaypointsBlue[offset]);
        _routeNavigationWaypointsRed[offset] = ProjectToOpenTerrain(_routeWaypointsRed[offset]);
    }

    private Vector2 ProjectToOpenTerrain(Vector2 waypoint)
    {
        if (IsTerrainOpen(waypoint))
            return waypoint;

        Vector2 best = waypoint;
        float bestDistanceSquared = float.MaxValue;
        for (int y = 0; y < AgentBattleConfig.ArenaHeight; y++)
        {
            for (int x = 0; x < AgentBattleConfig.ArenaWidth; x++)
            {
                Vector2 candidate = new(x + 0.5f, y + 0.5f);
                if (!IsTerrainOpen(candidate))
                    continue;
                float distanceSquared = waypoint.DistanceSquaredTo(candidate);
                if (distanceSquared >= bestDistanceSquared)
                    continue;
                bestDistanceSquared = distanceSquared;
                best = candidate;
            }
        }
        return best;
    }

    private bool IsApproachingScenarioBarrier(int index)
    {
        if (!_hasBarrier || HasPassedScenarioBarrier(index))
            return false;
        bool onApproachSide = _teams[index] == AgentBattleConfig.TeamBlue
            ? _positions[index].Y >= _barrierBottomY
            : _positions[index].Y <= _barrierTopY;
        if (!onApproachSide)
            return false;
        float centerY = (_barrierTopY + _barrierBottomY) * 0.5f;
        return MathF.Abs(_positions[index].Y - centerY) < 8.5f;
    }

    private bool HasPassedScenarioBarrier(int index)
    {
        if (!_hasBarrier)
            return true;
        return _teams[index] == AgentBattleConfig.TeamBlue
            ? _positions[index].Y <= _barrierTopY - 0.35f
            : _positions[index].Y >= _barrierBottomY + 0.35f;
    }

    private bool HasCompletedRoutePassage(int index) =>
        !_hasBarrier || HasPassedScenarioBarrier(index);

    private float RoutePassageX(int route)
    {
        int safeRoute = Math.Clamp(route, 0, AgentBattleConfig.RouteCount - 1);
        return _routeWaypointsBlue[RouteWaypointOffset(safeRoute, 0)].X;
    }

    private void PrepareRetreatRoute(int index)
    {
        int bestRoute = AgentBattleConfig.RouteCenter;
        float bestDistance = MathF.Abs(_positions[index].X - RoutePassageX(bestRoute));
        for (int route = 1; route < AgentBattleConfig.RouteCount; route++)
        {
            float distance = MathF.Abs(_positions[index].X - RoutePassageX(route));
            if (distance >= bestDistance)
                continue;
            bestDistance = distance;
            bestRoute = route;
        }
        _routeIntents[index] = bestRoute;
        _routeWaypointCursors[index] = ReverseWaypointCursorForPosition(index, bestRoute);
    }

    private int ReverseWaypointCursorForPosition(int index, int route)
    {
        float homeward = _teams[index] == AgentBattleConfig.TeamBlue ? 1f : -1f;
        int count = _routeWaypointCounts[route];
        int cursor = 0;
        while (cursor < count)
        {
            Vector2 waypoint = NavigationRouteWaypoint(index, route, cursor, true);
            if ((waypoint.Y - _positions[index].Y) * homeward >= 0f)
                break;
            cursor++;
        }
        return cursor;
    }

    private void AdvanceRouteWaypointCursor(int index, bool reverse)
    {
        int route = Math.Clamp(_routeIntents[index], 0, AgentBattleConfig.RouteCount - 1);
        int count = _routeWaypointCounts[route];
        int cursor = _routeWaypointCursors[index];
        float reachSquared = RouteWaypointReach * RouteWaypointReach;
        while (cursor < count)
        {
            Vector2 waypoint = NavigationRouteWaypoint(index, route, cursor, reverse);
            if (_positions[index].DistanceSquaredTo(waypoint) > reachSquared)
                break;
            cursor++;
        }
        _routeWaypointCursors[index] = cursor;
    }

    private Vector2 RouteWaypoint(int index, int route, int waypoint, bool reverse)
    {
        int offset = RouteWaypointOffset(route, waypoint);
        bool useBlue = reverse
            ? _teams[index] == AgentBattleConfig.TeamRed
            : _teams[index] == AgentBattleConfig.TeamBlue;
        return useBlue ? _routeWaypointsBlue[offset] : _routeWaypointsRed[offset];
    }

    private Vector2 NavigationRouteWaypoint(int index, int route, int waypoint, bool reverse)
    {
        int offset = RouteWaypointOffset(route, waypoint);
        bool useBlue = reverse
            ? _teams[index] == AgentBattleConfig.TeamRed
            : _teams[index] == AgentBattleConfig.TeamBlue;
        return useBlue
            ? _routeNavigationWaypointsBlue[offset]
            : _routeNavigationWaypointsRed[offset];
    }

    private int ClassifyPhysicalPassage(float crossingX)
    {
        int bestRoute = AgentBattleConfig.RouteCenter;
        float bestDistance = float.MaxValue;
        for (int route = 0; route < AgentBattleConfig.RouteCount; route++)
        {
            int exitWaypoint = Math.Max(0, _routeWaypointCounts[route] - 2);
            float exitX = _routeWaypointsBlue[RouteWaypointOffset(route, exitWaypoint)].X;
            float distance = MathF.Abs(crossingX - exitX);
            if (distance >= bestDistance)
                continue;
            bestDistance = distance;
            bestRoute = route;
        }
        return bestRoute;
    }

    private static int RouteWaypointOffset(int route, int waypoint) =>
        route * RouteWaypointCapacity + waypoint;

    private static string ScenarioName(int scenario) => scenario switch
    {
        AgentBattleConfig.ScenarioCornerTrap => "CORNER_TRAP",
        AgentBattleConfig.ScenarioRouteChoice => "ROUTE_CHOICE",
        AgentBattleConfig.ScenarioOpenControl => "OPEN_CONTROL",
        _ => "BOTTLENECK",
    };
}
