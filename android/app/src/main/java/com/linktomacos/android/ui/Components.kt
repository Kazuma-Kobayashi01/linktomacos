package com.linktomacos.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.linktomacos.android.R

/** 圆形底的图标，用来标识一项功能。 */
@Composable
fun IconBadge(
    icon: ImageVector,
    modifier: Modifier = Modifier,
    accent: Accent = Accent.Secondary,
    container: Color = accent.container(),
    tint: Color = accent.onContainer(),
    size: Dp = 44.dp,
) {
    Box(modifier.size(size).clip(CircleShape).background(container), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(size * 0.55f))
    }
}

/** 一组相关的行，放在一个大圆角的浅色面板里，行之间有分隔线。 */
@Composable
fun ListCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(content = content)
    }
}

@Composable
fun RowDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(start = 72.dp, end = 20.dp),
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
    )
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.padding(start = 20.dp, top = 8.dp),
    )
}

/** 可点击的功能入口：图标、标题、一行状态，右侧是箭头。[attention] 为真时状态用醒目的颜色，提示这里需要处理。 */
@Composable
fun NavRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    attention: Boolean = false,
    accent: Accent = Accent.Primary,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).padding(horizontal = 20.dp, vertical = 14.dp),
    ) {
        IconBadge(
            icon,
            accent = accent,
            container = if (attention) MaterialTheme.colorScheme.errorContainer else accent.container(),
            tint = if (attention) MaterialTheme.colorScheme.onErrorContainer else accent.onContainer(),
        )
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = if (attention) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(LinkIcons.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun ToggleRow(title: String, subtitle: String?, checked: Boolean, onChecked: (Boolean) -> Unit, enabled: Boolean = true) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth().clickable(enabled = enabled, role = Role.Switch) { onChecked(!checked) }.padding(horizontal = 20.dp, vertical = 14.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

/** 权限一行：标题、已授予或未授予，未授予时右侧给一个“授权”按钮。 */
@Composable
fun PermissionRow(title: String, granted: Boolean, onGrant: () -> Unit, actionLabel: String = stringResource(R.string.go_grant)) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(if (granted) R.string.granted else R.string.not_granted),
                style = MaterialTheme.typography.bodyMedium,
                color = if (granted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
            )
        }
        if (granted) {
            Icon(LinkIcons.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        } else {
            FilledTonalButton(onClick = onGrant) { Text(actionLabel) }
        }
    }
}

/** 一段说明文字，放在面板之间。 */
@Composable
fun Hint(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(horizontal = 20.dp),
    )
}

/**
 * 功能页的统一外框：可折叠的大标题和返回键，顶部一幅小插图和一句话说明，下面是这一页的设置。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeaturePage(
    title: String,
    badges: List<ImageVector>,
    summary: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = modifier.nestedScroll(scroll.nestedScrollConnection),
        containerColor = Color.Transparent,
        topBar = {
            LargeTopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent, scrolledContainerColor = Color.Transparent),
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(LinkIcons.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                scrollBehavior = scroll,
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            HeroCard(Modifier.padding(horizontal = 16.dp)) {
                HeroIllustration(badges, Modifier.fillMaxWidth(0.7f))
            }
            Text(
                summary,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 24.dp),
            )
            Column(
                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                content = content,
            )
        }
    }
}

/** 带渐变和几个半透明大圆的卡片，放插图或主要状态；颜色全部来自系统调色盘。 */
@Composable
fun HeroCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val colors = MaterialTheme.colorScheme
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(32.dp))
            .background(Brush.linearGradient(listOf(colors.primaryContainer, colors.tertiaryContainer)))
            .drawBehind {
                drawCircle(colors.primary.copy(alpha = 0.10f), radius = size.minDimension * 0.55f, center = Offset(size.width * 0.95f, size.height * 0.05f))
                drawCircle(colors.tertiary.copy(alpha = 0.10f), radius = size.minDimension * 0.45f, center = Offset(size.width * 0.05f, size.height * 0.95f))
            },
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content,
        )
    }
}
