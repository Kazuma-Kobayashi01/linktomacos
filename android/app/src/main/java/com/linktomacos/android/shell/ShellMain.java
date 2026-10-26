package com.linktomacos.android.shell;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.os.Build;
import android.os.Looper;

import org.json.JSONObject;

import java.io.IOException;
import java.lang.reflect.Field;

/**
 * 以 shell 身份运行的常驻服务，由 Mac 通过 USB 启动一次：
 *
 *   app_process -Djava.class.path=<APK 路径> /system/bin com.linktomacos.android.shell.ShellMain --port 47153 --secret <hex>
 *
 * 之后拔掉数据线也继续运行，直到手机重启。它反复连接手机 App 的本机端口（127.0.0.1），握手通过后接受指令：
 * 开始/停止投屏、请求关键帧、注入输入、开关物理屏幕。加上 {@code --selftest} 只检查系统接口是否可用，不会读屏或注入；{@code --audio-selftest} 检查音频捕获（会录 1.5 秒系统混音，并播一个低音量提示音）。
 */
public final class ShellMain {
    /** 服务的版本。改了服务的行为就要加 1：App 发现连上来的服务版本不对，会要求重新启动它（EnhancedBridge.SHELL_VERSION 要同步）。 */
    static final int VERSION = 5;

    private ShellMain() {}

    public static void main(String[] args) {
        int port = 47153;
        byte[] secret = null;
        boolean selftest = false;
        boolean audioSelftest = false;
        boolean micSelftest = false;
        boolean clipSelftest = false;
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--port": port = Integer.parseInt(args[++i]); break;
                case "--secret": secret = Link.fromHex(args[++i]); break;
                case "--selftest": selftest = true; break;
                case "--audio-selftest": audioSelftest = true; break;
                case "--mic-selftest": micSelftest = true; break;
                case "--clip-selftest": clipSelftest = true; break;
                default: break;
            }
        }
        final int finalPort = port;
        final byte[] finalSecret = secret;
        try {
            prepareMainLooper();
            Hidden.init();
            if (selftest) {
                System.exit(selftest() ? 0 : 1);
                return;
            }
            if (audioSelftest) {
                System.exit(AudioProbe.run() ? 0 : 1);
                return;
            }
            if (micSelftest) {
                System.exit(MicProbe.run() ? 0 : 1);
                return;
            }
            if (clipSelftest) {
                System.exit(clipSelftest() ? 0 : 1);
                return;
            }
            if (finalSecret == null) {
                Log.d("missing --secret");
                System.exit(2);
                return;
            }
            Log.d("linktomacos shell server v" + VERSION + " started, uid=" + android.os.Process.myUid() + " sdk=" + Hidden.sdk());
            Thread worker = new Thread(() -> serve(finalPort, finalSecret), "serve");
            worker.start();
            Looper.loop();
        } catch (Throwable t) {
            Log.e("fatal", t);
            System.exit(1);
        }
    }

    /** 和 Looper.prepareMainLooper() 一样，但允许退出。部分系统服务回调需要主线程 Looper。 */
    @SuppressWarnings({"JavaReflectionMemberAccess", "DiscouragedPrivateApi"})
    private static void prepareMainLooper() throws Exception {
        Looper.prepare();
        synchronized (Looper.class) {
            Field field = Looper.class.getDeclaredField("sMainLooper");
            field.setAccessible(true);
            field.set(null, Looper.myLooper());
        }
    }

    private static void serve(int port, byte[] secret) {
        InputInjector injector = new InputInjector();
        while (true) {
            Link link = null;
            ScreenMirror mirror = null;
            AudioCapture audio = null;
            MicInjector mic = null;
            ClipboardWatcher clipboard = null;
            boolean screenOff = false;
            try {
                link = Link.connect(port, secret);
                Log.d("connected to app");
                while (true) {
                    JSONObject command = link.readCommand();
                    switch (command.optString("t")) {
                        case "start": {
                            if (mirror != null) mirror.stop();
                            if (audio != null) audio.stop();
                            audio = null;
                            mic = stopMic(link, mic);
                            ScreenMirror.Params params = new ScreenMirror.Params();
                            params.mode = command.optString("mode", "new").equals("mirror") ? ScreenMirror.MODE_MIRROR : ScreenMirror.MODE_NEW;
                            params.displayId = command.optInt("display", 0);
                            params.maxSize = command.optInt("maxSize", 1920);
                            params.bitRate = command.optInt("bitRate", 8_000_000);
                            params.maxFps = command.optInt("fps", 60);
                            params.width = command.optInt("width", 0);
                            params.height = command.optInt("height", 0);
                            params.app = command.optString("app", "");
                            params.forceStop = command.optBoolean("forceStop", false);
                            mirror = new ScreenMirror(link, injector, params);
                            mirror.setScreenOff(screenOff);
                            mirror.start();
                            if (command.optBoolean("audio", false)) {
                                audio = new AudioCapture(link);
                                audio.start();
                            }
                            if (command.optBoolean("mic", false)) mic = startMic(link);
                            break;
                        }
                        case "resize":
                            if (mirror != null) mirror.requestResize(command.optInt("width"), command.optInt("height"));
                            break;
                        case "launch":
                            if (mirror != null) mirror.launch(command.optString("pkg"), command.optBoolean("forceStop", false));
                            break;
                        case "stop":
                            if (mirror != null) mirror.stop();
                            mirror = null;
                            if (audio != null) audio.stop();
                            audio = null;
                            mic = stopMic(link, mic);
                            // 投屏结束时把物理屏幕还给用户
                            if (screenOff) {
                                Hidden.setPanelPower(true);
                                screenOff = false;
                            }
                            break;
                        case "sync":
                            if (mirror != null) mirror.requestSync();
                            break;
                        case "input":
                            injector.handle(command);
                            break;
                        case "clip": {
                            // App 开关剪贴板互通：on=true 开始监听手机上的复制
                            try {
                                if (clipboard == null) clipboard = new ClipboardWatcher(link);
                                if (command.optBoolean("on", false)) clipboard.start(); else clipboard.stop();
                            } catch (Throwable t) {
                                Log.e("clipboard unavailable", t);
                                link.sendJson(new JSONObject().put("t", "clipError").put("message", String.valueOf(t)));
                            }
                            break;
                        }
                        case "clipSet":
                            try {
                                if (clipboard == null) clipboard = new ClipboardWatcher(link);
                                String text = command.optString("text", "");
                                if (!text.isEmpty()) clipboard.set(text);
                            } catch (Throwable t) {
                                Log.e("clipboard write failed", t);
                            }
                            break;
                        case "screen":
                            screenOff = !command.optBoolean("on", true);
                            if (mirror != null) mirror.setScreenOff(screenOff);
                            if (!Hidden.setPanelPower(!screenOff)) Log.d("screen power change failed");
                            break;
                        default:
                            break;
                    }
                }
            } catch (IOException e) {
                // 连不上或断开：App 没在运行或已重启，稍后重试
            } catch (Throwable t) {
                Log.e("session error", t);
            } finally {
                if (mirror != null) mirror.stop();
                if (audio != null) audio.stop();
                if (link != null) stopMic(link, mic);
                if (clipboard != null) clipboard.stop();
                if (screenOff) Hidden.setPanelPower(true); // 无论如何都要把物理屏幕还给用户
                if (link != null) link.close();
            }
            try {
                Thread.sleep(1000);
            } catch (InterruptedException ignored) {
            }
        }
    }

    /** 开始注入 Mac 麦克风的声音。失败时通知 App（不影响投屏），返回 null。 */
    private static MicInjector startMic(Link link) {
        MicInjector injector = new MicInjector();
        try {
            injector.start();
        } catch (Throwable t) {
            Log.e("mic injection failed", t);
            try {
                link.sendJson(new JSONObject().put("t", "micError").put("message", String.valueOf(t)));
            } catch (Exception ignored) {
            }
            return null;
        }
        link.micSink = injector::write;
        return injector;
    }

    private static MicInjector stopMic(Link link, MicInjector injector) {
        link.micSink = null;
        if (injector != null) injector.stop();
        return null;
    }

    /** 检查剪贴板读取是否可行。只读，不写入，也不打印剪贴板内容，只报告长度。 */
    private static boolean clipSelftest() {
        try {
            ClipboardWatcher watcher = new ClipboardWatcher(null);
            Log.d("OK   clipboard readable from shell uid, current text length: " + watcher.peekLength());
            watcher.start();
            watcher.stop();
            Log.d("OK   clipboard listener register/unregister");
            Log.d("selftest PASSED");
            return true;
        } catch (Throwable t) {
            Log.e("FAIL clipboard", t);
            return false;
        }
    }

    /** 检查所有要用到的系统接口。只读，不创建虚拟显示器，不注入任何事件。 */
    private static boolean selftest() {
        boolean ok = true;
        Log.d("selftest: sdk=" + Build.VERSION.SDK_INT + " " + Build.MANUFACTURER + " " + Build.MODEL + " uid=" + android.os.Process.myUid());
        try {
            Hidden.DisplayInfo info = Hidden.displayInfo(0);
            Log.d("OK   display 0: " + info.width + "x" + info.height + " rotation=" + info.rotation + " dpi=" + info.densityDpi);
        } catch (Throwable t) {
            ok = false;
            Log.d("FAIL display info: " + t);
        }
        try {
            Hidden.createVirtualDisplayMethod();
            Log.d("OK   DisplayManager.createVirtualDisplay(name,w,h,displayId,surface)");
        } catch (Throwable t) {
            ok = false;
            Log.d("FAIL createVirtualDisplay: " + t);
        }
        try {
            Hidden.injectInputEventMethod();
            Log.d("OK   InputManager.injectInputEvent");
        } catch (Throwable t) {
            ok = false;
            Log.d("FAIL injectInputEvent: " + t);
        }
        try {
            android.view.InputEvent.class.getMethod("setDisplayId", int.class);
            Log.d("OK   InputEvent.setDisplayId");
        } catch (Throwable t) {
            Log.d("WARN setDisplayId (only needed for secondary displays): " + t);
        }
        try {
            int count = Hidden.panelPowerSelfTest();
            Log.d("OK   SurfaceControl.setDisplayPowerMode (turn the panel off while mirroring), physical displays: " + count);
        } catch (Throwable t) {
            Log.d("WARN panel power unavailable: " + t);
        }
        try {
            String encoder = null;
            for (MediaCodecInfo codec : new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos()) {
                if (!codec.isEncoder()) continue;
                for (String type : codec.getSupportedTypes()) {
                    if (type.equalsIgnoreCase("video/avc")) {
                        encoder = codec.getName();
                        break;
                    }
                }
                if (encoder != null) break;
            }
            if (encoder == null) throw new IOException("no video/avc encoder");
            Log.d("OK   H.264 encoder: " + encoder);
        } catch (Throwable t) {
            ok = false;
            Log.d("FAIL encoder: " + t);
        }
        Log.d(ok ? "selftest PASSED" : "selftest FAILED");
        return ok;
    }
}
