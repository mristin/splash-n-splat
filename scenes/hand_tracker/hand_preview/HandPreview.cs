using Godot;

using SplashNSplat.Vision;

/// <summary>
/// Show the camera image with the tracked hands: their boxes, ids, gestures and
/// probabilities.
/// </summary>
/// <remarks>The image is mirrored like a mirror, if <see cref="Mirror"/> is set.</remarks>
public partial class HandPreview : Control
{
    [Export]
    public bool Mirror = true;

    [Export]
    public bool ShowProbabilities = true;

    [Export]
    public HandVisionService? Service;

    private static readonly Color _openColor = new(0.3f, 0.95f, 0.5f);
    private static readonly Color _fistColor = new(1f, 0.55f, 0.2f);
    private static readonly Color _unknownColor = new(0.75f, 0.8f, 0.9f);

    public override void _Ready()
    {
        MouseFilter = MouseFilterEnum.Ignore;
    }

    public override void _Process(double delta)
    {
        QueueRedraw();
    }

    public override void _Draw()
    {
        var rect = new Rect2(Vector2.Zero, Size);
        DrawRect(rect, new Color(0.05f, 0.08f, 0.12f, 0.6f));

        var texture = Service?.CameraTexture;
        if (texture != null)
        {
            if (Mirror)
            {
                DrawSetTransform(new Vector2(Size.X, 0), 0, new Vector2(-1, 1));
            }

            DrawTextureRect(texture, rect, false, new Color(1, 1, 1, 0.9f));
            DrawSetTransform(Vector2.Zero, 0, Vector2.One);
        }

        var snapshot = Service?.Latest;
        if (snapshot == null)
        {
            DrawRect(rect, _unknownColor, false, 2f);
            return;
        }

        var font = ThemeDB.FallbackFont;
        float sx = Size.X / snapshot.FrameWidth;
        float sy = Size.Y / snapshot.FrameHeight;

        foreach (var hand in snapshot.Hands)
        {
            float x1 = hand.Box.X1 * sx;
            float x2 = hand.Box.X2 * sx;
            if (Mirror)
            {
                (x1, x2) = (Size.X - x2, Size.X - x1);
            }

            var box = new Rect2(x1, hand.Box.Y1 * sy, x2 - x1, hand.Box.Height * sy);
            Color color = hand.Gesture switch
            {
                HandGesture.Open => _openColor,
                HandGesture.Fist => _fistColor,
                _ => _unknownColor,
            };

            if (!hand.IsConfirmed)
            {
                color.A = 0.4f;
            }

            DrawRect(box, color, false, 3f);

            string label = $"#{hand.Id} {hand.Gesture}{(hand.Armed ? " armed" : "")}";
            DrawString(font, box.Position + new Vector2(2, -6), label, HorizontalAlignment.Left, -1, 14, color);

            if (ShowProbabilities && hand.IsClassified)
            {
                DrawBar(box.Position + new Vector2(0, box.Size.Y + 4), box.Size.X, hand.Probabilities.Open, _openColor);
                DrawBar(box.Position + new Vector2(0, box.Size.Y + 12), box.Size.X, hand.Probabilities.Fist, _fistColor);
                DrawBar(box.Position + new Vector2(0, box.Size.Y + 20), box.Size.X, hand.Probabilities.Other, _unknownColor);
            }
        }

        DrawRect(rect, _unknownColor, false, 2f);
    }

    private void DrawBar(Vector2 position, float width, float value, Color color)
    {
        DrawRect(new Rect2(position, new Vector2(width, 6)), new Color(0, 0, 0, 0.5f));
        DrawRect(new Rect2(position, new Vector2(width * Mathf.Clamp(value, 0f, 1f), 6)), color);
    }
}
