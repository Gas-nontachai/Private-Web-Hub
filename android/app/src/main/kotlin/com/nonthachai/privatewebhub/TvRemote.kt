package com.nonthachai.privatewebhub

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.*
import javax.security.auth.x500.X500Principal

/** Foreground-only LAN transport. Web content never has access to this channel. */
class TvRemote(private val activity: Activity, private val channel: MethodChannel) {
    val isTv = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
        (activity.resources.configuration.uiMode and 15) == 4
    private val main = Handler(Looper.getMainLooper())
    private val random = SecureRandom()
    private val prefs = activity.getSharedPreferences("tv_remote", Context.MODE_PRIVATE)
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val clientExecutor = Executors.newSingleThreadExecutor()
    private val workers = ThreadPoolExecutor(4, 4, 30, TimeUnit.SECONDS, ArrayBlockingQueue(4)).apply {
        allowCoreThreadTimeOut(true)
    }
    private val nsd = activity.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registration: NsdManager.RegistrationListener? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private val devices = mutableMapOf<String, Map<String, Any>>()
    @Volatile private var foreground = false
    @Volatile private var enabled = false
    @Volatile private var server: SSLServerSocket? = null
    @Volatile private var starting = false
    @Volatile private var generation = 0
    private var code = ""
    private var expires = 0L
    private var attempts = 0
    private var approval: CountDownLatch? = null
    private var approved = false
    private var requestKey = ""
    private var permissionResult: MethodChannel.Result? = null
    private val peerLock = Any()
    private var peer: SSLSocket? = null
    private var peerReader: BufferedReader? = null
    private var peerId = 0
    private var paired = readSecret("paired")
    @Volatile private var token = readSecret("controller")?.optString("token") ?: ""
    private val sockets = java.util.Collections.synchronizedSet(mutableSetOf<SSLSocket>())
    @Volatile private var controllerSocket: SSLSocket? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "info" -> result.success(mapOf("isTv" to isTv))
                "permission" -> {
                    if (Build.VERSION.SDK_INT >= 37 && activity.applicationInfo.targetSdkVersion >= 37 &&
                        activity.checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") != PackageManager.PERMISSION_GRANTED) {
                        check(permissionResult == null) { "Permission request in progress" }
                        permissionResult = result
                        activity.requestPermissions(arrayOf("android.permission.ACCESS_LOCAL_NETWORK"), 731)
                    } else result.success(true)
                }
                "start" -> {
                    check(isTv); enabled = true; start()
                    val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
                    fun ready() {
                        when {
                            server != null -> result.success(null)
                            !foreground || android.os.SystemClock.elapsedRealtime() >= deadline -> result.error("receiver", "TV receiver unavailable", null)
                            else -> main.postDelayed({ ready() }, 100)
                        }
                    }
                    ready()
                }
                "pairing" -> {
                    check(isTv && foreground && server != null) { "TV receiver unavailable" }
                    code = "%06d".format(java.util.Locale.US, random.nextInt(1_000_000))
                    expires = android.os.SystemClock.elapsedRealtime() + 120_000
                    attempts = 0
                    result.success(mapOf("code" to code, "address" to localAddress(), "port" to PORT,
                        "fingerprint" to fingerprint(store.getCertificate(TLS_ALIAS) as X509Certificate).take(12)))
                }
                "endPairing" -> { expires = 0; approval?.countDown(); result.success(null) }
                "approve" -> {
                    if (call.argument<String>("id") == requestKey) {
                        approved = call.argument<Boolean>("allow") == true
                        approval?.countDown()
                    }
                    result.success(null)
                }
                "revoke" -> {
                    synchronized(this) { token = ""; writeSecret("controller", null); expires = 0 }
                    synchronized(sockets) { sockets.toList().forEach { runCatching { it.close() } } }
                    result.success(null)
                }
                "discover" -> { discover(); result.success(null) }
                "stopDiscovery" -> { stopDiscovery(); result.success(null) }
                "connect", "pair", "send", "disconnect" -> clientExecutor.execute {
                    try {
                        val answer = synchronized(peerLock) {
                            when (call.method) {
                                "connect" -> connect(call)
                                "pair" -> pair(call)
                                "send" -> request(call.argument<Map<String, Any?>>("command") ?: error("Missing command"))
                                else -> { disconnect(); null }
                            }
                        }
                        main.post { result.success(answer) }
                    } catch (e: Exception) {
                        val rejected = call.method == "send" && e is RemoteRejected
                        if (!rejected) synchronized(peerLock) { disconnect() }
                        main.post { result.error(if (rejected) "rejected" else "remote", e.message ?: "Connection failed", null) }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("remote", e.message, null) }
    }

    fun permissionResponse(grants: IntArray) {
        permissionResult?.success(grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED)
        permissionResult = null
    }

    fun resume() { foreground = true; if (enabled) start() }
    fun pause() {
        foreground = false
        generation++
        expires = 0
        approval?.countDown()
        runCatching { server?.close() }; server = null
        synchronized(sockets) { sockets.toList().forEach { runCatching { it.close() } } }
        registration?.let { runCatching { nsd.unregisterService(it) } }; registration = null
        stopDiscovery()
        // Closing wakes a blocked read immediately, without waiting for the client executor.
        runCatching { peer?.close() }
    }
    fun close() { pause(); workers.shutdownNow(); clientExecutor.shutdownNow() }

    @Synchronized private fun start() {
        if (!foreground || server != null || starting) return
        starting = true
        val epoch = generation
        Thread {
            try {
                val context = serverContext()
                val listener = context.serverSocketFactory.createServerSocket() as SSLServerSocket
                listener.enabledProtocols = listener.supportedProtocols.filter { it == "TLSv1.2" || it == "TLSv1.3" }.toTypedArray()
                listener.reuseAddress = true
                listener.bind(InetSocketAddress(PORT))
                synchronized(this) {
                    if (!foreground || epoch != generation) { listener.close(); return@Thread }
                    server = listener
                }
                main.post { if (server === listener) register() }
                while (!listener.isClosed) {
                    val socket = listener.accept() as SSLSocket
                    sockets.add(socket)
                    try { workers.execute { serve(socket, epoch) } }
                    catch (_: Exception) { sockets.remove(socket); socket.close() }
                }
            } catch (e: Exception) {
                if (foreground && epoch == generation) event("receiverError", e.message ?: "Receiver unavailable")
            } finally { starting = false; if (foreground && enabled && epoch != generation) main.post { start() } }
        }.apply { name = "movie-tv-listener"; isDaemon = true; start() }
    }

    private fun serve(socket: SSLSocket, epoch: Int) {
        try {
            socket.use {
                socket.soTimeout = 90_000
                socket.startHandshake()
                val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
                var authenticated = ""
                while (foreground && epoch == generation) {
                    val frame = readFrame(reader) ?: break
                    val msg = JSONObject(frame)
                    val id = msg.optInt("id", -1)
                    val response = JSONObject().put("v", 1).put("id", id)
                    try {
                        require(msg.optInt("v") == 1 && id >= 0) { "Unsupported protocol" }
                        when (msg.optString("type")) {
                            "pair" -> {
                                val latch = CountDownLatch(1)
                                synchronized(this) {
                                    require(approval == null && android.os.SystemClock.elapsedRealtime() < expires && attempts < 5) { "Open pairing on TV" }
                                    attempts++
                                    require(constantEquals(msg.optString("code"), code)) { "Incorrect pairing code" }
                                    approved = false; approval = latch; requestKey = secret()
                                }
                                event("pairRequest", mapOf("id" to requestKey,
                                    "name" to msg.optString("name", "Android").take(60),
                                    "fingerprint" to fingerprint(store.getCertificate(TLS_ALIAS) as X509Certificate).take(12)))
                                try {
                                    require(latch.await(60, TimeUnit.SECONDS) && approved && foreground && epoch == generation &&
                                        android.os.SystemClock.elapsedRealtime() < expires) { "Pairing declined or expired" }
                                    synchronized(this) {
                                        token = secret()
                                        writeSecret("controller", JSONObject().put("token", token))
                                        authenticated = token; expires = 0
                                    }
                                    activateController(socket)
                                    response.put("token", authenticated).put("ok", true)
                                } finally { synchronized(this) { approval = null; approved = false } }
                            }
                            "auth" -> {
                                val candidate = msg.optString("token")
                                require(token.isNotEmpty() && constantEquals(candidate, token)) { "Pair again on TV" }
                                authenticated = candidate; activateController(socket); response.put("ok", true)
                            }
                            "command" -> {
                                require(authenticated.isNotEmpty() && constantEquals(authenticated, token)) { "Pair first" }
                                val command = msg.optJSONObject("command") ?: error("Missing command")
                                val latch = CountDownLatch(1)
                                var answer: Any? = null
                                var failure: String? = "TV did not respond"
                                main.post {
                                    if (!foreground || epoch != generation || controllerSocket !== socket ||
                                        token.isEmpty() || !constantEquals(authenticated, token)) {
                                        failure = "Controller disconnected or revoked"
                                        latch.countDown(); return@post
                                    }
                                    channel.invokeMethod("command", jsonMap(command), object : MethodChannel.Result {
                                        override fun success(value: Any?) { answer = value; failure = null; latch.countDown() }
                                        override fun error(code: String, message: String?, details: Any?) { failure = message ?: code; latch.countDown() }
                                        override fun notImplemented() { failure = "Unsupported command"; latch.countDown() }
                                    })
                                }
                                require(latch.await(10, TimeUnit.SECONDS) && failure == null) { failure ?: "TV timed out" }
                                response.put("ok", true).put("state", JSONObject.wrap(answer))
                            }
                            else -> error("Unsupported request")
                        }
                    } catch (e: Exception) { response.put("ok", false).put("error", e.message ?: "Invalid request") }
                    socket.outputStream.write((response.toString() + "\n").toByteArray(Charsets.UTF_8))
                    socket.outputStream.flush()
                }
            }
        } catch (e: Exception) {
            if (e is SSLException) android.util.Log.w("MovieTvRemote", "TLS connection failed", e)
        }
        finally { sockets.remove(socket) }
    }

    private fun connect(call: MethodCall): Map<String, Any> {
        disconnect()
        val host = call.argument<String>("host") ?: error("Missing TV address")
        val port = call.argument<Int>("port") ?: PORT
        require(port in 1..65535)
        val address = InetAddress.getByName(host)
        require(address.isSiteLocalAddress || address.isLinkLocalAddress || address.isLoopbackAddress) { "Use a local TV address" }
        val known = paired
        val pairing = call.argument<Boolean>("pairing") == true
        require(pairing || known != null) { "Pair with TV first" }
        val pin = if (pairing) null else known!!.getString("pin")
        var actualPin = ""
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers() = emptyArray<X509Certificate>()
            override fun checkClientTrusted(chain: Array<X509Certificate>, auth: String) { error("Not a server") }
            override fun checkServerTrusted(chain: Array<X509Certificate>, auth: String) {
                require(chain.isNotEmpty())
                actualPin = fingerprint(chain[0])
                if (pin != null && !constantEquals(pin, actualPin)) throw java.security.cert.CertificateException("TV identity changed; pair again")
            }
        }
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), random) }
        val socket = context.socketFactory.createSocket() as SSLSocket
        socket.enabledProtocols = socket.supportedProtocols.filter { it == "TLSv1.2" || it == "TLSv1.3" }.toTypedArray()
        peer = socket
        socket.soTimeout = 70_000
        socket.connect(InetSocketAddress(address, port), 5000)
        socket.startHandshake()
        peerReader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
        peerPin = actualPin
        if (!pairing) {
            exchange(JSONObject().put("type", "auth").put("token", known!!.getString("token")))
            socket.soTimeout = 12_000
        }
        return mapOf("fingerprint" to actualPin.take(12), "paired" to !pairing, "name" to host)
    }

    private var peerPin = ""
    @Synchronized private fun activateController(socket: SSLSocket) {
        if (controllerSocket !== socket) runCatching { controllerSocket?.close() }
        controllerSocket = socket
        socket.soTimeout = 15_000
    }
    private fun pair(call: MethodCall): Any {
        val entered = call.argument<String>("code") ?: ""
        require(entered.matches(Regex("[0-9]{6}"))) { "Enter six digits" }
        val response = exchange(JSONObject().put("type", "pair").put("code", entered).put("name", Build.MODEL))
        val data = JSONObject().put("pin", peerPin).put("token", response.getString("token"))
        writeSecret("paired", data); paired = data
        peer?.soTimeout = 12_000
        return true
    }
    private fun request(command: Map<String, Any?>): Any? =
        exchange(JSONObject().put("type", "command").put("command", JSONObject(command))).opt("state")?.let {
            if (it is JSONObject) jsonMap(it) else null
        }
    private fun exchange(msg: JSONObject): JSONObject {
        val socket = peer ?: error("Connect to TV first")
        val id = ++peerId
        msg.put("v", 1).put("id", id)
        val bytes = (msg.toString() + "\n").toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_FRAME)
        socket.outputStream.write(bytes); socket.outputStream.flush()
        val response = JSONObject(readFrame(peerReader!!) ?: error("TV disconnected"))
        require(response.optInt("v") == 1 && response.optInt("id") == id) { "Invalid TV response" }
        if (!response.optBoolean("ok")) throw RemoteRejected(response.optString("error", "TV rejected command"))
        return response
    }
    private fun disconnect() { runCatching { peer?.close() }; peer = null; peerReader = null }
    private class RemoteRejected(message: String) : Exception(message)

    private fun serverContext(): SSLContext {
        if (!store.containsAlias(TLS_ALIAS)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(TLS_ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256)
                    .setCertificateSubject(X500Principal("CN=Movie.exe TV"))
                    .setCertificateNotBefore(Date(0)).setCertificateNotAfter(Date(4_102_444_800_000L)).build())
            }.generateKeyPair()
        }
        val keys = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(store, null) }
        return SSLContext.getInstance("TLS").apply { init(keys.keyManagers, null, random) }
    }

    private fun writeSecret(name: String, value: JSONObject?) {
        if (value == null) { prefs.edit().remove(name).commit(); return }
        if (!store.containsAlias(SECRET_ALIAS)) KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(SECRET_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, store.getKey(SECRET_ALIAS, null) as SecretKey)
        val bytes = cipher.iv + cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString(name, Base64.encodeToString(bytes, Base64.NO_WRAP)).commit()) { "Could not save pairing" }
    }
    private fun readSecret(name: String): JSONObject? = try {
        prefs.getString(name, null)?.let {
            val bytes = Base64.decode(it, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, store.getKey(SECRET_ALIAS, null) as SecretKey, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        }
    } catch (_: Exception) { null }

    private fun register() {
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) { event("receiverReady", mapOf("address" to localAddress(), "port" to PORT)) }
            override fun onRegistrationFailed(info: NsdServiceInfo, error: Int) { event("discoveryError", "Discovery unavailable; use the TV IP address") }
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, error: Int) {}
        }
        registration = listener
        nsd.registerService(NsdServiceInfo().apply { serviceName = "Movie.exe ${Build.MODEL}"; serviceType = SERVICE; port = PORT }, NsdManager.PROTOCOL_DNS_SD, listener)
    }
    private fun discover() {
        stopDiscovery(); devices.clear(); event("devices", emptyList<Any>())
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, error: Int) { event("discoveryError", "ค้นหา TV ไม่สำเร็จ ลองกรอก IP") }
            override fun onStopDiscoveryFailed(type: String, error: Int) {}
            override fun onServiceLost(info: NsdServiceInfo) { main.post { devices.remove(info.serviceName); event("devices", devices.values.toList()) } }
            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(service: NsdServiceInfo, error: Int) {}
                    override fun onServiceResolved(service: NsdServiceInfo) {
                        val host = service.host?.hostAddress ?: return
                        main.post {
                            if (discovery == null) return@post
                            devices[service.serviceName] = mapOf("name" to service.serviceName, "host" to host, "port" to service.port)
                            event("devices", devices.values.toList())
                        }
                    }
                })
            }
        }
        discovery = listener
        nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, listener)
    }
    private fun stopDiscovery() { discovery?.let { runCatching { nsd.stopServiceDiscovery(it) } }; discovery = null }
    private fun localAddress(): String = NetworkInterface.getNetworkInterfaces().toList()
        .flatMap { it.inetAddresses.toList() }.firstOrNull { it.isSiteLocalAddress && !it.isLoopbackAddress }?.hostAddress ?: ""
    private fun event(name: String, data: Any?) { main.post { channel.invokeMethod(name, data) } }
    private fun secret(): String = ByteArray(32).also(random::nextBytes).let { Base64.encodeToString(it, Base64.NO_WRAP) }

    companion object {
        const val PORT = 47831
        const val SERVICE = "_movieexe._tcp."
        private const val MAX_FRAME = 16_384
        private const val TLS_ALIAS = "movie-tv-tls-ec"
        private const val SECRET_ALIAS = "movie-tv-secrets"
        private fun fingerprint(cert: X509Certificate): String = MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02x".format(it) }
        private fun constantEquals(a: String, b: String): Boolean = MessageDigest.isEqual(a.toByteArray(Charsets.UTF_8), b.toByteArray(Charsets.UTF_8))
        private fun readFrame(reader: BufferedReader): String? {
            val text = StringBuilder()
            while (text.length < MAX_FRAME) {
                val c = reader.read()
                if (c == -1) { require(text.isEmpty()) { "Incomplete frame" }; return null }
                if (c == 10) return text.toString()
                text.append(c.toChar())
            }
            error("Frame too large")
        }
        private fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key ->
            when (val value = json.get(key)) { JSONObject.NULL -> null; is JSONObject -> jsonMap(value); else -> value }
        }
    }
}
