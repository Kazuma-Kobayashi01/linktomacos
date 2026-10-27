package com.linktomacos.android.shell;

import android.content.ComponentName;
import android.content.Intent;
import android.hardware.display.VirtualDisplay;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.os.Bundle;
import android.view.Surface;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.util.concurrent.TimeUnit;

/**
 * 读取显示内容并编码成 H.264，发给 App。两种模式：
 *  - MODE_NEW：新建一个独立的虚拟显示器，应用开在它上面；手机屏幕可以关掉或锁屏。可以用 requestResize 调整它的尺寸，应用会重新排版。
 *  - MODE_MIRROR：镜像手机主屏。旋转导致尺寸变化时自动重建编码器。
 */
final class ScreenMirror {
    static final int MODE_MIRROR = 0;
    static final int MODE_NEW = 1;

    private static final int ALIGN = 8;
    private static final int MIN_SIDE = 320;
    private static final int REPEAT_FRAME_DELAY_US = 100_000;
    private static final int I_FRAME_INTERVAL_SECONDS = 3;
    private static final int IME_POLICY_HIDE = 2;

    static final class Params {
        int mode = MODE_NEW;
        int displayId = 0;
        int maxSize = 1920;
        int bitRate = 8_000_000;
        int maxFps = 60;
        /** 独立显示的初始尺寸；0 表示和手机屏幕同样的宽高比。 */
        int width = 0;
        int height = 0;
        String app;
        boolean forceStop;
    }

    private final Link link;
    private final InputInjector injector;
    private final Params params;

    private volatile boolean stopped;
    private volatile boolean syncRequested;
    private volatile int[] pendingResize;
    private volatile boolean screenOff;
    /** 独立显示当前的尺寸（显示器本身的朝向，不是系统旋转之后的）。 */
    private volatile int currentWidth;
    private volatile int currentHeight;
    private volatile long resizedAt;
    private Thread thread;

    private VirtualDisplay newDisplay;
    private volatile int newDisplayId = -1;

    ScreenMirror(Link link, InputInjector injector, Params params) {
        this.link = link;
        this.injector = injector;
        this.params = params;
    }

    void start() {
        thread = new Thread(this::run, "mirror");
        thread.start();
    }

    void stop() {
        stopped = true;
        Thread t = thread;
        if (t != null && t != Thread.currentThread()) {
            try {
                t.join(4000);
            } catch (InterruptedException ignored) {
            }
        }
    }

    /** 请求一个关键帧。App 丢包后用来让 Mac 尽快恢复画面。 */
    void requestSync() {
        syncRequested = true;
    }

    /** 独立显示模式：调整虚拟显示器的尺寸。应用会按新尺寸重新排版。 */
    void requestResize(int width, int height) {
        if (params.mode == MODE_NEW) pendingResize = new int[] {width, height};
    }

    /** 物理屏幕当前是不是被关掉的。打开应用可能会把它点亮，所以打开之后要再关一次。 */
    void setScreenOff(boolean off) {
        screenOff = off;
    }

    /** 打开应用：独立显示模式开在虚拟显示器上，镜像模式开在被镜像的显示器（手机屏幕）上。 */
    void launch(String pkg, boolean forceStop) {
        new Thread(() -> {
            JSONObject event = new JSONObject();
            try {
                event.put("t", "launched");
                event.put("pkg", pkg);
                int id = params.mode == MODE_NEW ? newDisplayId : params.displayId;
                if (id < 0) throw new IllegalStateException("no display");
                if (params.mode == MODE_NEW) resetToPortrait();
                Intent launchIntent = Hidden.context().getPackageManager().getLaunchIntentForPackage(pkg);
                if (launchIntent == null || launchIntent.getComponent() == null) throw new IllegalStateException("no launcher activity");
                ComponentName component = launchIntent.getComponent();
                if (forceStop) exec("am", "force-stop", pkg);
                String output = exec("am", "start", "--display", String.valueOf(id), "-n", component.flattenToShortString());
                boolean ok = !output.contains("Error") && !output.contains("Exception");
                event.put("ok", ok);
                if (!ok) event.put("message", output.trim());
            } catch (Throwable t) {
                try {
                    event.put("ok", false);
                    event.put("message", String.valueOf(t));
                } catch (Exception ignored) {
                }
            }
            try {
                link.sendJson(event);
            } catch (Exception ignored) {
            }
            keepScreenOff();
        }, "launch").start();
    }

    /** 应用启动时系统可能点亮屏幕（有的应用要求亮屏），稍等一下再关一次。 */
    private void keepScreenOff() {
        if (!screenOff || params.mode != MODE_MIRROR) return;
        try {
            Thread.sleep(700);
        } catch (InterruptedException ignored) {
        }
        if (screenOff && !stopped) Hidden.setPanelPower(false);
    }

    private static String exec(String... command) throws Exception {
        Process process = new ProcessBuilder(command).redirectErrorStream(true).start();
        StringBuilder output = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) output.append(line).append('\n');
        }
        if (!process.waitFor(8, TimeUnit.SECONDS)) process.destroyForcibly();
        return output.toString();
    }

    private void run() {
        try {
            if (params.mode == MODE_NEW) runNewDisplay(); else runMirror();
        } catch (Throwable t) {
            Log.e("mirror failed", t);
            try {
                JSONObject event = new JSONObject();
                event.put("t", "error");
                event.put("message", String.valueOf(t));
                link.sendJson(event);
            } catch (Exception ignored) {
            }
        } finally {
            if (newDisplay != null) {
                newDisplay.release();
                newDisplay = null;
            }
            // 只在自己结束（出错）时通知 App。被主动停止时不发：旧会话的 stopped 会在新会话登记监听之后才到，
            // 导致 App 误把新会话当成结束了。
            if (!stopped) {
                try {
                    JSONObject event = new JSONObject();
                    event.put("t", "stopped");
                    link.sendJson(event);
                } catch (Exception ignored) {
                }
            }
        }
    }

    // ---- 编码器 ----

    private static final class Encoder {
        MediaCodec codec;
        Surface surface;
    }

    private Encoder createEncoder(int width, int height) throws Exception {
        Encoder encoder = new Encoder();
        encoder.codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
        MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height);
        format.setInteger(MediaFormat.KEY_BIT_RATE, params.bitRate);
        // 必须设置才能配置编码器，不影响实际帧率（帧率由屏幕刷新决定，可变）
        format.setInteger(MediaFormat.KEY_FRAME_RATE, 60);
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
        format.setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED);
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL_SECONDS);
        // 画面静止时也定期重复上一帧：让第一帧立刻出来，也让质量能恢复
        format.setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, REPEAT_FRAME_DELAY_US);
        format.setInteger(MediaFormat.KEY_PRIORITY, 0); // 实时
        format.setInteger(MediaFormat.KEY_LATENCY, 1);
        if (params.maxFps > 0) format.setFloat("max-fps-to-encoder", params.maxFps);
        encoder.codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        encoder.surface = encoder.codec.createInputSurface();
        encoder.codec.start();
        return encoder;
    }

    private static void release(Encoder encoder) {
        try {
            encoder.codec.stop();
        } catch (Throwable ignored) {
        }
        encoder.codec.release();
        if (encoder.surface != null) encoder.surface.release();
    }

    private interface ShapeCheck {
        /** 返回 true 表示需要重建编码器。 */
        boolean changed() throws Exception;
    }

    private void encodeLoop(MediaCodec codec, ShapeCheck check) throws Exception {
        MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
        byte[] scratch = new byte[256 * 1024];
        long lastCheck = System.currentTimeMillis();
        while (!stopped) {
            int index = codec.dequeueOutputBuffer(bufferInfo, 40_000);
            if (index >= 0) {
                try {
                    if (bufferInfo.size > 0) {
                        ByteBuffer buffer = codec.getOutputBuffer(index);
                        buffer.position(bufferInfo.offset);
                        buffer.limit(bufferInfo.offset + bufferInfo.size);
                        if (scratch.length < bufferInfo.size) scratch = new byte[bufferInfo.size];
                        buffer.get(scratch, 0, bufferInfo.size);
                        int flags = 0;
                        if ((bufferInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) flags |= Link.FLAG_CONFIG;
                        if ((bufferInfo.flags & MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0) flags |= Link.FLAG_KEY;
                        link.sendVideo(flags, bufferInfo.presentationTimeUs, scratch, bufferInfo.size);
                    }
                } finally {
                    codec.releaseOutputBuffer(index, false);
                }
                if ((bufferInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return;
            }
            if (syncRequested) {
                syncRequested = false;
                Bundle requestParams = new Bundle();
                requestParams.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0);
                codec.setParameters(requestParams);
            }
            long now = System.currentTimeMillis();
            if (pendingResize != null) return; // 独立显示模式：Mac 请求了新尺寸
            if (now - lastCheck > 400) {
                lastCheck = now;
                if (check != null && check.changed()) return;
            }
        }
    }

    private void sendShape(String type, int width, int height, int deviceWidth, int deviceHeight, int rotation) throws Exception {
        JSONObject event = new JSONObject();
        event.put("t", type);
        event.put("mode", params.mode);
        event.put("width", width);
        event.put("height", height);
        event.put("deviceWidth", deviceWidth);
        event.put("deviceHeight", deviceHeight);
        event.put("rotation", rotation);
        event.put("displayId", params.mode == MODE_NEW ? newDisplayId : params.displayId);
        link.sendJson(event);
    }

    // ---- 独立显示 ----

    /** 之前被横屏应用转成横向的话，开新的应用前先还原成竖向：多数应用不指定方向，会沿用当前方向。 */
    private void resetToPortrait() throws InterruptedException {
        if (currentWidth <= currentHeight) return;
        pendingResize = new int[] {currentHeight, currentWidth};
        for (int i = 0; i < 20 && currentWidth > currentHeight && !stopped; i++) Thread.sleep(100);
    }

    /**
     * 应用请求横屏（比如全屏看视频）时，系统会把虚拟显示器旋转，画面就是侧着的。
     * 这时把显示器本身改成横向（宽高对调），系统就不用再旋转；应用切回竖屏时同理。返回 true 表示需要重建编码器。
     */
    private boolean orientationMismatch() throws Exception {
        if (System.currentTimeMillis() - resizedAt < 1200) return false; // 刚改过尺寸，等系统更新
        Hidden.DisplayInfo info = Hidden.displayInfo(newDisplayId);
        if ((info.width > info.height) == (currentWidth > currentHeight)) return false;
        Log.d("orientation follows content: " + currentWidth + "x" + currentHeight + " -> " + currentHeight + "x" + currentWidth
                + " (system " + info.width + "x" + info.height + " rotation=" + info.rotation + ")");
        pendingResize = new int[] {currentHeight, currentWidth};
        return true;
    }

    /** 独立显示的初始尺寸：没有指定时用手机屏幕的宽高比，竖向。 */
    private int[] initialSize() throws Exception {
        int width = params.width;
        int height = params.height;
        if (width <= 0 || height <= 0) {
            Hidden.DisplayInfo main = Hidden.displayInfo(0);
            width = Math.min(main.width, main.height);
            height = Math.max(main.width, main.height);
        }
        return sanitize(width, height, params.maxSize);
    }

    private void runNewDisplay() throws Exception {
        int[] size = initialSize();
        boolean first = true;
        while (!stopped) {
            int width = size[0];
            int height = size[1];
            int dpi = dpiFor(width, height);
            Log.d("new display " + width + "x" + height + " dpi=" + dpi);
            currentWidth = width;
            currentHeight = height;
            resizedAt = System.currentTimeMillis();
            Encoder encoder = createEncoder(width, height);
            try {
                if (newDisplay == null) {
                    newDisplay = Hidden.createNewVirtualDisplay("LinkToMacOS", width, height, dpi, encoder.surface);
                    newDisplayId = newDisplay.getDisplay().getDisplayId();
                    Hidden.setDisplayImePolicy(newDisplayId, IME_POLICY_HIDE);
                    Log.d("virtual display id=" + newDisplayId);
                } else {
                    // 同一个虚拟显示器改尺寸：上面的应用继续运行，只是重新排版
                    newDisplay.resize(width, height, dpi);
                    newDisplay.setSurface(encoder.surface);
                }
                injector.setTarget(newDisplayId, width, height);
                sendShape(first ? "started" : "resized", width, height, width, height, 0);
                if (first && params.app != null && !params.app.isEmpty()) launch(params.app, params.forceStop);
                first = false;
                pendingResize = null;
                encodeLoop(encoder.codec, this::orientationMismatch);
            } finally {
                release(encoder);
            }
            int[] requested = pendingResize;
            if (requested != null) size = sanitize(requested[0], requested[1], params.maxSize);
        }
    }

    /** 让应用看到的“dp 宽度”和手机本身相近：按短边比例缩放主屏的 dpi。 */
    private static int dpiFor(int width, int height) {
        try {
            Hidden.DisplayInfo main = Hidden.displayInfo(0);
            double ratio = (double) Math.min(width, height) / Math.min(main.width, main.height);
            return (int) Math.max(120, Math.min(640, Math.round(main.densityDpi * ratio)));
        } catch (Throwable t) {
            return 420;
        }
    }

    // ---- 镜像手机主屏 ----

    private void runMirror() throws Exception {
        boolean first = true;
        while (!stopped) {
            Hidden.DisplayInfo info = Hidden.displayInfo(params.displayId);
            int[] size = fit(info.width, info.height, params.maxSize);
            Log.d("capture " + info.width + "x" + info.height + " rot=" + info.rotation + " -> " + size[0] + "x" + size[1]);
            injector.setTarget(params.displayId, info.width, info.height);
            Encoder encoder = createEncoder(size[0], size[1]);
            VirtualDisplay virtualDisplay = null;
            try {
                virtualDisplay = Hidden.createVirtualDisplay("LinkToMacOS", size[0], size[1], params.displayId, encoder.surface);
                sendShape(first ? "started" : "resized", size[0], size[1], info.width, info.height, info.rotation);
                if (first && params.app != null && !params.app.isEmpty()) launch(params.app, params.forceStop);
                first = false;
                final Hidden.DisplayInfo shape = info;
                encodeLoop(encoder.codec, () -> !shape.sameShape(Hidden.displayInfo(params.displayId)));
            } finally {
                if (virtualDisplay != null) virtualDisplay.release();
                release(encoder);
            }
        }
    }

    // ---- 尺寸 ----

    /** 长边不超过 maxSize，宽高取 8 的倍数（硬件编码器的常见要求）。 */
    static int[] fit(int width, int height, int maxSize) {
        double scale = 1;
        int longEdge = Math.max(width, height);
        if (maxSize > 0 && longEdge > maxSize) scale = (double) maxSize / longEdge;
        return new int[] {align((int) Math.round(width * scale)), align((int) Math.round(height * scale))};
    }

    /** 独立显示的尺寸：每边不小于 MIN_SIDE，长边不超过 maxSize，按 8 对齐。 */
    static int[] sanitize(int width, int height, int maxSize) {
        int[] size = fit(Math.max(MIN_SIDE, width), Math.max(MIN_SIDE, height), maxSize);
        return new int[] {Math.max(MIN_SIDE, size[0]), Math.max(MIN_SIDE, size[1])};
    }

    private static int align(int value) {
        return Math.max(ALIGN, (value + ALIGN / 2) / ALIGN * ALIGN);
    }
}
