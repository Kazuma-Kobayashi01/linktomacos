package com.linktomacos.android.shell;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** 标准输出日志。启动脚本把它重定向到 /data/local/tmp/linktomacos-shell.log。 */
final class Log {
    private static final SimpleDateFormat FORMAT = new SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US);

    private Log() {}

    static synchronized void d(String message) {
        System.out.println(FORMAT.format(new Date()) + " " + message);
        System.out.flush();
    }

    static void e(String message, Throwable t) {
        d(message + ": " + t);
        if (t != null) {
            for (StackTraceElement element : t.getStackTrace()) d("    at " + element);
        }
    }
}
