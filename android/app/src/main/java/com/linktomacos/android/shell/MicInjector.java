package com.linktomacos.android.shell;

import android.annotation.SuppressLint;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaRecorder;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * 把 Mac 麦克风的声音注入手机：手机上任何应用录音（麦克风类的录音预设）时，拿到的都是这里写进去的声音。
 *
 * 做法：注册一个音频策略，里面有一个只匹配麦克风录音的“回环混音”，再往它的 AudioTrack 里写 PCM。
 * 需要 shell 身份持有 MODIFY_AUDIO_ROUTING；接口都是系统内部的，所以全部用反射（在 MicProbe 里验证过可行）。
 * 数据格式：48 kHz、单声道、16 位小端 PCM，任意长度（Mac 发的是每包 20 ms）。
 */
@SuppressLint({"PrivateApi", "DiscouragedPrivateApi", "BlockedPrivateApi", "SoonBlockedPrivateApi", "WrongConstant"})
final class MicInjector {
    static final int SAMPLE_RATE = 48_000;
    /** 待写入的包上限：约 1 秒。写不过来说明声音已经过时，丢最旧的。 */
    private static final int QUEUE_PACKETS = 50;
    private static final int[] PRESETS = {
            MediaRecorder.AudioSource.MIC, MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            MediaRecorder.AudioSource.VOICE_RECOGNITION, MediaRecorder.AudioSource.CAMCORDER,
            MediaRecorder.AudioSource.UNPROCESSED, MediaRecorder.AudioSource.VOICE_PERFORMANCE,
    };

    private final BlockingQueue<byte[]> queue = new ArrayBlockingQueue<>(QUEUE_PACKETS);
    private volatile boolean stopped;
    private AudioManager audioManager;
    private Object policy;
    private AudioTrack track;
    private Thread writer;

    /** 注册策略、创建注入轨道并开始写入线程。失败时抛出异常，调用方记录日志。 */
    void start() throws Exception {
        try {
            Context context = Hidden.context();
            audioManager = context.getSystemService(AudioManager.class);

            Class<?> ruleBuilderClass = Class.forName("android.media.audiopolicy.AudioMixingRule$Builder");
            Class<?> ruleClass = Class.forName("android.media.audiopolicy.AudioMixingRule");
            Class<?> mixBuilderClass = Class.forName("android.media.audiopolicy.AudioMix$Builder");
            Class<?> mixClass = Class.forName("android.media.audiopolicy.AudioMix");
            Class<?> policyBuilderClass = Class.forName("android.media.audiopolicy.AudioPolicy$Builder");
            Class<?> policyClass = Class.forName("android.media.audiopolicy.AudioPolicy");

            Object ruleBuilder = ruleBuilderClass.getConstructor().newInstance();
            int matchCapturePreset = ruleClass.getField("RULE_MATCH_ATTRIBUTE_CAPTURE_PRESET").getInt(null);
            Method addMixRule = ruleBuilderClass.getMethod("addMixRule", int.class, Object.class);
            Method setCapturePreset = AudioAttributes.Builder.class.getMethod("setCapturePreset", int.class);
            for (int preset : PRESETS) {
                AudioAttributes.Builder attributes = new AudioAttributes.Builder();
                setCapturePreset.invoke(attributes, preset);
                addMixRule.invoke(ruleBuilder, matchCapturePreset, attributes.build());
            }
            Object rule = ruleBuilderClass.getMethod("build").invoke(ruleBuilder);

            Object mixBuilder = mixBuilderClass.getConstructor(ruleClass).newInstance(rule);
            mixBuilderClass.getMethod("setFormat", AudioFormat.class).invoke(mixBuilder, new AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build());
            mixBuilderClass.getMethod("setRouteFlags", int.class).invoke(mixBuilder, mixClass.getField("ROUTE_FLAG_LOOP_BACK").getInt(null));
            Object mix = mixBuilderClass.getMethod("build").invoke(mixBuilder);

            Constructor<?> policyBuilderConstructor = policyBuilderClass.getConstructor(Context.class);
            Object policyBuilder = policyBuilderConstructor.newInstance(context);
            policyBuilderClass.getMethod("addMix", mixClass).invoke(policyBuilder, mix);
            Object built = policyBuilderClass.getMethod("build").invoke(policyBuilder);
            int result = (int) AudioManager.class.getMethod("registerAudioPolicy", policyClass).invoke(audioManager, built);
            if (result != 0) throw new IllegalStateException("registerAudioPolicy returned " + result);
            policy = built;

            track = (AudioTrack) policyClass.getMethod("createAudioTrackSource", mixClass).invoke(policy, mix);
            track.play();
        } catch (InvocationTargetException e) {
            release();
            throw e.getCause() instanceof Exception ? (Exception) e.getCause() : e;
        } catch (Exception e) {
            release();
            throw e;
        }
        writer = new Thread(this::writeLoop, "mic-inject");
        writer.start();
        Log.d("mic injection started");
    }

    /** 收到一包 PCM（在读命令的线程上调用，不能阻塞）。 */
    void write(byte[] pcm, int length) {
        if (stopped || length <= 0) return;
        byte[] copy = java.util.Arrays.copyOf(pcm, length);
        while (!queue.offer(copy)) queue.poll(); // 满了就丢最旧的
    }

    void stop() {
        stopped = true;
        Thread t = writer;
        if (t != null && t != Thread.currentThread()) {
            t.interrupt();
            try {
                t.join(1000);
            } catch (InterruptedException ignored) {
            }
        }
        release();
        Log.d("mic injection stopped");
    }

    private void writeLoop() {
        try {
            while (!stopped) {
                byte[] pcm = queue.poll(200, TimeUnit.MILLISECONDS);
                if (pcm == null) continue;
                int offset = 0;
                while (offset < pcm.length && !stopped) {
                    int n = track.write(pcm, offset, pcm.length - offset);
                    if (n < 0) {
                        Log.d("mic inject write returned " + n);
                        return;
                    }
                    offset += n;
                }
            }
        } catch (InterruptedException ignored) {
        }
    }

    private void release() {
        AudioTrack t = track;
        track = null;
        if (t != null) {
            try {
                t.stop();
            } catch (Throwable ignored) {
            }
            t.release();
        }
        Object p = policy;
        policy = null;
        if (p != null && audioManager != null) {
            try {
                AudioManager.class.getMethod("unregisterAudioPolicy", Class.forName("android.media.audiopolicy.AudioPolicy"))
                        .invoke(audioManager, p);
            } catch (Throwable ignored) {
            }
        }
    }
}
