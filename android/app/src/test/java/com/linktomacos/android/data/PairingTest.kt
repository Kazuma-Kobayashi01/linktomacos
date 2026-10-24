package com.linktomacos.android.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingTest {
    private fun mac(fp: String = "aa", token: String? = null, hosts: List<String> = listOf("1.1.1.1")) =
        PairedMac("Mac", hosts, 47152, fp, token)

    @Test
    fun consumingTokenAfterHandshakeIsNotARepair() {
        assertTrue(isSamePairing(mac(token = "t1"), mac(token = null, hosts = listOf("2.2.2.2"))))
    }

    @Test
    fun hostUpdateIsNotARepair() {
        assertTrue(isSamePairing(mac(), mac(hosts = listOf("2.2.2.2", "1.1.1.1"))))
    }

    @Test
    fun rescanningSameMacIsARepair() {
        assertFalse(isSamePairing(mac(), mac(token = "t2")))
        assertFalse(isSamePairing(mac(token = "t1"), mac(token = "t2")))
    }

    @Test
    fun differentMacOrUnpairIsARepair() {
        assertFalse(isSamePairing(mac(fp = "aa"), mac(fp = "bb")))
        assertFalse(isSamePairing(mac(), null))
        assertFalse(isSamePairing(null, mac(token = "t")))
    }
}
