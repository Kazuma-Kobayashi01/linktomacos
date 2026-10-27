# 增强服务（shell 包）：由 app_process 直接按类名启动（ShellMain），内部还通过反射调用系统隐藏接口，整包保留。
-keep class com.linktomacos.android.shell.** { *; }
# 协议消息靠 kotlinx.serialization 生成的序列化器，库自带的规则已处理；这里不再额外保留。
-dontwarn javax.annotation.**
