package com.linktomacos.android.shell;

import android.os.SystemClock;
import android.view.InputDevice;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.MotionEvent;

import org.json.JSONObject;

/** 把 Mac 发来的鼠标键盘事件变成真实的触摸和按键事件注入系统。 */
final class InputInjector {
    private static final int KEYCODE_BACK = 4;
    private static final int KEYCODE_HOME = 3;
    private static final int KEYCODE_APP_SWITCH = 187;
    private static final int KEYCODE_WAKEUP = 224;
    private static final int KEYCODE_POWER = 26;
    private static final int KEYCODE_VOLUME_UP = 24;
    private static final int KEYCODE_VOLUME_DOWN = 25;
    private static final int KEYCODE_NOTIFICATION = 83;

    private final MotionEvent.PointerProperties[] properties = {new MotionEvent.PointerProperties()};
    private final MotionEvent.PointerCoords[] coords = {new MotionEvent.PointerCoords()};

    private volatile int displayId = 0;
    /** 被投显示器的逻辑尺寸（像素）。触摸坐标按它换算。 */
    private volatile int width = 1;
    private volatile int height = 1;
    private long downTime;
    private boolean touching;

    InputInjector() {
        properties[0].id = 0;
        properties[0].toolType = MotionEvent.TOOL_TYPE_FINGER;
    }

    void setTarget(int displayId, int width, int height) {
        this.displayId = displayId;
        this.width = Math.max(1, width);
        this.height = Math.max(1, height);
    }

    synchronized void handle(JSONObject event) {
        switch (event.optString("k")) {
            case "t": // touch：a 0=按下 1=抬起 2=移动，x/y 是 0..1 的相对位置
                touch(event.optInt("a"), (float) event.optDouble("x"), (float) event.optDouble("y"));
                break;
            case "s": // scroll
                scroll((float) event.optDouble("x"), (float) event.optDouble("y"),
                        (float) event.optDouble("h", 0), (float) event.optDouble("v", 0));
                break;
            case "key":
                key(event.optInt("a"), event.optInt("c"), event.optInt("m"));
                break;
            case "text":
                text(event.optString("text"));
                break;
            case "cmd":
                command(event.optString("cmd"));
                break;
            default:
                break;
        }
    }

    private void touch(int action, float nx, float ny) {
        long now = SystemClock.uptimeMillis();
        if (action == MotionEvent.ACTION_DOWN) {
            downTime = now;
            touching = true;
        } else if (!touching) {
            return; // 没有按下就收到移动或抬起，忽略
        }
        if (action == MotionEvent.ACTION_UP) touching = false;
        if (action != MotionEvent.ACTION_DOWN && action != MotionEvent.ACTION_UP && action != MotionEvent.ACTION_MOVE) return;

        MotionEvent.PointerCoords c = coords[0];
        c.x = clamp(nx) * (width - 1);
        c.y = clamp(ny) * (height - 1);
        c.pressure = action == MotionEvent.ACTION_UP ? 0f : 1f;
        c.size = 1f;
        MotionEvent event = MotionEvent.obtain(downTime, now, action, 1, properties, coords, 0, 0, 1f, 1f, 0, 0,
                InputDevice.SOURCE_TOUCHSCREEN, 0);
        Hidden.injectInputEvent(event, displayId);
        event.recycle();
    }

    private void scroll(float nx, float ny, float h, float v) {
        MotionEvent.PointerCoords c = coords[0];
        c.x = clamp(nx) * (width - 1);
        c.y = clamp(ny) * (height - 1);
        c.setAxisValue(MotionEvent.AXIS_HSCROLL, h);
        c.setAxisValue(MotionEvent.AXIS_VSCROLL, v);
        MotionEvent.PointerProperties p = properties[0];
        int previousTool = p.toolType;
        p.toolType = MotionEvent.TOOL_TYPE_MOUSE;
        long now = SystemClock.uptimeMillis();
        MotionEvent event = MotionEvent.obtain(now, now, MotionEvent.ACTION_SCROLL, 1, properties, coords, 0, 0, 1f, 1f, 0, 0,
                InputDevice.SOURCE_MOUSE, 0);
        Hidden.injectInputEvent(event, displayId);
        event.recycle();
        p.toolType = previousTool;
        c.setAxisValue(MotionEvent.AXIS_HSCROLL, 0);
        c.setAxisValue(MotionEvent.AXIS_VSCROLL, 0);
    }

    private void key(int action, int keyCode, int metaState) {
        long now = SystemClock.uptimeMillis();
        KeyEvent event = new KeyEvent(now, now, action, keyCode, 0, metaState, KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0,
                InputDevice.SOURCE_KEYBOARD);
        Hidden.injectInputEvent(event, displayId);
    }

    private void press(int keyCode) {
        key(KeyEvent.ACTION_DOWN, keyCode, 0);
        key(KeyEvent.ACTION_UP, keyCode, 0);
    }

    /** 能用键盘映射表打出来的字符（主要是 ASCII）。其他字符（如中文）目前不支持。 */
    private void text(String text) {
        KeyCharacterMap map = KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD);
        KeyEvent[] events = map.getEvents(text.toCharArray());
        if (events == null) return;
        for (KeyEvent event : events) Hidden.injectInputEvent(event, displayId);
    }

    private void command(String name) {
        switch (name) {
            case "back": press(KEYCODE_BACK); break;
            case "home": press(KEYCODE_HOME); break;
            case "recents": press(KEYCODE_APP_SWITCH); break;
            case "wake": press(KEYCODE_WAKEUP); break;
            case "power": press(KEYCODE_POWER); break;
            case "volumeUp": press(KEYCODE_VOLUME_UP); break;
            case "volumeDown": press(KEYCODE_VOLUME_DOWN); break;
            case "notifications": press(KEYCODE_NOTIFICATION); break;
            default: break;
        }
    }

    private static float clamp(float value) {
        if (Float.isNaN(value)) return 0f;
        return Math.max(0f, Math.min(1f, value));
    }
}
