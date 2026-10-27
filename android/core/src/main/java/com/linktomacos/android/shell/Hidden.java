package com.linktomacos.android.shell;

import android.annotation.SuppressLint;
import android.app.Application;
import android.app.Instrumentation;
import android.content.AttributionSource;
import android.content.Context;
import android.content.ContextWrapper;
import android.hardware.display.VirtualDisplay;
import android.os.Build;
import android.os.IBinder;
import android.os.Process;
import android.view.InputEvent;
import android.view.Surface;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * 在 shell 进程里访问系统内部接口（读屏、注入输入）所需的反射封装。
 *
 * 做法参考 scrcpy（Apache-2.0，https://github.com/Genymobile/scrcpy）：在没有 App 上下文的 app_process
 * 里伪造 ActivityThread 和系统上下文，之后才能使用 DisplayManagerGlobal、InputManager 等。
 */
@SuppressLint({"PrivateApi", "BlockedPrivateApi", "SoonBlockedPrivateApi", "DiscouragedPrivateApi"})
final class Hidden {
    static final String PACKAGE = "com.android.shell";

    static final class DisplayInfo {
        int width;
        int height;
        int rotation;
        int layerStack;
        int flags;
        int densityDpi;

        boolean sameShape(DisplayInfo other) {
            return other != null && width == other.width && height == other.height && rotation == other.rotation;
        }
    }

    private static Class<?> activityThreadClass;
    private static Object activityThread;
    private static Context context;
    private static Object displayManagerGlobal;
    private static Method getDisplayInfoMethod;
    private static Method createVirtualDisplayMethod;
    private static Object inputManager;
    private static Method injectInputEventMethod;
    private static Method setDisplayIdMethod;

    private Hidden() {}

    /** 伪造的上下文：包名是 com.android.shell，权限检查按 shell 身份。 */
    private static final class ShellContext extends ContextWrapper {
        ShellContext(Context base) {
            super(base);
        }

        @Override
        public String getPackageName() {
            return PACKAGE;
        }

        @Override
        public String getOpPackageName() {
            return PACKAGE;
        }

        @Override
        public AttributionSource getAttributionSource() {
            AttributionSource.Builder builder = new AttributionSource.Builder(Process.SHELL_UID);
            builder.setPackageName(PACKAGE);
            return builder.build();
        }

        @SuppressWarnings("unused")
        public int getDeviceId() {
            return 0;
        }

        @Override
        public Context getApplicationContext() {
            return this;
        }

        @Override
        public Context createPackageContext(String packageName, int flags) {
            return this;
        }
    }

    static synchronized void init() throws Exception {
        if (context != null) return;
        activityThreadClass = Class.forName("android.app.ActivityThread");
        Constructor<?> constructor = activityThreadClass.getDeclaredConstructor();
        constructor.setAccessible(true);
        activityThread = constructor.newInstance();

        Field current = activityThreadClass.getDeclaredField("sCurrentActivityThread");
        current.setAccessible(true);
        current.set(null, activityThread);
        Field systemThread = activityThreadClass.getDeclaredField("mSystemThread");
        systemThread.setAccessible(true);
        systemThread.setBoolean(activityThread, true);

        // 部分三星机型的 DisplayManagerGlobal 会读 ConfigurationController，必须先补上
        fillConfigurationController();
        fillAppInfo();

        Method getSystemContext = activityThreadClass.getDeclaredMethod("getSystemContext");
        context = new ShellContext((Context) getSystemContext.invoke(activityThread));
        try {
            Application app = Instrumentation.newApplication(Application.class, context);
            Field initialApplication = activityThreadClass.getDeclaredField("mInitialApplication");
            initialApplication.setAccessible(true);
            initialApplication.set(activityThread, app);
        } catch (Throwable t) {
            Log.d("fillAppContext failed: " + t);
        }
    }

    private static void fillConfigurationController() {
        try {
            Class<?> controllerClass = Class.forName("android.app.ConfigurationController");
            Class<?> internalClass = Class.forName("android.app.ActivityThreadInternal");
            Constructor<?> constructor = controllerClass.getDeclaredConstructor(internalClass);
            constructor.setAccessible(true);
            Object controller = constructor.newInstance(activityThread);
            Field field = activityThreadClass.getDeclaredField("mConfigurationController");
            field.setAccessible(true);
            field.set(activityThread, controller);
        } catch (Throwable t) {
            Log.d("fillConfigurationController failed: " + t);
        }
    }

    private static void fillAppInfo() {
        try {
            Class<?> bindDataClass = Class.forName("android.app.ActivityThread$AppBindData");
            Constructor<?> constructor = bindDataClass.getDeclaredConstructor();
            constructor.setAccessible(true);
            Object bindData = constructor.newInstance();
            android.content.pm.ApplicationInfo info = new android.content.pm.ApplicationInfo();
            info.packageName = PACKAGE;
            Field appInfo = bindDataClass.getDeclaredField("appInfo");
            appInfo.setAccessible(true);
            appInfo.set(bindData, info);
            Field bound = activityThreadClass.getDeclaredField("mBoundApplication");
            bound.setAccessible(true);
            bound.set(activityThread, bindData);
        } catch (Throwable t) {
            Log.d("fillAppInfo failed: " + t);
        }
    }

    // ---- 显示 ----

    private static synchronized Object displayManagerGlobal() throws Exception {
        if (displayManagerGlobal == null) {
            Class<?> clazz = Class.forName("android.hardware.display.DisplayManagerGlobal");
            displayManagerGlobal = clazz.getDeclaredMethod("getInstance").invoke(null);
        }
        return displayManagerGlobal;
    }

    static synchronized DisplayInfo displayInfo(int displayId) throws Exception {
        Object dmg = displayManagerGlobal();
        if (getDisplayInfoMethod == null) {
            getDisplayInfoMethod = dmg.getClass().getMethod("getDisplayInfo", int.class);
        }
        Object info = getDisplayInfoMethod.invoke(dmg, displayId);
        if (info == null) throw new IllegalStateException("display " + displayId + " not found");
        Class<?> cls = info.getClass();
        DisplayInfo result = new DisplayInfo();
        // logicalWidth/Height 已经考虑了旋转
        result.width = cls.getDeclaredField("logicalWidth").getInt(info);
        result.height = cls.getDeclaredField("logicalHeight").getInt(info);
        result.rotation = cls.getDeclaredField("rotation").getInt(info);
        result.layerStack = cls.getDeclaredField("layerStack").getInt(info);
        result.flags = cls.getDeclaredField("flags").getInt(info);
        result.densityDpi = cls.getDeclaredField("logicalDensityDpi").getInt(info);
        return result;
    }

    static Method createVirtualDisplayMethod() throws Exception {
        if (createVirtualDisplayMethod == null) {
            createVirtualDisplayMethod = android.hardware.display.DisplayManager.class.getMethod(
                    "createVirtualDisplay", String.class, int.class, int.class, int.class, Surface.class);
        }
        return createVirtualDisplayMethod;
    }

    /** 镜像 {@code displayIdToMirror} 的内容到 surface。不需要用户授权，shell 身份自带 CAPTURE_VIDEO_OUTPUT。 */
    static VirtualDisplay createVirtualDisplay(String name, int width, int height, int displayIdToMirror, Surface surface)
            throws Exception {
        return (VirtualDisplay) createVirtualDisplayMethod().invoke(null, name, width, height, displayIdToMirror, surface);
    }

    private static final int POWER_MODE_OFF = 0;
    private static final int POWER_MODE_NORMAL = 2;
    private static Class<?> displayControlClass;

    /**
     * 只开关物理屏幕的面板。系统里的显示器仍然是开着的，内容继续渲染，镜像和触摸都不受影响。
     * 不用 DisplayManagerGlobal.requestDisplayPower：它把整个显示器置为关闭状态，镜像画面会冻住
     * （scrcpy 也因此不用它，见 scrcpy issue 5530）。
     */
    static boolean setPanelPower(boolean on) {
        try {
            Class<?> surfaceControl = Class.forName("android.view.SurfaceControl");
            Class<?> source = hasMethod(surfaceControl, "getPhysicalDisplayIds") ? surfaceControl : displayControl();
            long[] ids = (long[]) source.getMethod("getPhysicalDisplayIds").invoke(null);
            if (ids == null || ids.length == 0) return false;
            Method getToken = source.getMethod("getPhysicalDisplayToken", long.class);
            Method setMode = surfaceControl.getMethod("setDisplayPowerMode", IBinder.class, int.class);
            int mode = on ? POWER_MODE_NORMAL : POWER_MODE_OFF;
            for (long id : ids) setMode.invoke(null, getToken.invoke(null, id), mode);
            return true;
        } catch (Throwable t) {
            Log.d("setPanelPower failed: " + t);
            return false;
        }
    }

    /** 只检查接口在不在、能不能取到物理显示器，不改变屏幕状态。 */
    static int panelPowerSelfTest() throws Exception {
        Class<?> surfaceControl = Class.forName("android.view.SurfaceControl");
        Class<?> source = hasMethod(surfaceControl, "getPhysicalDisplayIds") ? surfaceControl : displayControl();
        long[] ids = (long[]) source.getMethod("getPhysicalDisplayIds").invoke(null);
        source.getMethod("getPhysicalDisplayToken", long.class);
        surfaceControl.getMethod("setDisplayPowerMode", IBinder.class, int.class);
        return ids == null ? 0 : ids.length;
    }

    private static boolean hasMethod(Class<?> cls, String name) {
        for (Method method : cls.getMethods()) {
            if (method.getName().equals(name)) return true;
        }
        return false;
    }

    /** Android 14 起，这些接口搬到了系统服务进程里的 DisplayControl，需要用系统服务的类路径加载。 */
    private static Class<?> displayControl() throws Exception {
        if (displayControlClass == null) {
            Class<?> factory = Class.forName("com.android.internal.os.ClassLoaderFactory");
            Method create = factory.getDeclaredMethod("createClassLoader", String.class, String.class, String.class,
                    ClassLoader.class, int.class, boolean.class, String.class);
            ClassLoader loader = (ClassLoader) create.invoke(null, System.getenv("SYSTEMSERVERCLASSPATH"), null, null,
                    ClassLoader.getSystemClassLoader(), 0, true, null);
            Class<?> cls = loader.loadClass("com.android.server.display.DisplayControl");
            Method loadLibrary = Runtime.class.getDeclaredMethod("loadLibrary0", Class.class, String.class);
            loadLibrary.setAccessible(true);
            loadLibrary.invoke(Runtime.getRuntime(), cls, "android_servers");
            displayControlClass = cls;
        }
        return displayControlClass;
    }

    static Context context() throws Exception {
        init();
        return context;
    }

    // 虚拟显示器的标志位（部分是系统内部的，DisplayManager 里没有公开常量）
    private static final int FLAG_PUBLIC = 1 << 0;
    private static final int FLAG_PRESENTATION = 1 << 1;
    private static final int FLAG_OWN_CONTENT_ONLY = 1 << 3;
    private static final int FLAG_SUPPORTS_TOUCH = 1 << 6;
    private static final int FLAG_ROTATES_WITH_CONTENT = 1 << 7;
    private static final int FLAG_DESTROY_CONTENT_ON_REMOVAL = 1 << 8;
    private static final int FLAG_TRUSTED = 1 << 10;
    private static final int FLAG_OWN_DISPLAY_GROUP = 1 << 11;
    private static final int FLAG_ALWAYS_UNLOCKED = 1 << 12;
    private static final int FLAG_TOUCH_FEEDBACK_DISABLED = 1 << 13;
    private static final int FLAG_OWN_FOCUS = 1 << 14;
    private static final int FLAG_DEVICE_DISPLAY_GROUP = 1 << 15;

    /**
     * 新建一个独立的虚拟显示器（不是镜像）。应用可以开在它上面，手机自己的屏幕可以关掉或锁屏，互不影响。
     * 标志位参考 scrcpy 的 --new-display：可信、独立显示组、始终解锁、独立焦点，移除时销毁上面的内容。
     */
    @SuppressLint("WrongConstant") // 标志位里有系统内部的（不在公开的 IntDef 里）
    static VirtualDisplay createNewVirtualDisplay(String name, int width, int height, int dpi, Surface surface) throws Exception {
        init();
        int flags = FLAG_PUBLIC | FLAG_PRESENTATION | FLAG_OWN_CONTENT_ONLY | FLAG_SUPPORTS_TOUCH | FLAG_ROTATES_WITH_CONTENT
                | FLAG_DESTROY_CONTENT_ON_REMOVAL | FLAG_TRUSTED | FLAG_OWN_DISPLAY_GROUP | FLAG_ALWAYS_UNLOCKED
                | FLAG_TOUCH_FEEDBACK_DISABLED | FLAG_OWN_FOCUS | FLAG_DEVICE_DISPLAY_GROUP;
        Constructor<android.hardware.display.DisplayManager> constructor =
                android.hardware.display.DisplayManager.class.getDeclaredConstructor(Context.class);
        constructor.setAccessible(true);
        android.hardware.display.DisplayManager manager = constructor.newInstance(context);
        return manager.createVirtualDisplay(name, width, height, dpi, surface, flags);
    }

    /** 0 = 本显示器显示输入法，1 = 借用主显示器，2 = 不显示。Mac 键盘直接输入，所以设成不显示。 */
    static void setDisplayImePolicy(int displayId, int policy) {
        try {
            Class<?> serviceManager = Class.forName("android.os.ServiceManager");
            Object binder = serviceManager.getDeclaredMethod("getService", String.class).invoke(null, "window");
            Object wm = Class.forName("android.view.IWindowManager$Stub")
                    .getMethod("asInterface", android.os.IBinder.class).invoke(null, binder);
            wm.getClass().getMethod("setDisplayImePolicy", int.class, int.class).invoke(wm, displayId, policy);
        } catch (Throwable t) {
            Log.d("setDisplayImePolicy failed: " + t);
        }
    }

    // ---- 输入 ----

    static synchronized Method injectInputEventMethod() throws Exception {
        if (injectInputEventMethod == null) {
            if (inputManager == null) {
                init();
                inputManager = context.getSystemService(Context.INPUT_SERVICE);
            }
            injectInputEventMethod = android.hardware.input.InputManager.class.getMethod(
                    "injectInputEvent", InputEvent.class, int.class);
        }
        return injectInputEventMethod;
    }

    private static Object inputManager() throws Exception {
        injectInputEventMethod();
        return inputManager;
    }

    static boolean injectInputEvent(InputEvent event, int displayId) {
        try {
            if (displayId != 0) {
                if (setDisplayIdMethod == null) setDisplayIdMethod = InputEvent.class.getMethod("setDisplayId", int.class);
                setDisplayIdMethod.invoke(event, displayId);
            }
            // 0 = INJECT_INPUT_EVENT_MODE_ASYNC
            return (boolean) injectInputEventMethod().invoke(inputManager(), event, 0);
        } catch (Throwable t) {
            Log.e("injectInputEvent failed", t);
            return false;
        }
    }

    static int sdk() {
        return Build.VERSION.SDK_INT;
    }
}
