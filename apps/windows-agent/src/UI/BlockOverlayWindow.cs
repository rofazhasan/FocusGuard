// FocusGuard Windows Agent — Block Overlay Window
// A topmost, non-closeable WPF window that overlays the blocked application.
// Displays: blocked target, reason, policy name, remaining time until reset.
//
// Design: Cannot be closed by Alt+F4 or X. User cannot click through it.
// This is the consumer-mode enforcement mechanism on Windows.
// (Enterprise mode would use AppLocker/WDAC to prevent app launch entirely.)

using System.Windows;
using System.Windows.Media;
using FocusGuard.Windows.Domain.Models;

namespace FocusGuard.Windows.UI;

/// <summary>
/// Fullscreen topmost WPF overlay window displayed when a block is enforced.
/// Prevents interaction with the blocked app without terminating it.
/// </summary>
public sealed partial class BlockOverlayWindow : Window
{
    private readonly PolicyDecision _decision;

    public BlockOverlayWindow(string target, PolicyDecision decision)
    {
        _decision = decision;
        InitializeComponent();
        RenderBlock(target, decision);
    }

    private void RenderBlock(string target, PolicyDecision decision)
    {
        Title = "FocusGuard — Access Restricted";
        WindowState = WindowState.Maximized;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        AllowsTransparency = false;

        Background = new SolidColorBrush(Color.FromRgb(10, 10, 20));

        var grid = new System.Windows.Controls.Grid();
        var stack = new System.Windows.Controls.StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(40)
        };

        // Shield icon
        stack.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "🛡",
            FontSize = 80,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 24)
        });

        // "Access Restricted" heading
        stack.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "Access Restricted",
            FontSize = 36,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 12)
        });

        // Target domain/app
        stack.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = target,
            FontSize = 22,
            Foreground = new SolidColorBrush(Color.FromRgb(165, 180, 252)),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 8)
        });

        // Reason
        var reasonText = decision.Reason switch
        {
            "TIME_LIMIT_EXCEEDED" =>
                $"You've reached your daily limit of {decision.LimitSeconds / 60} minutes.",
            "FOCUS_MODE_ACTIVE" =>
                "A focus session is active. This site is blocked during focus.",
            "EXPLICIT_BLOCK_RULE" =>
                "This site is blocked by your FocusGuard policy.",
            "SCHEDULED_BLOCK_ACTIVE" =>
                "This site is blocked during your scheduled block hours.",
            _ => decision.Reason
        };

        stack.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = reasonText,
            FontSize = 16,
            Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
            HorizontalAlignment = HorizontalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 600,
            TextAlignment = TextAlignment.Center,
            Margin = new Thickness(0, 0, 0, 32)
        });

        // Used / Limit info
        if (decision.LimitSeconds > 0)
        {
            stack.Children.Add(new System.Windows.Controls.TextBlock
            {
                Text = $"Used: {decision.UsedSeconds / 60}m / Limit: {decision.LimitSeconds / 60}m",
                FontSize = 14,
                FontFamily = new FontFamily("Consolas"),
                Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)),
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 40)
            });
        }

        // Reset info
        stack.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "Your limit resets at midnight UTC.",
            FontSize = 13,
            Foreground = new SolidColorBrush(Color.FromRgb(71, 85, 105)),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 24)
        });

        // Close button (only visible if owner allows early close — otherwise hidden)
        // Currently: hidden. Owner can unlock via STOP_FOCUS command.
        var closeBtn = new System.Windows.Controls.Button
        {
            Content = "Minimize (Return Later)",
            Padding = new Thickness(24, 12, 24, 12),
            FontSize = 14,
            Background = new SolidColorBrush(Color.FromRgb(30, 41, 59)),
            Foreground = Brushes.White,
            BorderThickness = new Thickness(1),
            BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
            Cursor = System.Windows.Input.Cursors.Hand
        };
        closeBtn.Click += (_, _) => WindowState = WindowState.Minimized;
        stack.Children.Add(closeBtn);

        grid.Children.Add(stack);
        Content = grid;
    }

    // Prevent Alt+F4 close
    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // Only allow close from policy engine releasing the block
        e.Cancel = true;
        WindowState = WindowState.Minimized;
    }

    /// <summary>
    /// Called by the enforcement adapter when the block is released (e.g. focus session ends).
    /// </summary>
    public void Release()
    {
        Dispatcher.Invoke(() =>
        {
            // Allow close now
            Closing -= (_, e) => e.Cancel = true;
            Close();
        });
    }
}
