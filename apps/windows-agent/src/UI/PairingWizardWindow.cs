// FocusGuard Windows Agent — Pairing Wizard Window
// Guides the user through the one-time device enrollment process.
// Implements the FocusGuard consent model: explicit, visible, user-initiated.

using System.Windows;
using System.Windows.Media;

namespace FocusGuard.Windows.UI;

/// <summary>
/// Step-by-step pairing wizard shown to a new (unpaired) device.
/// The user must explicitly enter the pairing code from the owner dashboard.
/// This is the consent gate — no pairing happens automatically.
/// </summary>
public sealed partial class PairingWizardWindow : Window
{
    private readonly System.Windows.Controls.TextBox _codeInput;
    private readonly System.Windows.Controls.TextBox _nameInput;
    private readonly System.Windows.Controls.Button _pairButton;
    private readonly System.Windows.Controls.TextBlock _statusLabel;

    public PairingWizardWindow()
    {
        Title = "FocusGuard — Device Enrollment";
        Width = 540;
        Height = 480;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = ResizeMode.NoResize;
        Background = new SolidColorBrush(Color.FromRgb(10, 10, 20));

        var main = new System.Windows.Controls.StackPanel
        {
            Margin = new Thickness(48, 40, 48, 40)
        };

        // Header
        main.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "🛡 FocusGuard",
            FontSize = 28,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            Margin = new Thickness(0, 0, 0, 8)
        });

        main.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "Enroll This Device",
            FontSize = 18,
            Foreground = new SolidColorBrush(Color.FromRgb(165, 180, 252)),
            Margin = new Thickness(0, 0, 0, 4)
        });

        main.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "Enter the 6-character pairing code shown in your FocusGuard dashboard (Owner → Pair New Device).",
            FontSize = 13,
            Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 32)
        });

        // Pairing code input
        main.Children.Add(CreateLabel("Pairing Code (from dashboard)"));
        _codeInput = CreateInput("FG-XXXXXX", isCode: true);
        main.Children.Add(_codeInput);

        Thickness marginBottom = new(0, 0, 0, 20);
        _codeInput.Margin = marginBottom;

        // Device name input
        main.Children.Add(CreateLabel("Device Name (your choice)"));
        _nameInput = CreateInput(Environment.MachineName);
        main.Children.Add(_nameInput);
        _nameInput.Margin = new Thickness(0, 0, 0, 32);

        // Pair button
        _pairButton = new System.Windows.Controls.Button
        {
            Content = "🔗 Enroll This Device",
            Height = 48,
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            Background = new LinearGradientBrush(
                Color.FromRgb(79, 70, 229),
                Color.FromRgb(124, 58, 237),
                90),
            Foreground = Brushes.White,
            BorderThickness = new Thickness(0),
            Cursor = System.Windows.Input.Cursors.Hand,
            Margin = new Thickness(0, 0, 0, 16)
        };
        _pairButton.Click += OnPairButtonClick;
        main.Children.Add(_pairButton);

        // Status label
        _statusLabel = new System.Windows.Controls.TextBlock
        {
            FontSize = 13,
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 8, 0, 0)
        };
        main.Children.Add(_statusLabel);

        // Consent note
        main.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "By enrolling, you explicitly consent to having this device managed " +
                   "by the FocusGuard account linked to this code. " +
                   "You can un-enroll at any time from Settings.",
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.FromRgb(71, 85, 105)),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 24, 0, 0)
        });

        Content = main;
    }

    private async void OnPairButtonClick(object sender, RoutedEventArgs e)
    {
        var code = _codeInput.Text.Trim().ToUpperInvariant();
        var name = _nameInput.Text.Trim();

        if (string.IsNullOrWhiteSpace(code) || code == "FG-XXXXXX")
        {
            SetStatus("⚠️ Please enter your pairing code.", isError: true);
            return;
        }

        if (string.IsNullOrWhiteSpace(name))
        {
            name = Environment.MachineName;
        }

        _pairButton.IsEnabled = false;
        SetStatus("🔄 Enrolling device...", isError: false);

        try
        {
            var app = (App)System.Windows.Application.Current;
            // App exposes the orchestrator for enrollment
            // In a full DI setup this would be injected, but for clarity we access it directly
            if (app._orchestrator is not null)
            {
                var identity = await app._orchestrator.EnrollWithPairingCodeAsync(code, name);
                SetStatus($"✅ Enrolled successfully! Device: {identity.DeviceName}", isError: false);

                // Close wizard after 2 seconds on success
                await Task.Delay(2000);
                Close();
            }
        }
        catch (Exception ex)
        {
            SetStatus($"❌ Enrollment failed: {ex.Message}", isError: true);
            _pairButton.IsEnabled = true;
        }
    }

    private void SetStatus(string message, bool isError)
    {
        _statusLabel.Text = message;
        _statusLabel.Foreground = isError
            ? new SolidColorBrush(Color.FromRgb(248, 113, 113))
            : new SolidColorBrush(Color.FromRgb(74, 222, 128));
    }

    private static System.Windows.Controls.TextBlock CreateLabel(string text) =>
        new()
        {
            Text = text,
            FontSize = 13,
            FontWeight = FontWeights.Medium,
            Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
            Margin = new Thickness(0, 0, 0, 6)
        };

    private static System.Windows.Controls.TextBox CreateInput(string placeholder, bool isCode = false) =>
        new()
        {
            Text = placeholder,
            FontSize = isCode ? 20 : 14,
            FontFamily = isCode ? new System.Windows.Media.FontFamily("Consolas") : new System.Windows.Media.FontFamily("Segoe UI"),
            Height = isCode ? 52 : 40,
            Padding = new Thickness(12, 8, 12, 8),
            Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)),
            Foreground = new SolidColorBrush(Color.FromRgb(226, 232, 240)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85)),
            BorderThickness = new Thickness(1),
            CaretBrush = Brushes.White,
            TextAlignment = isCode ? TextAlignment.Center : TextAlignment.Left
        };
}
