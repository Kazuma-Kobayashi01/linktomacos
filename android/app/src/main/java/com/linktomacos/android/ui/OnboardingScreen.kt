package com.linktomacos.android.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding

import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.linktomacos.android.R

private class IntroPage(val badges: List<ImageVector>, val title: Int, val body: Int)

private val pages = listOf(
    IntroPage(listOf(LinkIcons.Bell, LinkIcons.Phone, LinkIcons.Link), R.string.intro1_title, R.string.intro1_body),
    IntroPage(listOf(LinkIcons.Clipboard, LinkIcons.Link, LinkIcons.Laptop), R.string.intro2_title, R.string.intro2_body),
    IntroPage(listOf(LinkIcons.Monitor, LinkIcons.Folder, LinkIcons.Phone), R.string.intro3_title, R.string.intro3_body),
)

/** 还没配对时的首屏：三张介绍页（可左右滑），下面是配对入口。 */
@Composable
fun OnboardingScreen(onScan: () -> Unit, onPaste: () -> Unit, modifier: Modifier = Modifier) {
    val pager = rememberPagerState { pages.size }
    Column(
        modifier = modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        HorizontalPager(state = pager, modifier = Modifier.weight(1f)) { index ->
            val page = pages[index]
            Column(
                modifier = Modifier.fillMaxSize().padding(horizontal = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                HeroCard { HeroIllustration(page.badges, Modifier.fillMaxWidth(0.85f)) }
                Spacer(Modifier.height(40.dp))
                Text(
                    stringResource(page.title),
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    stringResource(page.body),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
        PageDots(count = pages.size, selected = pager.currentPage)
        Spacer(Modifier.height(24.dp))
        Column(Modifier.padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = onScan, modifier = Modifier.fillMaxWidth().height(56.dp)) {
                Icon(LinkIcons.QrCode, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.pair_scan))
            }
            OutlinedButton(onClick = onPaste, modifier = Modifier.fillMaxWidth().height(56.dp)) {
                Text(stringResource(R.string.pair_paste))
            }
            Text(
                stringResource(R.string.state_not_paired_detail),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            )
        }
    }
}

/** 当前页是一条拉长的胶囊，其余是小圆点。 */
@Composable
private fun PageDots(count: Int, selected: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(count) { index ->
            val active = index == selected
            val width = animateDpAsState(if (active) 28.dp else 8.dp, label = "dot").value
            val color = animateColorAsState(
                if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, label = "dotColor",
            ).value
            Box(Modifier.size(width, 8.dp).clip(CircleShape).background(color))
        }
    }
}
