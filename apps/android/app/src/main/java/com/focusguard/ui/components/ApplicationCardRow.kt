package com.focusguard.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.focusguard.ui.theme.FocusGuardColors

data class AppUsageModel(
    val name: String,
    val usedMinutes: Int,
    val limitMinutes: Int,
    val themeColor: Color
) {
    val remainingMinutes: Int get() = (limitMinutes - usedMinutes).coerceAtLeast(0)

    val statusText: String get() = when {
        usedMinutes >= limitMinutes -> "Limit Reached"
        remainingMinutes <= 5 -> "Almost at limit"
        else -> "Active"
    }

    val statusColor: Color get() = when {
        usedMinutes >= limitMinutes -> FocusGuardColors.Danger
        remainingMinutes <= 5 -> FocusGuardColors.Warning
        else -> FocusGuardColors.Success
    }
}

@Composable
fun ApplicationCardRow(item: AppUsageModel) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(FocusGuardColors.Surface, RoundedCornerShape(12.dp))
            .border(1.dp, FocusGuardColors.Border, RoundedCornerShape(12.dp))
            .padding(14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = item.name,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = FocusGuardColors.TextPrimary
            )

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "${item.usedMinutes}m / ${item.limitMinutes}m",
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    color = FocusGuardColors.TextSecondary
                )
                Text(
                    text = "• ${item.remainingMinutes}m remaining",
                    fontSize = 12.sp,
                    color = if (item.remainingMinutes <= 5) FocusGuardColors.Warning else FocusGuardColors.TextMuted
                )
            }
        }

        Box(
            modifier = Modifier
                .background(item.statusColor.copy(alpha = 0.12f), RoundedCornerShape(6.dp))
                .border(1.dp, item.statusColor.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = item.statusText,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = item.statusColor
            )
        }
    }
}
