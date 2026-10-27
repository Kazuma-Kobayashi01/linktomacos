package com.linktomacos.android.shell;

import android.annotation.SuppressLint;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 麦克风注入的检查（计划 B1）：只用在 {@code --mic-selftest} 里。
 *
 * 用 {@link MicInjector} 注册回环混音并写入一个 440 Hz 的提示音，再从本进程里开一个普通的麦克风 AudioRecord，
 * 看读到的是不是这个提示音。读到的话，任何应用录音都会拿到我们写进去的声音。全程在内存里，不会放出声音。
 */
@SuppressLint({"WrongConstant", "MissingPermission"})
final class MicProbe {
    private static final int SAMPLE_RATE = MicInjector.SAMPLE_RATE;
    private static final int TONE_PEAK = 6000;

    private MicProbe() {}

    static boolean run() {
        MicInjector injector = new MicInjector();
        try {
            injector.start();
            Log.d("OK   audio policy registered and injection track playing");
        } catch (Throwable t) {
            Log.d("FAIL mic injection setup failed: " + t);
            return false;
        }
        try {
            return verifyLoopback(injector);
        } finally {
            injector.stop();
        }
    }

    /** 往注入器写提示音，从普通麦克风录音里读，看读到的是不是提示音。 */
    private static boolean verifyLoopback(MicInjector injector) {
        AtomicBoolean stop = new AtomicBoolean();
        Thread writer = new Thread(() -> {
            int samplesPerPacket = SAMPLE_RATE / 50; // 20 ms
            byte[] packet = new byte[samplesPerPacket * 2];
            double phase = 0;
            double step = 2 * Math.PI * 440 / SAMPLE_RATE;
            long next = System.nanoTime();
            while (!stop.get()) {
                for (int i = 0; i < samplesPerPacket; i++) {
                    short sample = (short) (Math.sin(phase) * TONE_PEAK);
                    packet[2 * i] = (byte) sample;
                    packet[2 * i + 1] = (byte) (sample >> 8);
                    phase += step;
                }
                injector.write(packet, packet.length);
                next += 20_000_000L;
                long wait = (next - System.nanoTime()) / 1_000_000L;
                if (wait > 0) {
                    try {
                        Thread.sleep(wait);
                    } catch (InterruptedException e) {
                        return;
                    }
                }
            }
        }, "mic-probe-writer");
        writer.start();

        AudioRecord record = null;
        int peak = 0;
        int bytes = 0;
        try {
            record = new AudioRecord.Builder()
                    .setAudioSource(MediaRecorder.AudioSource.MIC)
                    .setAudioFormat(new AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                            .build())
                    .setBufferSizeInBytes(SAMPLE_RATE / 5 * 2)
                    .build();
            Log.d("OK   microphone AudioRecord created, state=" + record.getState());
            record.startRecording();
            byte[] buffer = new byte[SAMPLE_RATE / 50 * 2];
            long end = System.currentTimeMillis() + 1500;
            while (System.currentTimeMillis() < end) {
                int n = record.read(buffer, 0, buffer.length);
                if (n < 0) {
                    Log.d("FAIL microphone read returned " + n);
                    return false;
                }
                bytes += n;
                for (int i = 0; i + 1 < n; i += 2) {
                    int sample = (short) ((buffer[i] & 0xFF) | (buffer[i + 1] << 8));
                    peak = Math.max(peak, Math.abs(sample));
                }
            }
        } catch (Throwable t) {
            Log.d("FAIL microphone capture failed: " + t);
            return false;
        } finally {
            stop.set(true);
            writer.interrupt();
            try {
                writer.join(1000);
            } catch (InterruptedException ignored) {
            }
            if (record != null) {
                try {
                    record.stop();
                } catch (Throwable ignored) {
                }
                record.release();
            }
        }
        Log.d("     read " + bytes + " bytes from the microphone, peak " + peak + " (injected tone peak " + TONE_PEAK + ")");
        // 真实的麦克风环境噪声一般远小于提示音；峰值接近提示音说明读到的是注入的声音
        boolean ok = peak > TONE_PEAK / 2 && peak < TONE_PEAK * 2;
        Log.d(ok ? "OK   the microphone path carries the injected audio" : "FAIL the microphone did not carry the injected tone");
        return ok;
    }
}
