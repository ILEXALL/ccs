package com.example.ccs_app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.GeoPoint
import com.google.firebase.firestore.SetOptions
import java.util.Date

class LiveLocationService : Service(), LocationListener {
    private lateinit var locationManager: LocationManager

    private var uid: String = ""
    private var shareScope: String = "public"
    private var visibleToUserIds: List<String> = emptyList()
    private var promptAtMillis: Long = 0L
    private var expiresAtMillis: Long = 0L
    private var uploadIntervalMillis: Long = 60_000L
    private var minimumUploadDistanceMeters: Float = 0f
    private var isListening = false

    private val auth: FirebaseAuth by lazy { FirebaseAuth.getInstance() }
    private val firestore: FirebaseFirestore by lazy { FirebaseFirestore.getInstance() }

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        readIntent(intent)

        if (uid.isBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (!hasLocationPermission() || !startForegroundSafely()) {
            stopSelf()
            return START_NOT_STICKY
        }

        startLocationUpdates()
        return START_STICKY
    }

    override fun onDestroy() {
        stopLocationUpdates()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onLocationChanged(location: Location) {
        uploadLocation(location)
    }

    override fun onProviderEnabled(provider: String) = Unit

    override fun onProviderDisabled(provider: String) = Unit

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

    private fun readIntent(intent: Intent?) {
        if (intent == null) {
            return
        }

        uid = intent.getStringExtra("uid") ?: uid
        shareScope = intent.getStringExtra("shareScope")?.takeIf { it.isNotBlank() }
            ?: shareScope
        promptAtMillis = intent.getLongExtra("promptAtMillis", promptAtMillis)
        expiresAtMillis = intent.getLongExtra("expiresAtMillis", expiresAtMillis)
        uploadIntervalMillis =
            (intent.getIntExtra("uploadIntervalSeconds", 60).coerceAtLeast(15) * 1000L)
        minimumUploadDistanceMeters =
            intent.getDoubleExtra("minimumUploadDistanceMeters", 0.0).toFloat()
                .coerceAtLeast(0f)
        visibleToUserIds =
            intent.getStringArrayListExtra("visibleToUserIds")?.filter { it.isNotBlank() }
                ?: visibleToUserIds
    }

    private fun hasLocationPermission(): Boolean {
        val fineGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarseGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        return fineGranted || coarseGranted
    }

    private fun startForegroundSafely(): Boolean {
        return try {
            startForeground(NOTIFICATION_ID, buildNotification())
            true
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        if (isListening || !hasLocationPermission()) {
            return
        }

        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER
        ).filter { provider ->
            try {
                locationManager.isProviderEnabled(provider)
            } catch (_: Exception) {
                false
            }
        }

        if (providers.isEmpty()) {
            return
        }

        for (provider in providers) {
            try {
                locationManager.requestLocationUpdates(
                    provider,
                    uploadIntervalMillis,
                    minimumUploadDistanceMeters,
                    this
                )
                locationManager.getLastKnownLocation(provider)?.let { uploadLocation(it) }
                isListening = true
            } catch (_: SecurityException) {
                stopSelf()
                return
            } catch (_: Exception) {
                // Keep trying the remaining provider.
            }
        }
    }

    private fun stopLocationUpdates() {
        if (!isListening) {
            return
        }

        try {
            locationManager.removeUpdates(this)
        } catch (_: Exception) {
            // The service is shutting down anyway.
        }

        isListening = false
    }

    private fun uploadLocation(location: Location) {
        val currentUid = auth.currentUser?.uid
        if (currentUid == null || currentUid != uid) {
            return
        }

        if (expiresAtMillis > 0 && System.currentTimeMillis() >= expiresAtMillis) {
            stopExpiredSharing()
            return
        }

        val audience = normalizedAudience()
        val liveLocationData = mutableMapOf<String, Any>(
            "uid" to uid,
            "lat" to location.latitude,
            "lng" to location.longitude,
            "coordinates" to GeoPoint(location.latitude, location.longitude),
            "visibleToUserIds" to audience,
            "shareScope" to shareScope.ifBlank { "public" },
            "updatedAt" to FieldValue.serverTimestamp()
        )

        if (location.hasBearing()) {
            liveLocationData["heading"] = location.bearing.toDouble()
        }

        if (promptAtMillis > 0) {
            liveLocationData["promptAt"] = Timestamp(Date(promptAtMillis))
        }

        if (expiresAtMillis > 0) {
            liveLocationData["expiresAt"] = Timestamp(Date(expiresAtMillis))
        }

        firestore.collection("live_locations")
            .document(uid)
            .set(liveLocationData, SetOptions.merge())

        val userData = mutableMapOf<String, Any>(
            "isSharingLiveLocation" to true,
            "liveLocationVisibleToUserIds" to audience,
            "lastSeenAt" to FieldValue.serverTimestamp(),
            "isOnline" to true
        )

        if (expiresAtMillis > 0) {
            userData["liveLocationExpiresAt"] = Timestamp(Date(expiresAtMillis))
        }

        firestore.collection("users")
            .document(uid)
            .set(userData, SetOptions.merge())
    }

    private fun stopExpiredSharing() {
        firestore.collection("live_locations").document(uid).delete()
        firestore.collection("users").document(uid).set(
            mapOf(
                "isSharingLiveLocation" to false,
                "liveLocationVisibleToUserIds" to emptyList<String>()
            ),
            SetOptions.merge()
        )
        stopSelf()
    }

    private fun normalizedAudience(): List<String> {
        val result = linkedSetOf<String>()
        result.add(uid)

        for (userId in visibleToUserIds) {
            if (userId.isNotBlank()) {
                result.add(userId)
            }
        }

        if (shareScope == "public") {
            result.add(PUBLIC_AUDIENCE_MARKER)
        }

        return result.toList()
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("CCS live location")
            .setContentText("Sharing your live location")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live location",
                NotificationManager.IMPORTANCE_LOW
            )

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val CHANNEL_ID = "ccs_live_location"
        private const val NOTIFICATION_ID = 1001
        private const val PUBLIC_AUDIENCE_MARKER = "__public__"
    }
}
