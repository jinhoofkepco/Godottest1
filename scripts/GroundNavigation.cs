using Godot;
using System;

internal static class GroundNavigation
{
    public const int InfantryClearance = 0;
    public const int HeavyClearance = 1;

    private static bool Valid(Vector2I cell, int width, int height) =>
        cell.X >= 0 && cell.X < width && cell.Y >= 0 && cell.Y < height;

    private static int Index(Vector2I cell, int width) => cell.Y * width + cell.X;

    public static void BuildClearanceMask(byte[] blocked, byte[] elevation, int width, int height, float radius, byte[] output)
    {
        if (blocked.Length != width * height || elevation.Length != blocked.Length || output.Length != blocked.Length)
            throw new ArgumentException("ground navigation mask size mismatch");
        if (radius <= 0.5f)
        {
            Array.Copy(blocked, output, blocked.Length);
            return;
        }
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++)
            {
                var cell = new Vector2I(col, row);
                output[Index(cell, width)] = CanOccupyPosition(
                    new Vector2(col + 0.5f, row + 0.5f), radius, blocked, elevation, width, height) ? (byte)0 : (byte)1;
            }
    }

    public static bool MasksEqual(byte[] first, byte[] second)
    {
        if (first.Length != second.Length) return false;
        for (int i = 0; i < first.Length; i++)
            if (first[i] != second[i]) return false;
        return true;
    }

    public static bool CanTransition(Vector2I from, Vector2I to, byte[] blocked, byte[] elevation, int width, int height)
    {
        if (!Valid(from, width, height) || !Valid(to, width, height)) return false;
        int dx = to.X - from.X;
        int dy = to.Y - from.Y;
        if (Math.Abs(dx) > 1 || Math.Abs(dy) > 1 || dx == 0 && dy == 0) return false;
        return CanTransitionValid(from, to, blocked, elevation, width);
    }

    public static bool CanTransitionValid(Vector2I from, Vector2I to, byte[] blocked, byte[] elevation, int width)
    {
        int dx = to.X - from.X;
        int dy = to.Y - from.Y;
        int fromIndex = Index(from, width);
        int toIndex = Index(to, width);
        int fromElevation = elevation[fromIndex];
        int toElevation = elevation[toIndex];
        if (blocked[fromIndex] != 0 || blocked[toIndex] != 0 || Math.Abs(fromElevation - toElevation) > 1) return false;
        if (dx == 0 || dy == 0) return true;

        // A diagonal is legal only when both possible orthogonal routes are legal.
        // This prevents a unit circle from slipping through a pinched cliff corner.
        var horizontal = new Vector2I(to.X, from.Y);
        var vertical = new Vector2I(from.X, to.Y);
        int horizontalIndex = Index(horizontal, width);
        int verticalIndex = Index(vertical, width);
        int horizontalElevation = elevation[horizontalIndex];
        int verticalElevation = elevation[verticalIndex];
        return blocked[horizontalIndex] == 0 && blocked[verticalIndex] == 0
            && Math.Abs(fromElevation - horizontalElevation) <= 1
            && Math.Abs(horizontalElevation - toElevation) <= 1
            && Math.Abs(fromElevation - verticalElevation) <= 1
            && Math.Abs(verticalElevation - toElevation) <= 1;
    }

    public static bool CanOccupyPosition(Vector2 position, float radius, byte[] blocked, byte[]? elevation, int width, int height)
    {
        float safeRadius = Math.Max(0f, radius);
        if (position.X - safeRadius < 0f || position.X + safeRadius > width
            || position.Y - safeRadius < 0f || position.Y + safeRadius > height)
            return false;
        Vector2I center = new(Math.Clamp(Mathf.FloorToInt(position.X), 0, width - 1), Math.Clamp(Mathf.FloorToInt(position.Y), 0, height - 1));
        if (blocked[Index(center, width)] != 0) return false;
        float localX = position.X - center.X;
        float localY = position.Y - center.Y;
        if (safeRadius <= 0.5f && localX >= safeRadius && localX <= 1f - safeRadius
            && localY >= safeRadius && localY <= 1f - safeRadius)
            return true;
        int centerElevation = elevation == null ? 0 : elevation[Index(center, width)];
        int minimumCol = Math.Max(0, Mathf.FloorToInt(position.X - safeRadius));
        int maximumCol = Math.Min(width - 1, Mathf.FloorToInt(position.X + safeRadius));
        int minimumRow = Math.Max(0, Mathf.FloorToInt(position.Y - safeRadius));
        int maximumRow = Math.Min(height - 1, Mathf.FloorToInt(position.Y + safeRadius));
        float radiusSq = safeRadius * safeRadius;
        for (int row = minimumRow; row <= maximumRow; row++)
            for (int col = minimumCol; col <= maximumCol; col++)
            {
                int cellIndex = row * width + col;
                bool impassable = blocked[cellIndex] != 0
                    || elevation != null && Math.Abs(elevation[cellIndex] - centerElevation) > 1;
                if (!impassable) continue;
                float closestX = Mathf.Clamp(position.X, col, col + 1f);
                float closestY = Mathf.Clamp(position.Y, row, row + 1f);
                float offsetX = position.X - closestX;
                float offsetY = position.Y - closestY;
                if (offsetX * offsetX + offsetY * offsetY < radiusSq - 0.000001f)
                    return false;
            }
        return true;
    }

}
