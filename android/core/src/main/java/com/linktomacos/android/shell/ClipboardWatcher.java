package com.linktomacos.android.shell;

import android.annotation.SuppressLint;
import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONObject;

import java.lang.reflect.Constructor;

/**
 * 手机剪贴板的读写。普通 App 在后台读不了剪贴板（Android 10 起只有前台或输入法能读），
 * shell 身份没有这个限制，所以由这个常驻服务来监听复制、并代 Mac 写入。
 *
 * ClipboardManager 的构造函数是隐藏的；用伪造的 shell 上下文（包名 com.android.shell）建一个，
 * 它调用系统服务时带的就是 shell 的身份。监听回调要投递到主线程 Looper（ShellMain 已经准备好）。
 */
@SuppressLint({"PrivateApi", "DiscouragedPrivateApi", "BlockedPrivateApi"})
final class ClipboardWatcher {
    /** 单条文本的上限（字符数）。再大的文本一个协议帧装不下。 */
    static final int MAX_CHARS = 200_000;

    private final Link link;
    private final ClipboardManager manager;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private volatile boolean watching;
    /** 最近一次由 Mac 写入的文本。系统会为这次写入再回调一次监听，据此跳过，避免回传。 */
    private volatile String lastWritten;

    private final ClipboardManager.OnPrimaryClipChangedListener listener = this::onChanged;

    ClipboardWatcher(Link link) throws Exception {
        this.link = link;
        Context context = Hidden.context();
        Constructor<ClipboardManager> constructor = ClipboardManager.class.getDeclaredConstructor(Context.class, Handler.class);
        constructor.setAccessible(true);
        manager = constructor.newInstance(context, handler);
    }

    /** 开始监听。重复调用无害。 */
    void start() {
        if (watching) return;
        watching = true;
        manager.addPrimaryClipChangedListener(listener);
    }

    void stop() {
        if (!watching) return;
        watching = false;
        manager.removePrimaryClipChangedListener(listener);
    }

    /** 把 Mac 上复制的文本写进手机剪贴板。 */
    void set(String text) {
        lastWritten = text;
        manager.setPrimaryClip(ClipData.newPlainText("Link to macOS", text));
    }

    /** 只检查读取是否可行，用于 --clip-selftest。返回当前剪贴板文本的长度，空或无文本返回 0。 */
    int peekLength() {
        ClipData clip = manager.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return 0;
        CharSequence text = clip.getItemAt(0).getText();
        return text == null ? 0 : text.length();
    }

    private void onChanged() {
        try {
            ClipData clip = manager.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0) return;
            // 密码管理器等会把剪贴板标成敏感内容，不往外发
            ClipDescription description = clip.getDescription();
            if (description != null && description.getExtras() != null
                    && description.getExtras().getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false)) {
                return;
            }
            CharSequence text = clip.getItemAt(0).getText();
            if (text == null || text.length() == 0 || text.length() > MAX_CHARS) return;
            String value = text.toString();
            if (value.equals(lastWritten)) {
                lastWritten = null; // 这是自己那次写入的回声，只跳过一次
                return;
            }
            link.sendJson(new JSONObject().put("t", "clip").put("text", value));
        } catch (Throwable t) {
            Log.e("clipboard read failed", t);
        }
    }
}
