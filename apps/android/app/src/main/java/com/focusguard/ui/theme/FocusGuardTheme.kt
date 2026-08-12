package com.focusguard.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

object FocusGuardColors {
    val Background = Color(0xFF0B0F17)
    val Surface = Color(0xFF161D2A)
    val SurfaceElevated = Color(0xFF1F293D)
    val Border = Color(0xFF2D384D)

    val Accent = Color(0xFF3B82F6)
    val Indigo = Color(0xFF6366F1)
    val Violet = Color(0xFF8B5CF6)

    val Success = Color(0xFF10B981)
    val Warning = Color(0xFFF59E0B)
    val Danger = Color(0xFFEF4444)
    val Info = Color(0xFF38BDF8)

    val TextPrimary = Color(0xFFF8FAFC)
    val TextSecondary = Color(0xFF94A3B8)
    val TextMuted = Color(0xFF64748B)
}

private val DarkColorScheme = darkColorScheme(
    primary = FocusGuardColors.Accent,
    secondary = FocusGuardColors.Indigo,
    tertiary = FocusGuardColors.Violet,
    background = FocusGuardColors.Background,
    surface = FocusGuardColors.Surface,
    onPrimary = Color.White,
    onBackground = FocusGuardColors.TextPrimary,
    onSurface = FocusGuardColors.TextPrimary
)

@Composable
fun FocusGuardTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
