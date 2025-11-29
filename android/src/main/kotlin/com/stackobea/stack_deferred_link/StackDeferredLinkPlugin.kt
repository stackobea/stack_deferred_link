package com.stackobea.stack_deferred_link

import android.content.Context
import android.os.DeadObjectException
import android.util.Log
import androidx.annotation.NonNull
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.android.installreferrer.api.ReferrerDetails
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android implementation for `stack_deferred_link`.
 *
 * Responsibilities:
 *  - Create an InstallReferrerClient
 *  - Handle connection lifecycle (OK / errors / disconnects)
 *  - Cache the first received result (success or error)
 *  - Serve all pending MethodChannel requests from the same cached result
 *  - Retry the connection exactly once on disconnect
 */
class StackDeferredLinkPlugin : FlutterPlugin, MethodCallHandler {

    // Application context for creating the InstallReferrerClient
    private lateinit var appContext: Context

    // MethodChannel used to communicate with Dart side
    private lateinit var channel: MethodChannel

    // Underlying Play Install Referrer client (null when not connected)
    @Volatile
    private var referrerClient: InstallReferrerClient? = null

    // First successfully retrieved referrer details (cached)
    @Volatile
    private var cachedDetails: ReferrerDetails? = null

    // First error we encountered and decided to cache
    @Volatile
    private var cachedError: PluginError? = null

    // Results pending while connection / fetch is in progress
    private val pendingResults = mutableListOf<Result>()

    // Internal error model to carry structured errors to Dart
    private data class PluginError(
        val code: String,
        val message: String
    )

    // To avoid infinite reconnect loops
    @Volatile
    private var hasRetriedConnection = false

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        channel = MethodChannel(
            binding.binaryMessenger,
            CHANNEL_NAME
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        // Clean up resources when the engine detaches
        synchronized(this) {
            pendingResults.clear()
            referrerClient?.endConnection()
            referrerClient = null
        }
        channel.setMethodCallHandler(null)
    }

    // ------------------------------------------------------------------------
    // MethodChannel entry point
    // ------------------------------------------------------------------------

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getInstallReferrer" -> handleGetInstallReferrer(result)
            else -> result.notImplemented()
        }
    }

    /**
     * Handle Dart call for "getInstallReferrer".
     *
     * - If we already have a cached result (success/error), return it immediately.
     * - Otherwise, enqueue the result and ensure that a connection is started.
     */
    @Synchronized
    private fun handleGetInstallReferrer(@NonNull result: Result) {
        // If we already have data (or a permanent error), reuse it.
        if (cachedDetails != null || cachedError != null) {
            sendCachedResult(result)
            return
        }

        // Otherwise, add this caller to the pending queue
        pendingResults.add(result)

        // If no client exists yet, start a connection
        if (referrerClient == null) {
            startConnection()
        }
    }

    // ------------------------------------------------------------------------
    // Connection logic
    // ------------------------------------------------------------------------

    /**
     * Start the initial InstallReferrer connection.
     */
    @Synchronized
    private fun startConnection() {
        if (referrerClient != null) {
            // Already trying or connected
            return
        }

        referrerClient = InstallReferrerClient.newBuilder(appContext).build()
        hasRetriedConnection = false

        try {
            referrerClient?.startConnection(object : InstallReferrerStateListener {

                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    handleSetupFinished(responseCode)
                }

                override fun onInstallReferrerServiceDisconnected() {
                    Log.w(TAG, "InstallReferrer service disconnected")

                    // Try exactly once to reconnect
                    if (!hasRetriedConnection) {
                        hasRetriedConnection = true
                        retryConnection()
                    } else {
                        // If we already tried once, surface an error
                        setErrorAndFlush(
                            PluginError(
                                code = "SERVICE_DISCONNECTED",
                                message = "Google Play Install Referrer service disconnected."
                            )
                        )
                    }
                }
            })
        } catch (e: DeadObjectException) {
            // Service died mid-call
            Log.e(TAG, "DeadObjectException while starting connection: ${e.message}", e)
            setErrorAndFlush(
                PluginError(
                    code = "DEAD_OBJECT_EXCEPTION",
                    message = "Install Referrer service connection died unexpectedly."
                )
            )
        } catch (e: Exception) {
            // Catch-all for any unexpected runtime issues
            Log.e(TAG, "Unexpected error while starting connection: ${e.message}", e)
            setErrorAndFlush(
                PluginError(
                    code = "CONNECTION_FAILED",
                    message = "Failed to start Install Referrer connection."
                )
            )
        }
    }

    /**
     * Retry the InstallReferrer connection once after a disconnect.
     */
    @Synchronized
    private fun retryConnection() {
        Log.d(TAG, "Retrying InstallReferrer connection once")

        referrerClient?.endConnection()
        referrerClient = InstallReferrerClient.newBuilder(appContext).build()

        try {
            referrerClient?.startConnection(object : InstallReferrerStateListener {

                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    handleSetupFinished(responseCode)
                }

                override fun onInstallReferrerServiceDisconnected() {
                    Log.w(TAG, "InstallReferrer service disconnected again after retry")
                    setErrorAndFlush(
                        PluginError(
                            code = "SERVICE_DISCONNECTED_RETRY",
                            message = "Install Referrer service disconnected after retry."
                        )
                    )
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Failed to retry InstallReferrer connection: ${e.message}", e)
            setErrorAndFlush(
                PluginError(
                    code = "RETRY_FAILED",
                    message = "Failed to reconnect to Install Referrer service."
                )
            )
        }
    }

    /**
     * Called when Play Store finishes the setup call.
     */
    @Synchronized
    private fun handleSetupFinished(responseCode: Int) {
        try {
            when (responseCode) {
                InstallReferrerClient.InstallReferrerResponse.OK -> {
                    // Connection is OK, try to read the referrer data
                    val client = referrerClient
                    if (client != null) {
                        try {
                            cachedDetails = client.installReferrer
                            // cachedDetails will be used for all pending results
                        } catch (e: DeadObjectException) {
                            Log.e(
                                TAG,
                                "DeadObjectException while fetching install referrer: ${e.message}",
                                e
                            )
                            cachedError = PluginError(
                                code = "DEAD_OBJECT_EXCEPTION",
                                message = "Install Referrer service died while retrieving data."
                            )
                            cachedDetails = null
                        } catch (e: Exception) {
                            Log.e(
                                TAG,
                                "Unexpected error while fetching install referrer: ${e.message}",
                                e
                            )
                            cachedError = PluginError(
                                code = "UNEXPECTED_ERROR",
                                message = "Unexpected error while retrieving referrer details."
                            )
                            cachedDetails = null
                        }
                    } else {
                        cachedError = PluginError(
                            code = "NULL_CLIENT",
                            message = "Install Referrer client was not available."
                        )
                        cachedDetails = null
                    }
                }

                InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE -> {
                    cachedError = PluginError(
                        code = "SERVICE_UNAVAILABLE",
                        message = "Install Referrer service is currently unavailable."
                    )
                    cachedDetails = null
                }

                InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> {
                    cachedError = PluginError(
                        code = "FEATURE_NOT_SUPPORTED",
                        message = "Install Referrer API is not supported on this device."
                    )
                    cachedDetails = null
                }

                InstallReferrerClient.InstallReferrerResponse.DEVELOPER_ERROR -> {
                    cachedError = PluginError(
                        code = "DEVELOPER_ERROR",
                        message = "Developer error while using Install Referrer API."
                    )
                    cachedDetails = null
                }

                InstallReferrerClient.InstallReferrerResponse.PERMISSION_ERROR -> {
                    cachedError = PluginError(
                        code = "PERMISSION_ERROR",
                        message = "App is not allowed to use Install Referrer service."
                    )
                    cachedDetails = null
                }

                else -> {
                    cachedError = PluginError(
                        code = "UNKNOWN_RESPONSE",
                        message = "Install Referrer API returned unknown response code: $responseCode"
                    )
                    cachedDetails = null
                }
            }
        } finally {
            // Release the client and push results to all pending callers.
            referrerClient?.endConnection()
            referrerClient = null
            flushAllPendingResults()
        }
    }

    // ------------------------------------------------------------------------
    // Result handling helpers
    // ------------------------------------------------------------------------

    /**
     * Set an error as final and flush all pending MethodChannel results.
     */
    @Synchronized
    private fun setErrorAndFlush(error: PluginError) {
        cachedError = error
        cachedDetails = null

        referrerClient?.endConnection()
        referrerClient = null

        flushAllPendingResults()
    }

    /**
     * Send cachedDetails or cachedError to all pending results.
     */
    @Synchronized
    private fun flushAllPendingResults() {
        val resultsToFlush = pendingResults.toList()
        pendingResults.clear()

        for (result in resultsToFlush) {
            sendCachedResult(result)
        }
    }

    /**
     * Send the already-known result (success or error) to a single caller.
     */
    @Synchronized
    private fun sendCachedResult(result: Result) {
        val details = cachedDetails
        val error = cachedError

        if (details != null) {
            // Success: map the ReferrerDetails to a serializable Map
            result.success(
                mapOf(
                    "installReferrer" to details.installReferrer,
                    "referrerClickTimestampSeconds" to details.referrerClickTimestampSeconds,
                    "installBeginTimestampSeconds" to details.installBeginTimestampSeconds,
                    "referrerClickTimestampServerSeconds" to details.referrerClickTimestampServerSeconds,
                    "installBeginTimestampServerSeconds" to details.installBeginTimestampServerSeconds,
                    "installVersion" to details.installVersion,
                    "googlePlayInstantParam" to details.googlePlayInstantParam
                )
            )
        } else if (error != null) {
            // Error: propagate as PlatformException
            result.error(error.code, error.message, null)
        } else {
            // Should be very rare; fallback to a generic error
            result.error(
                "NO_RESULT",
                "Install Referrer result is not available.",
                null
            )
        }
    }

    companion object {
        private const val TAG = "StackDeferredLink"
        private const val CHANNEL_NAME = "com.stackobea.stack_deferred_link"
    }
}
