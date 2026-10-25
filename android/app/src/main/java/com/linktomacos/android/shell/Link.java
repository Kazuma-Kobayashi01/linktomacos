package com.linktomacos.android.shell;

import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.Closeable;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * 与手机 App 的本机连接（127.0.0.1）。帧格式：[类型 1 字节][长度 4 字节大端][内容]。
 *  - 类型 1：JSON 控制消息
 *  - 类型 2：视频包 [标志 1 字节][pts 8 字节大端，微秒][H.264 数据]；标志 1=配置(SPS/PPS)，2=关键帧
 *
 * 握手是挑战应答：服务端发随机数，App 用共享密钥算 HMAC-SHA256 回应。密钥不上线，
 * 所以即使别的 App 抢先监听了同一个端口，也无法控制这个 shell 服务。
 */
final class Link implements Closeable {
    static final int TYPE_JSON = 1;
    static final int TYPE_VIDEO = 2;
    static final int TYPE_AUDIO = 3;
    /** App → 服务：Mac 麦克风的 PCM（48 kHz、单声道、16 位小端）。 */
    static final int TYPE_MIC = 4;
    static final int FLAG_CONFIG = 1;
    static final int FLAG_KEY = 2;
    private static final int MAX_FRAME = 4 * 1024 * 1024;

    private final Socket socket;
    private final DataInputStream in;
    private final DataOutputStream out;

    private Link(Socket socket) throws IOException {
        this.socket = socket;
        this.in = new DataInputStream(new BufferedInputStream(socket.getInputStream(), 16 * 1024));
        this.out = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream(), 64 * 1024));
    }

    /** 连接 App 并完成握手。失败抛出 IOException。 */
    static Link connect(int port, byte[] secret) throws Exception {
        Socket socket = new Socket();
        socket.setTcpNoDelay(true);
        socket.connect(new InetSocketAddress("127.0.0.1", port), 2000);
        socket.setSoTimeout(5000);
        Link link = new Link(socket);
        try {
            byte[] nonceBytes = new byte[16];
            new SecureRandom().nextBytes(nonceBytes);
            String nonce = hex(nonceBytes);
            JSONObject hello = new JSONObject();
            hello.put("t", "hello");
            hello.put("v", ShellMain.VERSION);
            hello.put("nonce", nonce);
            hello.put("sdk", Hidden.sdk());
            link.sendJson(hello);

            JSONObject auth = link.readJson();
            String expected = hex(hmac(secret, nonce.getBytes(StandardCharsets.UTF_8)));
            byte[] got = auth.optString("mac", "").getBytes(StandardCharsets.UTF_8);
            if (!"auth".equals(auth.optString("t")) || !MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8), got)) {
                throw new IOException("authentication failed");
            }
            JSONObject ready = new JSONObject();
            ready.put("t", "ready");
            link.sendJson(ready);
            socket.setSoTimeout(0);
            return link;
        } catch (Exception e) {
            link.close();
            throw e;
        }
    }

    private JSONObject readJson() throws Exception {
        int type = in.readUnsignedByte();
        int length = in.readInt();
        if (type != TYPE_JSON || length < 0 || length > 64 * 1024) throw new IOException("bad handshake frame");
        byte[] body = new byte[length];
        in.readFully(body);
        return new JSONObject(new String(body, StandardCharsets.UTF_8));
    }

    /** 收到麦克风 PCM 时的处理，由读命令的线程调用，不能阻塞。 */
    interface MicSink {
        void write(byte[] pcm, int length);
    }

    volatile MicSink micSink;

    /** 读取下一条 JSON 控制消息（阻塞）。麦克风数据在这里直接交给 [micSink]，不返回。 */
    JSONObject readCommand() throws Exception {
        while (true) {
            int type = in.readUnsignedByte();
            int length = in.readInt();
            if (length < 0 || length > MAX_FRAME) throw new IOException("bad frame length " + length);
            byte[] body = new byte[length];
            in.readFully(body);
            if (type == TYPE_JSON) return new JSONObject(new String(body, StandardCharsets.UTF_8));
            if (type == TYPE_MIC) {
                MicSink sink = micSink;
                if (sink != null) sink.write(body, length);
            }
            // 其他类型没有 App → 服务的数据，忽略
        }
    }

    synchronized void sendJson(JSONObject json) throws IOException {
        byte[] body = json.toString().getBytes(StandardCharsets.UTF_8);
        out.writeByte(TYPE_JSON);
        out.writeInt(body.length);
        out.write(body);
        out.flush();
    }

    synchronized void sendVideo(int flags, long ptsUs, byte[] data, int length) throws IOException {
        sendMedia(TYPE_VIDEO, flags, ptsUs, data, length);
    }

    /** Opus 音频包，格式和视频包一样：标志、pts、数据。 */
    synchronized void sendAudio(int flags, long ptsUs, byte[] data, int length) throws IOException {
        sendMedia(TYPE_AUDIO, flags, ptsUs, data, length);
    }

    private void sendMedia(int type, int flags, long ptsUs, byte[] data, int length) throws IOException {
        out.writeByte(type);
        out.writeInt(length + 9);
        out.writeByte(flags);
        out.writeLong(ptsUs);
        out.write(data, 0, length);
        out.flush();
    }

    @Override
    public void close() {
        try {
            socket.close();
        } catch (IOException ignored) {
        }
    }

    static byte[] hmac(byte[] key, byte[] message) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        return mac.doFinal(message);
    }

    static String hex(byte[] bytes) {
        StringBuilder builder = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) builder.append(String.format("%02x", b & 0xff));
        return builder.toString();
    }

    static byte[] fromHex(String text) {
        byte[] result = new byte[text.length() / 2];
        for (int i = 0; i < result.length; i++) result[i] = (byte) Integer.parseInt(text.substring(2 * i, 2 * i + 2), 16);
        return result;
    }
}
