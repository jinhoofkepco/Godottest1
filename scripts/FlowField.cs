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

    public FlowField(int width, int height)
    {
        _width = Math.Max(1, width);
        _height = Math.Max(1, height);
        Costs = new float[_width * _height];
        Flow = new Vector2[_width * _height];
    }

    public void Rebuild(Vector2I goal, byte[] blocked, int[] density, float congestionWeight, byte[] elevation, float uphillCost)
    {
        Array.Fill(Costs, float.PositiveInfinity);
        Array.Clear(Flow);
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
                if (!Valid(neighbor))
                    continue;
                int neighborIndex = Index(neighbor);
                if (neighborIndex != goalIndex && blocked[neighborIndex] != 0)
                    continue;
                if (offset.X != 0 && offset.Y != 0 && DiagonalPinched(current, offset, blocked, goalIndex))
                    continue;
                int neighborElevation = elevation[neighborIndex];
                if (Math.Abs(neighborElevation - currentElevation) > 1)
                    continue;
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
    }

    public float CostAt(Vector2I cell) => Valid(cell) ? Costs[Index(cell)] : float.PositiveInfinity;
    public Vector2 DirectionAt(Vector2I cell) => Valid(cell) ? Flow[Index(cell)] : Vector2.Zero;

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
                int currentElevation = elevation[cellIndex];
                foreach (Vector2I offset in Directions)
                {
                    Vector2I neighbor = cell + offset;
                    if (!Valid(neighbor))
                        continue;
                    int neighborIndex = Index(neighbor);
                    if (neighborIndex != goalIndex && blocked[neighborIndex] != 0)
                        continue;
                    if (offset.X != 0 && offset.Y != 0 && DiagonalPinched(cell, offset, blocked, goalIndex))
                        continue;
                    int neighborElevation = elevation[neighborIndex];
                    if (Math.Abs(neighborElevation - currentElevation) > 1)
                        continue;
                    float transition = offset.X != 0 && offset.Y != 0 ? DiagonalCost : 1f;
                    if (neighborElevation > currentElevation)
                        transition += Math.Max(0f, uphillCost);
                    float candidate = Costs[neighborIndex] + transition;
                    if (candidate + 0.0001f < best)
                    {
                        best = candidate;
                        bestOffset = offset;
                    }
                }
                Flow[cellIndex] = new Vector2(bestOffset.X, bestOffset.Y).Normalized();
            }
    }

    private bool DiagonalPinched(Vector2I cell, Vector2I offset, byte[] blocked, int goalIndex)
    {
        return BlockedAt(new Vector2I(cell.X + offset.X, cell.Y), blocked, goalIndex)
            && BlockedAt(new Vector2I(cell.X, cell.Y + offset.Y), blocked, goalIndex);
    }

    private bool BlockedAt(Vector2I cell, byte[] blocked, int goalIndex)
    {
        if (!Valid(cell))
            return true;
        int index = Index(cell);
        return index != goalIndex && blocked[index] != 0;
    }

    private bool Valid(Vector2I cell) => cell.X >= 0 && cell.X < _width && cell.Y >= 0 && cell.Y < _height;
    private int Index(Vector2I cell) => cell.Y * _width + cell.X;
}
