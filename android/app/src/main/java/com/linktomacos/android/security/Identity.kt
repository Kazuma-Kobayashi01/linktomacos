package com.linktomacos.android.security

import android.annotation.SuppressLint
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.math.BigInteger
import java.net.Socket
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.net.ssl.KeyManager
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509KeyManager
import javax.net.ssl.X509TrustManager
import javax.security.auth.x500.X500Principal

/**
 * 本机长期身份：AndroidKeyStore 中的 P-256 私钥（不可导出）+ 系统生成的自签名证书。
 * Mac 首次配对时记录该证书的 SHA-256 指纹，此后只认这张证书。
 */
object Identity {
    private const val ALIAS = "linktomacos_identity"

    private val keyStore: KeyStore by lazy { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }

    @Synchronized
    fun entry(): KeyStore.PrivateKeyEntry {
        if (!keyStore.containsAlias(ALIAS)) generate()
        return keyStore.getEntry(ALIAS, null) as KeyStore.PrivateKeyEntry
    }

    private fun generate() {
        val now = System.currentTimeMillis()
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            // TLS 1.3 用 SHA256；NONE 留给 TLS 1.2 及 Conscrypt 内部预哈希
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)
            .setCertificateSubject(X500Principal("CN=LinkToMacOS Android"))
            .setCertificateSerialNumber(BigInteger.valueOf(now))
            .setCertificateNotBefore(Date(now - 3_600_000))
            .setCertificateNotAfter(Date(now + 20L * 365 * 24 * 3_600_000))
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
            initialize(spec)
            generateKeyPair()
        }
    }

    fun fingerprint(cert: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02x".format(it) }

    /** 出示本机证书，并只信任指纹为 [pinnedFingerprint] 的 Mac 证书。 */
    fun sslContext(pinnedFingerprint: String): SSLContext {
        val entry = entry()
        val cert = entry.certificate as X509Certificate
        val keyManager = object : X509KeyManager {
            override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = ALIAS
            override fun getCertificateChain(alias: String?) = arrayOf(cert)
            override fun getPrivateKey(alias: String?): PrivateKey = entry.privateKey
            override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(ALIAS)
            override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?) = null
            override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?) = null
        }
        // 不走 CA 链校验，而是锁定配对时拿到的证书指纹，比信任系统 CA 更严格
        @SuppressLint("CustomX509TrustManager")
        val trustManager = object : X509TrustManager {
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?) {
                val actual = chain.firstOrNull()?.let(::fingerprint)
                if (actual != pinnedFingerprint) throw CertificateException("Mac certificate fingerprint does not match")
            }
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) =
                throw CertificateException("client mode only")
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        return SSLContext.getInstance("TLSv1.3").apply {
            init(arrayOf<KeyManager>(keyManager), arrayOf<TrustManager>(trustManager), null)
        }
    }
}
