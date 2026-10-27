package com.linktomacos.android.shell;

import android.annotation.SuppressLint;
import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaCodec;
import android.media.MediaFormat;

import org.json.JSONObject;

import java.io.IOException;
import java.nio.ByteBuffer;

/**
 * 录下手机播放的声音（系统混音），编码成 Opus 发给 App。做法参考 scrcpy 的音频转发（Apache-2.0）。
 *
 * 用 REMOTE_SUBMIX 音源：shell 身份可以直接创建，不需要录音权限和每次授权。
 * 录音期间系统把声音导进混音，手机本体不再出声，声音只在 Mac 上播放。
 * 每个包 20 ms，格式 {@code [标志][pts][Opus 包]}，和视频包一样，标志位 1 = 配置。
 */
final class AudioCapture {
    /** MediaRecorder.AudioSource.REMOTE_SUBMIX，不在公开的常量里。 */
    private static final int SOURCE_REMOTE_SUBMIX = 8;
    static final int SAMPLE_RATE = 48_000;
    private static final int CHANNELS = 2;
    private static final int BIT_RATE = 128_000;
    /** 20 ms 的 16 位立体声。 */
    private static final int FRAME_BYTES = SAMPLE_RATE / 50 * CHANNELS * 2;
    private static final String OPUS = "audio/opus";

    private final Link link;
    private volatile boolean stopped;
    private volatile AudioRecord record;
    private Thread thread;

    AudioCapture(Link link) {
        this.link = link;
    }

    void start() {
        thread = new Thread(this::run, "audio");
        thread.start();
    }

    void stop() {
        stopped = true;
        // 没有声音在播的时候 read 可能一直阻塞，停掉录音让它返回
        AudioRecord r = record;
        if (r != null) {
            try {
                r.stop();
            } catch (Throwable ignored) {
            }
        }
        Thread t = thread;
        if (t != null && t != Thread.currentThread()) {
            try {
                t.join(2000);
            } catch (InterruptedException ignored) {
            }
        }
    }

    @SuppressLint("WrongConstant") // REMOTE_SUBMIX 是系统内部的音源，不在公开的 IntDef 里
    static AudioRecord createRecord() throws Exception {
        AudioRecord.Builder builder = new AudioRecord.Builder();
        // Android 12 起，Builder 需要一个上下文来确定包名和权限；用伪造的 shell 上下文
        AudioRecord.Builder.class.getMethod("setContext", Context.class).invoke(builder, Hidden.context());
        builder.setAudioSource(SOURCE_REMOTE_SUBMIX);
        builder.setAudioFormat(new AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                .build());
        int minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT);
        builder.setBufferSizeInBytes(Math.max(minBuffer, SAMPLE_RATE / 5 * 4) * 2);
        return builder.build();
    }

    private void run() {
        MediaCodec codec = null;
        try {
            record = createRecord();
            codec = MediaCodec.createEncoderByType(OPUS);
            MediaFormat format = MediaFormat.createAudioFormat(OPUS, SAMPLE_RATE, CHANNELS);
            format.setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE);
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            codec.start();
            record.startRecording();
            Log.d("audio capture started");
            encodeLoop(codec);
        } catch (Throwable t) {
            if (!stopped) {
                Log.e("audio failed", t);
                try {
                    link.sendJson(new JSONObject().put("t", "audioError").put("message", String.valueOf(t)));
                } catch (Exception ignored) {
                }
            }
        } finally {
            AudioRecord r = record;
            record = null;
            if (r != null) {
                try {
                    r.stop();
                } catch (Throwable ignored) {
                }
                r.release();
            }
            if (codec != null) {
                try {
                    codec.stop();
                } catch (Throwable ignored) {
                }
                codec.release();
            }
            Log.d("audio capture ended");
        }
    }

    private void encodeLoop(MediaCodec codec) throws IOException {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        byte[] scratch = new byte[4096];
        long frames = 0;
        while (!stopped) {
            int input = codec.dequeueInputBuffer(20_000);
            if (input >= 0) {
                ByteBuffer buffer = codec.getInputBuffer(input);
                buffer.clear();
                int n = record.read(buffer, Math.min(FRAME_BYTES, buffer.capacity()));
                if (stopped) return;
                if (n < 0) throw new IOException("AudioRecord.read returned " + n);
                // 时间戳按采样数算，不受读取快慢影响
                codec.queueInputBuffer(input, 0, Math.max(n, 0), frames * 1_000_000L / SAMPLE_RATE, 0);
                frames += Math.max(n, 0) / (CHANNELS * 2);
            }
            int output;
            while ((output = codec.dequeueOutputBuffer(info, 0)) >= 0) {
                if (info.size > 0) {
                    ByteBuffer packet = codec.getOutputBuffer(output);
                    packet.position(info.offset);
                    packet.limit(info.offset + info.size);
                    if (scratch.length < info.size) scratch = new byte[info.size];
                    packet.get(scratch, 0, info.size);
                    int flags = (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0 ? Link.FLAG_CONFIG : 0;
                    link.sendAudio(flags, info.presentationTimeUs, scratch, info.size);
                }
                codec.releaseOutputBuffer(output, false);
            }
        }
    }
}
