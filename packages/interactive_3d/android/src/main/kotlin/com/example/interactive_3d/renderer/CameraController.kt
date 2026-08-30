package com.example.interactive_3d.renderer

import android.os.Handler
import android.os.Looper
import com.google.android.filament.Camera
import kotlin.math.cos
import kotlin.math.sin

/**
 * Controls the orbit camera around the 3D model.
 *
 * Munja showroom behaviour:
 * - Horizontal orbit is continuous and supports unrestricted 360-degree rotation.
 * - Vertical orbit is intentionally kept very small so the bike stays in a
 *   premium product-showroom angle.
 * - Pinch zoom remains available.
 *
 * Uses spherical coordinates ([orbitAngleX], [orbitAngleY]) and a radius
 * derived from the model bounding box. Gesture input is throttled to avoid
 * overloading the GPU with redundant projection updates.
 *
 * Also manages adaptive frame pacing state: [isInteracting] tracks whether
 * the user is actively touching the viewport. The render loop reads this
 * flag to throttle frame rate when idle.
 */
internal class CameraController {

    companion object {
        private const val DEFAULT_FOV = 45.0
        private const val NEAR_PLANE = 0.001
        private const val FAR_PLANE = 1000.0
        private const val THROTTLE_MS = 8L

        // -----------------------------------------------------------------
        // MUNJA SHOWROOM CAMERA BEHAVIOUR
        // -----------------------------------------------------------------
        //
        // Horizontal orbit is deliberately NOT clamped.
        // The user can rotate continuously through 360 degrees and keep going
        // in either direction.
        //
        // Keep vertical movement subtle: about +/- 8.5 degrees.
        private const val MIN_ORBIT_X = -0.15f
        private const val MAX_ORBIT_X = 0.15f

        // Slightly slower than the original 0.02f so the showroom feels
        // controlled rather than like a free 3D editor.
        private const val HORIZONTAL_PAN_SENSITIVITY = 0.012f
        private const val VERTICAL_PAN_SENSITIVITY = 0.006f

        // Default showroom starting angle.
        // The GLB's own orientation determines the exact visual 3/4 look,
        // so we keep the native center at zero and limit movement around it.
        private const val DEFAULT_ORBIT_X = 0.0f
        private const val DEFAULT_ORBIT_Y = 0.0f
    }

    // Spherical orbit state
    var orbitRadius = 5.0f
        private set

    var orbitAngleX = DEFAULT_ORBIT_X
        private set

    var orbitAngleY = DEFAULT_ORBIT_Y
        private set

    var targetPosition = floatArrayOf(0f, 0f, 0f)
        private set

    private var fittedCenter = floatArrayOf(0f, 0f, 0f)
    private var fittedHalfExtent = floatArrayOf(1f, 1f, 1f)

    var zoomLevel = 1.0f
        private set

    // Adaptive frame pacing
    var isInteracting = false
        private set

    var idleFrameCount = 0

    private var lastCameraUpdate = 0L

    private val idleHandler = Handler(
        Looper.getMainLooper()
    )

    private val markIdleRunnable = Runnable {
        isInteracting = false
        idleFrameCount = 0
    }

    val fov: Double
        get() = DEFAULT_FOV

    val nearPlane: Double
        get() = NEAR_PLANE

    val farPlane: Double
        get() = FAR_PLANE

    /**
     * Applies the current spherical coordinates to the Filament [camera].
     */
    fun applyToCamera(camera: Camera) {
        val radius = orbitRadius / zoomLevel

        val x =
            radius *
                cos(orbitAngleX.toDouble()) *
                sin(orbitAngleY.toDouble())

        val y =
            radius *
                sin(orbitAngleX.toDouble())

        val z =
            radius *
                cos(orbitAngleX.toDouble()) *
                cos(orbitAngleY.toDouble())

        camera.lookAt(
            x + targetPosition[0].toDouble(),
            y + targetPosition[1].toDouble(),
            z + targetPosition[2].toDouble(),
            targetPosition[0].toDouble(),
            targetPosition[1].toDouble(),
            targetPosition[2].toDouble(),
            0.0,
            1.0,
            0.0
        )
    }

    /**
     * Sets up the perspective projection on [camera] for the given viewport.
     */
    fun applyProjection(
        camera: Camera,
        width: Int,
        height: Int
    ) {
        camera.setProjection(
            DEFAULT_FOV / zoomLevel,
            if (height > 0) {
                width.toDouble() / height.toDouble()
            } else {
                1.0
            },
            NEAR_PLANE,
            FAR_PLANE,
            Camera.Fov.VERTICAL
        )
    }

    /**
     * Positions the camera to frame the model based on its bounding box.
     *
     * The model is normalized so it fills roughly 70% of the viewport
     * regardless of its real-world dimensions. [center] and [halfExtent]
     * come from the Filament asset bounding box.
     */
    fun fitToBoundingBox(
        center: FloatArray,
        halfExtent: FloatArray
    ) {
        fittedCenter = floatArrayOf(
            center[0],
            center[1],
            center[2]
        )

        fittedHalfExtent = floatArrayOf(
            halfExtent[0],
            halfExtent[1],
            halfExtent[2]
        )

        targetPosition = fittedCenter.copyOf()

        val maxExtent = maxOf(
            halfExtent[0],
            halfExtent[1],
            halfExtent[2]
        )

        val targetWorldSize = 2.0f

        val normalizedScale =
            if (maxExtent > 0) {
                targetWorldSize / maxExtent
            } else {
                1.0f
            }

        val fovRadians =
            Math.toRadians(DEFAULT_FOV)

        val fitDistance =
            targetWorldSize /
                Math.tan(
                    fovRadians / 8.0
                ).toFloat()

        orbitRadius =
            (fitDistance * 1.4f) /
                normalizedScale

        // Always return to the controlled showroom center whenever a model
        // is fitted/reloaded.
        orbitAngleX = DEFAULT_ORBIT_X
        orbitAngleY = DEFAULT_ORBIT_Y
    }

    /**
     * Sets the zoom level directly (e.g. from the public API).
     */
    fun setZoom(zoom: Float) {
        if (zoom <= 0) {
            return
        }

        zoomLevel =
            zoom.coerceIn(
                0.5f,
                6.0f
            )
    }

    /**
     * Handles a pan gesture.
     *
     * Horizontal motion is continuous and intentionally unrestricted.
     * Vertical motion is heavily constrained to keep the bike visually grounded
     * on the showroom platform.
     *
     * Returns true if the camera was updated, false if throttled.
     */
    fun onPan(
        deltaX: Float,
        deltaY: Float
    ): Boolean {
        if (!shouldUpdate()) {
            return false
        }

        markInteracting()

        val nextOrbitY =
            orbitAngleY -
                deltaX *
                HORIZONTAL_PAN_SENSITIVITY

        val nextOrbitX =
            orbitAngleX +
                deltaY *
                VERTICAL_PAN_SENSITIVITY

        // Continuous horizontal 360-degree orbit.
        //
        // Keep the value normalized to roughly -PI..PI so it does not grow
        // indefinitely during very long sessions, while preserving seamless
        // rotation through every full revolution.
        orbitAngleY = normalizeRadians(nextOrbitY)

        // Vertical movement remains intentionally constrained so the bike
        // stays visually grounded instead of flipping over.
        orbitAngleX =
            nextOrbitX.coerceIn(
                MIN_ORBIT_X,
                MAX_ORBIT_X
            )

        return true
    }

    /**
     * Sets the horizontal orbit angle programmatically.
     *
     * Used by Munja's native showroom animation. The value is normalized to
     * roughly -PI..PI so long-running animation stays numerically stable.
     *
     * Manual pan continues to use the exact same [orbitAngleY] state, which
     * means switching between automatic showroom motion and finger-driven
     * 360-degree rotation is seamless.
     */
    fun setHorizontalOrbitAngle(angleRadians: Float) {
        orbitAngleY = normalizeRadians(angleRadians)
        idleFrameCount = 0
    }

    fun setCameraPose(
        horizontalDegrees: Float,
        verticalDegrees: Float,
        targetHeightFactor: Float,
        zoom: Float
    ) {
        orbitAngleY = normalizeRadians(
            Math.toRadians(horizontalDegrees.toDouble()).toFloat()
        )

        orbitAngleX =
            Math.toRadians(verticalDegrees.toDouble())
                .toFloat()
                .coerceIn(
                    Math.toRadians(-30.0).toFloat(),
                    Math.toRadians(30.0).toFloat()
                )

        val h = targetHeightFactor.coerceIn(-1.0f, 1.25f)

        targetPosition = floatArrayOf(
            fittedCenter[0],
            fittedCenter[1] + fittedHalfExtent[1] * h,
            fittedCenter[2]
        )

        zoomLevel = zoom.coerceIn(0.5f, 6.0f)
        idleFrameCount = 0
    }

    /**
     * Handles a pinch-to-zoom gesture.
     *
     * Returns true if the camera was updated.
     */
    fun onScale(scale: Float): Boolean {
        if (!shouldUpdate()) {
            return false
        }

        markInteracting()

        val factor =
            if (scale > 1.0f) {
                1.0f +
                    (scale - 1.0f) *
                    0.15f
            } else {
                1.0f -
                    (1.0f - scale) *
                    0.15f
            }

        zoomLevel =
            (zoomLevel * factor).coerceIn(
                0.5f,
                3.0f
            )

        return true
    }

    /**
     * Marks the viewport as actively being touched.
     *
     * Call on tap, pan, or scale start. The idle timeout resets each time.
     */
    fun markInteracting() {
        isInteracting = true
        idleFrameCount = 0

        idleHandler.removeCallbacks(
            markIdleRunnable
        )

        idleHandler.postDelayed(
            markIdleRunnable,
            500
        )
    }

    /**
     * Cancels any pending idle callbacks.
     *
     * Call during cleanup.
     */
    fun cancelCallbacks() {
        idleHandler.removeCallbacks(
            markIdleRunnable
        )
    }

    /**
     * Normalizes an angle to approximately -PI..PI.
     *
     * This keeps continuous showroom rotation numerically stable while still
     * allowing the user to pass through 360 degrees indefinitely.
     */
    private fun normalizeRadians(angle: Float): Float {
        val twoPi = (Math.PI * 2.0).toFloat()
        var normalized = angle % twoPi

        if (normalized > Math.PI.toFloat()) {
            normalized -= twoPi
        } else if (normalized < -Math.PI.toFloat()) {
            normalized += twoPi
        }

        return normalized
    }

    private fun shouldUpdate(): Boolean {
        val now =
            System.currentTimeMillis()

        if (
            now - lastCameraUpdate <
            THROTTLE_MS
        ) {
            return false
        }

        lastCameraUpdate = now

        return true
    }
}
