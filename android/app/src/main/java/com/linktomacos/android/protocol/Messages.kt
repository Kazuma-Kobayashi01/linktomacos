package com.linktomacos.android.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** 协议版本，见 docs/PROTOCOL.md。 */
const val PROTOCOL_VERSION = 1

/** 链路上的一条消息。JSON 中以 `type` 字段区分类型，其余字段平铺在同一层。 */
sealed interface LinkMessage

@Serializable
data class Hello(
    val protocolVersion: Int = PROTOCOL_VERSION,
    val deviceId: String,
    val deviceName: String,
    val model: String,
    val osVersion: String,
    val appVersion: String,
    val pairingToken: String? = null,
) : LinkMessage

@Serializable
data class HelloAck(val accepted: Boolean, val macName: String, val reason: String? = null) : LinkMessage

@Serializable
data class Ping(val t: Long) : LinkMessage

@Serializable
data class Pong(val t: Long) : LinkMessage

@Serializable
data class DeviceStatus(
    val batteryLevel: Int,
    val charging: Boolean,
    val signalLevel: Int? = null,
    val networkType: String? = null,
    val carrier: String? = null,
    val wifiConnected: Boolean,
    val storageTotal: Long,
    val storageFree: Long,
    val timestamp: Long,
    /** 电池温度，摄氏度。 */
    val batteryTemperature: Double? = null,
    /** 电池电压，毫伏。 */
    val batteryVoltage: Int? = null,
    /** good / overheat / dead / over_voltage / cold / failure / unknown */
    val batteryHealth: String? = null,
    /** ac / usb / wireless / dock；未充电为 null。 */
    val chargingType: String? = null,
    val memoryTotal: Long? = null,
    val memoryAvailable: Long? = null,
    /** Wi‑Fi 信号格数 0-4；未连接 Wi‑Fi 为 null。 */
    val wifiLevel: Int? = null,
    /** Wi‑Fi 连接速率，Mbps。 */
    val wifiLinkSpeed: Int? = null,
    /** 蜂窝信号强度，dBm。 */
    val signalDbm: Int? = null,
    /** 开机至今的毫秒数。 */
    val uptime: Long? = null,
) : LinkMessage

@Serializable
data class Goodbye(val reason: String = "") : LinkMessage

/** 手机上弹出的一条通知。[key] 在手机端唯一，同一条通知更新时不变。 */
@Serializable
data class PhoneNotification(
    val key: String,
    val packageName: String,
    val appName: String,
    val title: String,
    val text: String,
    val subText: String? = null,
    val timestamp: Long,
    /** 应用图标，PNG 的 base64。 */
    val iconPng: String? = null,
) : LinkMessage

@Serializable
data class NotificationRemoved(val key: String) : LinkMessage

/** 请求：Mac → 手机（读取相册、文件列表、下载等）。[id] 由发起方分配，响应原样带回。 */
@Serializable
data class Request(val id: Int, val method: String, val params: JsonObject = JsonObject(emptyMap())) : LinkMessage

@Serializable
data class Response(
    val id: Int,
    val ok: Boolean,
    val result: JsonElement? = null,
    val error: String? = null,
) : LinkMessage

/** 一次文件流（下载）结束。内容本身走二进制数据帧。 */
@Serializable
data class StreamEnd(val streamId: Int, val ok: Boolean, val error: String? = null) : LinkMessage

/** 二进制数据帧，属于 [streamId] 对应的文件流。不走 JSON，见 [Frames]。 */
class DataChunk(val streamId: Int, val bytes: ByteArray, val length: Int = bytes.size) : LinkMessage

/**
 * 投屏时 Mac → 手机的输入事件。[k]：t 触摸（[a] 0 按下 1 抬起 2 移动，[x]/[y] 是 0..1 的相对位置）、
 * s 滚轮（[h]/[v]）、key 按键（[a] 0 按下 1 抬起，[c] Android 键值，[m] 修饰键）、text 文字、
 * cmd 命令（[cmd]：back/home/recents/wake/power/notifications/sync/screenOff/screenOn）。
 */
@Serializable
data class MirrorInput(
    val k: String,
    val a: Int? = null,
    val x: Double? = null,
    val y: Double? = null,
    val c: Int? = null,
    val m: Int? = null,
    val h: Double? = null,
    val v: Double? = null,
    val text: String? = null,
    val cmd: String? = null,
) : LinkMessage

/** 投屏状态变化（手机 → Mac）：resized（旋转或尺寸变化）、stopped、error。 */
@Serializable
data class MirrorEvent(
    val event: String,
    val width: Int? = null,
    val height: Int? = null,
    val deviceWidth: Int? = null,
    val deviceHeight: Int? = null,
    val rotation: Int? = null,
    val message: String? = null,
) : LinkMessage

/**
 * 手机的通话状态变化（手机 → Mac）。[state]：ringing（来电响铃）、offhook（通话中，接通或拨出）、idle（空闲，通话结束）。
 * [name] 是来电的联系人名或号码，取自来电通知，拿不到时为 null；响铃期间可能再发一次带名字的 ringing。
 */
@Serializable
data class CallState(
    val state: String,
    val name: String? = null,
    val timestamp: Long,
) : LinkMessage

/** 本端版本不认识的消息类型，忽略即可。 */
data class Unknown(val type: String) : LinkMessage

object MessageCodec {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun encode(message: LinkMessage): String {
        val (type, body) = when (message) {
            is Hello -> "hello" to json.encodeToJsonElement(message)
            is HelloAck -> "helloAck" to json.encodeToJsonElement(message)
            is Ping -> "ping" to json.encodeToJsonElement(message)
            is Pong -> "pong" to json.encodeToJsonElement(message)
            is DeviceStatus -> "deviceStatus" to json.encodeToJsonElement(message)
            is Goodbye -> "goodbye" to json.encodeToJsonElement(message)
            is PhoneNotification -> "notification" to json.encodeToJsonElement(message)
            is NotificationRemoved -> "notificationRemoved" to json.encodeToJsonElement(message)
            is Request -> "request" to json.encodeToJsonElement(message)
            is Response -> "response" to json.encodeToJsonElement(message)
            is StreamEnd -> "streamEnd" to json.encodeToJsonElement(message)
            is MirrorInput -> "mirrorInput" to json.encodeToJsonElement(message)
            is MirrorEvent -> "mirrorEvent" to json.encodeToJsonElement(message)
            is CallState -> "callState" to json.encodeToJsonElement(message)
            is DataChunk -> error("data chunks are binary frames, see Frames")
            is Unknown -> error("cannot send unknown message ${message.type}")
        }
        return JsonObject(mapOf("type" to JsonPrimitive(type)) + body.jsonObject).toString()
    }

    fun decode(text: String): LinkMessage {
        val obj = json.parseToJsonElement(text).jsonObject
        return when (val type = obj["type"]?.jsonPrimitive?.content) {
            "hello" -> json.decodeFromJsonElement<Hello>(obj)
            "helloAck" -> json.decodeFromJsonElement<HelloAck>(obj)
            "ping" -> json.decodeFromJsonElement<Ping>(obj)
            "pong" -> json.decodeFromJsonElement<Pong>(obj)
            "deviceStatus" -> json.decodeFromJsonElement<DeviceStatus>(obj)
            "goodbye" -> json.decodeFromJsonElement<Goodbye>(obj)
            "notification" -> json.decodeFromJsonElement<PhoneNotification>(obj)
            "notificationRemoved" -> json.decodeFromJsonElement<NotificationRemoved>(obj)
            "request" -> json.decodeFromJsonElement<Request>(obj)
            "response" -> json.decodeFromJsonElement<Response>(obj)
            "streamEnd" -> json.decodeFromJsonElement<StreamEnd>(obj)
            "mirrorInput" -> json.decodeFromJsonElement<MirrorInput>(obj)
            "mirrorEvent" -> json.decodeFromJsonElement<MirrorEvent>(obj)
            "callState" -> json.decodeFromJsonElement<CallState>(obj)
            else -> Unknown(type ?: "")
        }
    }
}
