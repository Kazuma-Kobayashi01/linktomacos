package com.linktomacos.android.shell;

import android.annotation.SuppressLint;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 音频转发的可行性检查（计划 A1）：只用在 {@code --audio-selftest} 里，不属于正常的投屏流程。
 *
 * 检查三件事：shell 身份能不能创建 REMOTE_SUBMIX 的 AudioRecord、能不能读到数据、有没有 Opus / AAC 编码器。
 * 为了确认读到的是真实的声音而不是静音，会在录音的同时从本进程播放约 1 秒、音量很低的 440 Hz 提示音；
 * 录音期间系统会把声音导进混音，所以手机本体基本听不到。
 * 做法参考 scrcpy 的音频捕获（Apache-2.0）。
 */
@SuppressLint({"PrivateApi", "DiscouragedPrivateApi", "BlockedPrivateApi"})
final class AudioProbe {
    private static final int SAMPLE_RATE = AudioCapture.SAMPLE_RATE;
    private static final int RECORD_MILLIS = 1500;

    private AudioProbe() {}

    static boolean run() {
        boolean ok = true;
        ok &= checkEncoders();
        ok &= checkCapture();
        Log.d(ok ? "audio selftest PASSED" : "audio selftest FAILED");
        return ok;
    }

    private static boolean checkEncoders() {
        boolean opus = false;
        boolean aac = false;
        for (MediaCodecInfo codec : new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos()) {
            if (!codec.isEncoder()) continue;
            for (String type : codec.getSupportedTypes()) {
                if (type.equalsIgnoreCase("audio/opus")) {
                    opus = true;
                    Log.d("OK   Opus encoder: " + codec.getName());
                }
                if (type.equalsIgnoreCase("audio/mp4a-latm")) {
                    aac = true;
                    Log.d("OK   AAC encoder: " + codec.getName());
                }
            }
        }
        if (!opus) Log.d("WARN no Opus encoder, would fall back to AAC");
        if (!aac) Log.d("WARN no AAC encoder");
        return opus || aac;
    }

    private static boolean checkCapture() {
        AudioRecord record = null;
        try {
            record = AudioCapture.createRecord();
        } catch (Throwable t) {
            Log.d("FAIL AudioRecord(REMOTE_SUBMIX) could not be created: " + t);
            if (t.getCause() != null) Log.d("     cause: " + t.getCause());
            return false;
        }
        Log.d("OK   AudioRecord(REMOTE_SUBMIX) created, state=" + record.getState());

        AtomicBoolean stopTone = new AtomicBoolean();
        Thread tone = startTone(stopTone);
        int totalBytes = 0;
        int peak = 0;
        try {
            record.startRecording();
            Log.d("OK   startRecording, recordingState=" + record.getRecordingState());
            byte[] buffer = new byte[SAMPLE_RATE / 50 * 4]; // 20 ms
            long end = System.currentTimeMillis() + RECORD_MILLIS;
            int reads = 0;
            while (System.currentTimeMillis() < end) {
                int n = record.read(buffer, 0, buffer.length);
                if (n < 0) {
                    Log.d("FAIL read returned " + n);
                    return false;
                }
                reads++;
                totalBytes += n;
                for (int i = 0; i + 1 < n; i += 2) {
                    int sample = (short) ((buffer[i] & 0xFF) | (buffer[i + 1] << 8));
                    peak = Math.max(peak, Math.abs(sample));
                }
            }
            Log.d("     " + reads + " reads, " + totalBytes + " bytes (about " + totalBytes / 192 + " ms of audio), peak amplitude " + peak + " / 32767");
        } catch (Throwable t) {
            Log.d("FAIL capture failed: " + t);
            return false;
        } finally {
            stopTone.set(true);
            try {
                if (tone != null) tone.join(1000);
            } catch (InterruptedException ignored) {
            }
            try {
                record.stop();
            } catch (Throwable ignored) {
            }
            record.release();
        }
        if (totalBytes == 0) {
            Log.d("FAIL no data was delivered");
            return false;
        }
        if (peak == 0) {
            Log.d("WARN data flows but it is all silence (the test tone did not reach the capture)");
            return false;
        }
        Log.d("OK   captured real audio from the system mix");
        return true;
    }

    /** 低音量的 440 Hz 提示音，持续到 stop 被置位。创建失败返回 null（录音检查会因为全是静音而给出提示）。 */
    private static Thread startTone(AtomicBoolean stop) {
        try {
            AudioTrack track = new AudioTrack.Builder()
                    .setAudioAttributes(new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build())
                    .setAudioFormat(new AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                            .build())
                    .setBufferSizeInBytes(SAMPLE_RATE / 5 * 4)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build();
            track.play();
            Thread thread = new Thread(() -> {
                short[] samples = new short[SAMPLE_RATE / 50 * 2]; // 20 ms 立体声
                double phase = 0;
                double step = 2 * Math.PI * 440 / SAMPLE_RATE;
                try {
                    while (!stop.get()) {
                        for (int i = 0; i < samples.length; i += 2) {
                            short value = (short) (Math.sin(phase) * 3000); // 约 -21 dBFS
                            samples[i] = value;
                            samples[i + 1] = value;
                            phase += step;
                        }
                        track.write(samples, 0, samples.length);
                    }
                } finally {
                    try {
                        track.stop();
                    } catch (Throwable ignored) {
                    }
                    track.release();
                }
            }, "audio-probe-tone");
            thread.start();
            return thread;
        } catch (Throwable t) {
            Log.d("WARN test tone could not be played: " + t);
            return null;
        }
    }
}
