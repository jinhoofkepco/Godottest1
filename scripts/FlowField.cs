using Godot;
using System;
using System.Collections.Generic;

internal sealed class FlowField
{
    private static readonly Vector2I[] Directions =
    {
        new(-1, 0), new(1, 0), new(0, -1), new(0, 1),
        new(-1, -1), new(1, -1), new(-1, 1), new(1, 1),
    };
    private const float DiagonalCost = 1.41421356f;
    private readonly int _width;
    private readonly int _height;
    public readonly float[] Costs;
    public readonly Vector2[] Flow;
    public readonly int[] NextCells;
    public readonly byte[] NearObstacles;
    private ulong _obstacleSignature = ulong.MaxValue;

    public FlowField(int width, int height)
    {
        _width = Math.Max(1, width);
        _height = Math.Max(1, height);
        Costs = new float[_width * _height];
        Flow = new Vector2[_width * _height];
        NextCells = new int[_width * _height];
        NearObstacles = new byte[_width * _height];
    }

    public void Rebuild(Vector2I goal, byte[] blocked, int[] density, float congestionWeight, byte[] elevation, float uphillCost)
    {
        Array.Fill(Costs, float.PositiveInfinity);
        Array.Clear(Flow);
        Array.Fill(NextCells, -1);
        if (!Valid(goal))
            return;
        int goalIndex = Index(goal);
        Costs[goalIndex] = 0f;
        var heap = new PriorityQueue<int, float>();
        heap.Enqueue(goalIndex, 0f);
        while (heap.TryDequeue(out int currentIndex, out float queuedCost))
        {
            if (queuedCost > Costs[currentIndex] + 0.0001f)
                continue;
            var current = new Vector2I(currentIndex % _width, currentIndex / _width);
            int currentElevation = elevation[currentIndex];
            foreach (Vector2I offset in Directions)
            {
                Vector2I neighbor = current + offset;
                if (!Valid(neighbor)) continue;
                int neighborIndex = Index(neighbor);
                if (!GroundNavigation.CanTransitionValid(neighbor, current, blocked, elevation, _width)) continue;
                int neighborElevation = elevation[neighborIndex];
                float step = offset.X != 0 && offset.Y != 0 ? DiagonalCost : 1f;
                if (currentElevation > neighborElevation)
                    step += Math.Max(0f, uphillCost);
                step += density[neighborIndex] * Math.Max(0f, congestionWeight);
                float candidate = queuedCost + step;
                if (candidate + 0.0001f >= Costs[neighborIndex])
                    continue;
                Costs[neighborIndex] = candidate;
                heap.Enqueue(neighborIndex, candidate);
            }
        }
        BuildDirections(blocked, goalIndex, elevation, uphillCost);
        UpdateObstacleProximity(blocked, elevation);
    }

    public float CostAt(Vector2I cell) => Valid(cell) ? Costs[Index(cell)] : float.PositiveInfinity;
    public Vector2 DirectionAt(Vector2I cell) => Valid(cell) ? Flow[Index(cell)] : Vector2.Zero;
    public bool NearObstacleAt(Vector2I cell) => !Valid(cell) || NearObstacles[Index(cell)] != 0;
    public Vector2I NextCellAt(Vector2I cell)
    {
        if (!Valid(cell)) return new Vector2I(-1, -1);
        int next = NextCells[Index(cell)];
        return next >= 0 ? new Vector2I(next % _width, next / _width) : new Vector2I(-1, -1);
    }

    public Vector2 PortalDirectionAt(Vector2 position)
    {
        var cell = new Vector2I(Math.Clamp(Mathf.FloorToInt(position.X), 0, _width - 1), Math.Clamp(Mathf.FloorToInt(position.Y), 0, _height - 1));
        Vector2I next = NextCellAt(cell);
        if (!Valid(next)) return Vector2.Zero;
        Vector2 safeCenter = new(next.X + 0.5f, next.Y + 0.5f);
        return position.DirectionTo(safeCenter);
    }

    private void UpdateObstacleProximity(byte[] blocked, byte[] elevation)
    {
        ulong signature = 1469598103934665603UL;
        for (int index = 0; index < blocked.Length; index++)
        {
            signature = (signature ^ blocked[index]) * 1099511628211UL;
            signature = (signature ^ elevation[index]) * 1099511628211UL;
        }
        if (signature == _obstacleSignature) return;
        _obstacleSignature = signature;
        Array.Clear(NearObstacles);
        for (int row = 0; row < _height; row++)
            for (int col = 0; col < _width; col++)
            {
                var cell = new Vector2I(col, row);
                int cellIndex = Index(cell);
                int currentElevation = elevation[cellIndex];
                for (int y = -1; y <= 1 && NearObstacles[cellIndex] == 0; y++)
                    for (int x = -1; x <= 1; x++)
                    {
                        if (x == 0 && y == 0) continue;
                        var neighbor = cell + new Vector2I(x, y);
                        if (!Valid(neighbor)) { NearObstacles[cellIndex] = 1; break; }
                        int neighborIndex = Index(neighbor);
                        if (blocked[neighborIndex] != 0 || Math.Abs(elevation[neighborIndex] - currentElevation) > 1)
                        {
                            NearObstacles[cellIndex] = 1;
                            break;
                        }
                    }
            }
    }

    private void BuildDirections(byte[] blocked, int goalIndex, byte[] elevation, float uphillCost)
    {
        for (int row = 0; row < _height; row++)
            for (int col = 0; col < _width; col++)
            {
                var cell = new Vector2I(col, row);
                int cellIndex = Index(cell);
                if (cellIndex == goalIndex || blocked[cellIndex] != 0)
                    continue;
                float best = float.PositiveInfinity;
                Vector2I bestOffset = Vector2I.Zero;
                foreach (Vector2I offset in Directions)
                {
                    Vector2I neighbor = cell + offset;
                    if (!Valid(neighbor)) continue;
                    int neighborIndex = Index(neighbor);
                    if (!GroundNavigation.CanTransitionValid(cell, neighbor, blocked, elevation, _width)) continue;
                    int currentElevation = elevation[cellIndex];
                    int neighborElevation = elevation[neighborIndex];
                    float transition = offset.X != 0 && offset.Y != 0 ? DiagonalCost : 1f;
                    if (neighborElevation > currentElevation)
                        transition += Math.Max(0f, uphillCost);
                    float candidate = Costs[neighborIndex] + transition;
                    if (candidate + 0.0001f < best)
                    {
                        best = candidate;
                        bestOffset = offset;
                        NextCells[cellIndex] = neighborIndex;
                    }
                }
                Flow[cellIndex] = new Vector2(bestOffset.X, bestOffset.Y).Normalized();
            }
    }

    private bool Valid(Vector2I cell) => cell.X >= 0 && cell.X < _width && cell.Y >= 0 && cell.Y < _height;
    private int Index(Vector2I cell) => cell.Y * _width + cell.X;
}
