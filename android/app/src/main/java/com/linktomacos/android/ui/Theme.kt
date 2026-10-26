package com.linktomacos.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 应用主题：颜色完全取自系统调色盘（Material You）。
 * Android 12+ 会把壁纸或用户在“壁纸和风格 → 调色板”里选的颜色提炼成一整套色阶，
 * 这里直接用，所以换壁纸、换调色板、切换深浅色，应用跟着变；最低要求 Android 15，不需要备用配色。
 */
@Composable
fun LinkTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val colors = if (isSystemInDarkTheme()) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    val base = MaterialTheme.typography
    MaterialTheme(
        colorScheme = colors,
        typography = Typography(
            displaySmall = base.displaySmall.copy(fontWeight = FontWeight.SemiBold),
            headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.SemiBold, lineHeight = 36.sp),
            headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
            titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
            titleMedium = base.titleMedium.copy(fontWeight = FontWeight.Medium),
            labelLarge = base.labelLarge.copy(fontWeight = FontWeight.SemiBold),
        ),
        shapes = Shapes(
            small = RoundedCornerShape(12.dp),
            medium = RoundedCornerShape(16.dp),
            large = RoundedCornerShape(24.dp),
            extraLarge = RoundedCornerShape(32.dp),
        ),
        content = content,
    )
}

/** 整个应用的底：背景色，顶部带一层从主色容器渐隐的色晕，让页面有颜色又不抢内容。 */
@Composable
fun Modifier.screenWash(): Modifier {
    val colors = MaterialTheme.colorScheme
    return background(colors.background).background(
        Brush.verticalGradient(
            0f to colors.primaryContainer.copy(alpha = 0.6f),
            0.5f to colors.tertiaryContainer.copy(alpha = 0.12f),
            1f to Color.Transparent,
        ),
    )
}

/** 功能的强调色，三种取自系统调色盘的不同角色，让列表不单调。 */
enum class Accent { Primary, Secondary, Tertiary }

@Composable
fun Accent.container(): Color = when (this) {
    Accent.Primary -> MaterialTheme.colorScheme.primaryContainer
    Accent.Secondary -> MaterialTheme.colorScheme.secondaryContainer
    Accent.Tertiary -> MaterialTheme.colorScheme.tertiaryContainer
}

@Composable
fun Accent.onContainer(): Color = when (this) {
    Accent.Primary -> MaterialTheme.colorScheme.onPrimaryContainer
    Accent.Secondary -> MaterialTheme.colorScheme.onSecondaryContainer
    Accent.Tertiary -> MaterialTheme.colorScheme.onTertiaryContainer
}

@Composable
fun Accent.solid(): Color = when (this) {
    Accent.Primary -> MaterialTheme.colorScheme.primary
    Accent.Secondary -> MaterialTheme.colorScheme.secondary
    Accent.Tertiary -> MaterialTheme.colorScheme.tertiary
}

@Composable
fun Accent.onSolid(): Color = when (this) {
    Accent.Primary -> MaterialTheme.colorScheme.onPrimary
    Accent.Secondary -> MaterialTheme.colorScheme.onSecondary
    Accent.Tertiary -> MaterialTheme.colorScheme.onTertiary
}
