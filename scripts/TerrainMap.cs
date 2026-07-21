using Godot;
using System;
using System.Collections.Generic;

internal sealed class TerrainMap
{
    private static readonly Vector2I[] Neighbors =
    {
        new(-1, 0), new(1, 0), new(0, -1), new(0, 1),
        new(-1, -1), new(1, -1), new(-1, 1), new(1, 1),
    };

    public readonly int Width;
    public readonly int Height;
    public byte[] Elevation;
    public byte[] Water;

    public TerrainMap(int width, int height)
    {
        Width = Math.Max(1, width);
        Height = Math.Max(1, height);
        Elevation = new byte[Width * Height];
        Water = new byte[Width * Height];
    }

    public byte[] GenerateCentralLake(ulong seed)
    {
        Array.Clear(Water);
        float centerX = (Width - 1) * 0.5f;
        float centerY = (Height - 1) * 0.5f;
        float radiusX = Math.Max(4f, BattleConfig.LakeRadiusX);
        float radiusY = Math.Max(5f, BattleConfig.LakeRadiusY);
        for (int row = 0; row < Height; row++)
            for (int col = 0; col < Width; col++)
            {
                float dx = Math.Abs(col - centerX) / radiusX;
                float dy = Math.Abs(row - centerY) / radiusY;
                float edgeNoise = 0.075f * Mathf.Sin((Math.Abs(row - centerY) + (seed % 7)) * 1.37f)
                    + 0.045f * Mathf.Cos((Math.Abs(col - centerX) + (seed % 11)) * 1.91f);
                if (dx * dx + dy * dy <= 1f + edgeNoise)
                    Water[Index(new Vector2I(col, row))] = 1;
            }
        ClearHqZones();
        return (byte[])Water.Clone();
    }

    public byte[] Generate(ulong seed, int hillPairs, int summitPairs, int cliffPairs, int minimumRow, int maximumRow, int deploymentDepth, int maximumAttempts)
    {
        for (int attempt = 0; attempt < Math.Max(1, maximumAttempts); attempt++)
        {
            Array.Clear(Elevation);
            var rng = new RandomNumberGenerator { Seed = seed + (ulong)(attempt * 104729) };
            StampHillPairs(rng, hillPairs, summitPairs, minimumRow, maximumRow);
            StampCliffPairs(rng, cliffPairs, minimumRow, maximumRow);
            ClearHqZones();
            for (int i = 0; i < Elevation.Length; i++)
                if (Water[i] != 0) Elevation[i] = 0;
            if (AllRequiredPathsReachable(deploymentDepth))
                return (byte[])Elevation.Clone();
        }
        Array.Clear(Elevation);
        return (byte[])Elevation.Clone();
    }

    public int GetElevation(Vector2I cell) => Valid(cell) ? Elevation[Index(cell)] : 0;
    public bool CanStep(Vector2I from, Vector2I to) =>
        GroundNavigation.CanTransition(from, to, Water, Elevation, Width, Height);

    public bool AllRequiredPathsReachable(int deploymentDepth)
    {
        var enemyHq = new Vector2I(Width / 2, 0);
        var allyHq = new Vector2I(Width / 2, Height - 1);
        byte[] fromEnemy = ReachableFrom(enemyHq);
        byte[] fromAlly = ReachableFrom(allyHq);
        for (int i = 0; i < Elevation.Length; i++)
            if (Water[i] == 0 && (fromEnemy[i] == 0 || fromAlly[i] == 0))
                return false;
        int depth = Math.Clamp(deploymentDepth, 1, Math.Max(1, Height / 2 - 1));
        for (int row = 1; row <= depth; row++)
            for (int col = 0; col < Width; col++)
                if (fromAlly[Index(new Vector2I(col, row))] == 0)
                    return false;
        for (int row = Height - depth - 1; row < Height - 1; row++)
            for (int col = 0; col < Width; col++)
                if (fromEnemy[Index(new Vector2I(col, row))] == 0)
                    return false;
        return fromEnemy[Index(allyHq)] != 0 && fromAlly[Index(enemyHq)] != 0;
    }

    private void StampHillPairs(RandomNumberGenerator rng, int pairCount, int summitCount, int minimumRow, int maximumRow)
    {
        int minRow = Math.Clamp(minimumRow, 2, Math.Max(2, Height / 2 - 2));
        int maxRow = Math.Clamp(maximumRow, minRow, Math.Max(minRow, Height / 2 - 1));
        for (int pair = 0; pair < Math.Max(0, pairCount); pair++)
        {
            var center = new Vector2I(rng.RandiRange(2, Math.Max(2, Width - 3)), rng.RandiRange(minRow, maxRow));
            int radiusX = rng.RandiRange(2, 4);
            int radiusY = rng.RandiRange(2, 4);
            for (int y = -radiusY; y <= radiusY; y++)
                for (int x = -radiusX; x <= radiusX; x++)
                {
                    float normalized = Mathf.Pow((float)x / radiusX, 2f) + Mathf.Pow((float)y / radiusY, 2f);
                    if (normalized <= 1f)
                        SetMirrored(center + new Vector2I(x, y), 1);
                }
            if (pair < summitCount)
            {
                SetMirrored(center, 2);
                if ((pair & 1) == 0)
                    SetMirrored(center + new Vector2I(center.X < Width / 2 ? 1 : -1, 0), 2);
            }
        }
    }

    private void StampCliffPairs(RandomNumberGenerator rng, int pairCount, int minimumRow, int maximumRow)
    {
        int minRow = Math.Clamp(minimumRow, 2, Math.Max(2, Height / 2 - 2));
        int maxRow = Math.Clamp(maximumRow, minRow, Math.Max(minRow, Height / 2 - 1));
        int added = 0;
        for (int attempt = 0; attempt < 128 && added < pairCount; attempt++)
        {
            var cell = new Vector2I(rng.RandiRange(1, Math.Max(1, Width - 2)), rng.RandiRange(minRow, maxRow));
            if (GetElevation(cell) != 0 || !NeighborsAreLevel(cell, 0))
                continue;
            SetMirrored(cell, 2);
            SetMirrored(cell + Vector2I.Up, 1);
            added++;
        }
    }

    private bool NeighborsAreLevel(Vector2I cell, int level)
    {
        foreach (Vector2I offset in Neighbors)
        {
            Vector2I neighbor = cell + offset;
            if (Valid(neighbor) && GetElevation(neighbor) != level)
                return false;
        }
        return true;
    }

    private void SetMirrored(Vector2I cell, int level)
    {
        if (!Valid(cell))
            return;
        var mirrored = new Vector2I(Width - 1 - cell.X, Height - 1 - cell.Y);
        if (Water[Index(cell)] != 0 || Water[Index(mirrored)] != 0)
            return;
        byte value = (byte)Math.Max(Elevation[Index(cell)], Math.Clamp(level, 0, 2));
        Elevation[Index(cell)] = value;
        Elevation[Index(mirrored)] = value;
    }

    private void ClearHqZones()
    {
        Vector2I[] hqs = { new(Width / 2, 0), new(Width / 2, Height - 1) };
        foreach (Vector2I hq in hqs)
            for (int y = -2; y <= 2; y++)
                for (int x = -2; x <= 2; x++)
                {
                    Vector2I cell = hq + new Vector2I(x, y);
                    if (Valid(cell))
                    {
                        Elevation[Index(cell)] = 0;
                        Water[Index(cell)] = 0;
                    }
                }
    }

    private byte[] ReachableFrom(Vector2I start)
    {
        var visited = new byte[Width * Height];
        if (!Valid(start) || Water[Index(start)] != 0)
            return visited;
        var queue = new Queue<Vector2I>();
        queue.Enqueue(start);
        visited[Index(start)] = 1;
        while (queue.Count > 0)
        {
            Vector2I current = queue.Dequeue();
            foreach (Vector2I offset in Neighbors)
            {
                Vector2I neighbor = current + offset;
                if (!Valid(neighbor) || Water[Index(neighbor)] != 0 || visited[Index(neighbor)] != 0 || !CanStep(current, neighbor))
                    continue;
                visited[Index(neighbor)] = 1;
                queue.Enqueue(neighbor);
            }
        }
        return visited;
    }

    private bool Valid(Vector2I cell) => cell.X >= 0 && cell.X < Width && cell.Y >= 0 && cell.Y < Height;
    private int Index(Vector2I cell) => cell.Y * Width + cell.X;
}
