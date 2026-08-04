package cn.mapleafgo.singcast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TileConfigReaderTest {
    private val mergedWithoutDns = """{"inbounds":[]}"""
    private val mergedIpv6 = """{"dns":{"strategy":"prefer_ipv6"}}"""
    private val mergedIpv4 = """{"dns":{"strategy":"ipv4_only"}}"""

    @Test
    fun noConfig_returnsBlankContent() {
        val cfg = TileConfigReader.parse(null, null)
        assertNull(cfg.configContent)
        assertFalse(cfg.ipv6)
        assertEquals("https://gh-proxy.org", cfg.ruleSetProxy)
    }

    @Test
    fun mergedContent_returnedAsIs() {
        val cfg = TileConfigReader.parse(mergedWithoutDns, null)
        assertEquals(mergedWithoutDns, cfg.configContent)
    }

    @Test
    fun preferIpv6_mapsTrue() {
        val cfg = TileConfigReader.parse(mergedIpv6, null)
        assertTrue(cfg.ipv6)
    }

    @Test
    fun ipv4Only_mapsFalse() {
        val cfg = TileConfigReader.parse(mergedIpv4, null)
        assertFalse(cfg.ipv6)
    }

    @Test
    fun missingDns_mapsFalse() {
        val cfg = TileConfigReader.parse(mergedWithoutDns, null)
        assertFalse(cfg.ipv6)
    }

    @Test
    fun ruleSetProxy_readFromSettings() {
        val cfg = TileConfigReader.parse(null, """{"rule-set-proxy":"https://example.com"}""")
        assertEquals("https://example.com", cfg.ruleSetProxy)
    }

    @Test
    fun missingRuleSetProxy_fallsBackToDefault() {
        val cfg = TileConfigReader.parse(null, """{"sub-ua":"x"}""")
        assertEquals("https://gh-proxy.org", cfg.ruleSetProxy)
    }

    @Test
    fun nullOrEmpty_hasNoTunInbound() {
        assertFalse(TileConfigReader.hasTunInbound(null))
        assertFalse(TileConfigReader.hasTunInbound(""))
    }

    @Test
    fun noTunInbound_returnsFalse() {
        assertFalse(TileConfigReader.hasTunInbound(mergedWithoutDns))
    }

    @Test
    fun tunInbound_returnsTrue() {
        assertTrue(TileConfigReader.hasTunInbound("""{"inbounds":[{"type":"tun"}]}"""))
    }

    @Test
    fun invalidJson_returnsFalse() {
        assertFalse(TileConfigReader.hasTunInbound("""{not json"""))
    }
}
