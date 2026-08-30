package com.example.interactive_3d

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import com.example.interactive_3d.renderer.FilamentRenderer
import java.nio.ByteBuffer

/**
 * Bridges Flutter's SurfaceProducer with the Filament renderer.
 *
 * Manages the surface lifecycle: creates a [FilamentRenderer] when the
 * surface first becomes available, destroys and recreates the SwapChain
 * on app background/resume, and queues model/environment loads that
 * arrive before the surface is ready.
 */
class Interactive3dTextureEntry(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val messenger: BinaryMessenger,
    private val width: Int,
    private val height: Int
) : TextureRegistry.SurfaceProducer.Callback {

    private companion object {
        const val TAG = "Interactive3dTexture"
    }

    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var filamentRenderer: FilamentRenderer? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // Operations queued before the surface is available
    private var pendingModelLoad: (() -> Unit)? = null
    private var pendingEnvironmentLoad: (() -> Unit)? = null

    private var currentWidth: Int = width
    private var currentHeight: Int = height

    /**
     * Creates the SurfaceProducer and returns the texture ID used by
     * Flutter's [Texture] widget. Returns -1 on failure.
     */
    fun initialize(): Long {
        try {
            surfaceProducer = textureRegistry.createSurfaceProducer()
            val producer = surfaceProducer ?: return -1L

            producer.setSize(width, height)
            producer.setCallback(this)

            val textureId = producer.id()

            eventChannel = EventChannel(
                messenger,
                "interactive_3d_events_$textureId"
            )

            eventChannel?.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(
                        arguments: Any?,
                        events: EventChannel.EventSink?
                    ) {
                        eventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                }
            )

            mainHandler.post {
                initializeRendererIfReady()
            }

            return textureId
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Initialization failed: ${e.message}",
                e
            )
            return -1L
        }
    }

    override fun onSurfaceAvailable() {
        mainHandler.post {
            initializeRendererIfReady()
            drainPendingOperationsIfReady()
        }
    }

    override fun onSurfaceCleanup() {
        mainHandler.post {
            filamentRenderer?.destroySwapChain()
        }
    }

    private fun initializeRendererIfReady() {
        val producer = surfaceProducer ?: return
        val surface = producer.getSurface()

        if (!surface.isValid) {
            return
        }

        if (filamentRenderer == null) {
            filamentRenderer = FilamentRenderer(
                context,
                currentWidth,
                currentHeight
            )

            filamentRenderer?.setSelectionListener {
                sendSelectionEvent(it)
            }

            filamentRenderer?.setCacheSelectionListener {
                sendCacheSelectionEvent(it)
            }

            filamentRenderer?.setSelectionRejectedListener {
                sendSelectionRejectedEvent(it)
            }
        }

        filamentRenderer?.createSwapChain(
            producer.getSurface()
        )

        filamentRenderer?.startRenderLoop()

        // Surface + renderer are now ready. A model/environment request may have
        // arrived slightly earlier than this callback, so always drain the queue
        // here as well. This closes the race where onSurfaceAvailable fires before
        // Dart's loadModel() reaches the native texture entry.
        drainPendingOperationsIfReady()
    }

    /**
     * Executes model/environment loads that arrived before the native surface
     * and renderer were both ready.
     *
     * Important: the pending callback is cleared BEFORE invocation so a nested
     * renderer/surface callback cannot execute the same load twice.
     */
    private fun drainPendingOperationsIfReady() {
        val producer = surfaceProducer ?: return
        val renderer = filamentRenderer ?: return
        val surface = producer.getSurface()

        if (!surface.isValid) {
            return
        }

        val modelLoad = pendingModelLoad
        pendingModelLoad = null
        modelLoad?.invoke()

        val environmentLoad = pendingEnvironmentLoad
        pendingEnvironmentLoad = null
        environmentLoad?.invoke()

        Log.d(
            TAG,
            "MUNJA PENDING LOAD DRAIN: " +
                "rendererReady=${renderer.isModelLoaded()} | " +
                "modelQueued=${modelLoad != null} | " +
                "environmentQueued=${environmentLoad != null}"
        )
    }

    // -- Delegated operations -------------------------------------------------

    /**
     * MUNJA MODEL READINESS
     *
     * Returns true only when the native Filament renderer exists and its
     * ModelLoader has a live current asset marked as loaded.
     */
    fun isModelLoaded(): Boolean {
        val ready = filamentRenderer?.isModelLoaded() == true

        Log.d(
            TAG,
            "MUNJA MODEL READY CHECK: ready=$ready"
        )

        return ready
    }

    fun updateSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) {
            return
        }

        currentWidth = width
        currentHeight = height

        surfaceProducer?.setSize(
            width,
            height
        )

        filamentRenderer?.updateViewport(
            width,
            height
        )
    }

    fun loadModel(
        buffer: ByteBuffer,
        fileName: String,
        resources: Map<String, ByteArray>,
        preselectedEntities: List<String>?,
        selectionColor: List<Double>?,
        patchColors: List<Map<String, Any>>?,
        enableCache: Boolean,
        cacheColor: List<Double>?,
        clearSelectionsOnHighlight: Boolean = false,
        selectionSequence: List<Map<String, Any>>? = null,
        initialMaterialOverrides: List<Map<String, Any>>? = null
    ) {
        Log.i(
            TAG,
            "MUNJA TEXTURE LOAD ENTER: " +
                "file=$fileName | bytes=${buffer.remaining()} | " +
                "rendererExists=${filamentRenderer != null} | " +
                "surfaceValid=${surfaceProducer?.getSurface()?.isValid == true}"
        )

        val op = {
            Log.i(
                TAG,
                "MUNJA TEXTURE LOAD OP INVOKE: " +
                    "file=$fileName | rendererExists=${filamentRenderer != null}"
            )

            filamentRenderer?.loadModel(
                buffer,
                fileName,
                resources,
                preselectedEntities,
                selectionColor,
                patchColors,
                enableCache,
                cacheColor,
                clearSelectionsOnHighlight,
                selectionSequence,
                initialMaterialOverrides
            )
        }

        mainHandler.post {
            Log.i(
                TAG,
                "MUNJA TEXTURE LOAD MAIN POST: " +
                    "file=$fileName | rendererExists=${filamentRenderer != null} | " +
                    "surfaceValid=${surfaceProducer?.getSurface()?.isValid == true}"
            )

            // Always queue first. initializeRendererIfReady() may be the call
            // that creates the renderer for this texture, and it will drain the
            // queued operation as soon as the surface is valid.
            pendingModelLoad = {
                op()
                Unit
            }

            Log.i(
                TAG,
                "MUNJA TEXTURE LOAD QUEUED: file=$fileName"
            )

            initializeRendererIfReady()
            drainPendingOperationsIfReady()
        }
    }

    fun loadEnvironment(
        iblBuffer: ByteBuffer,
        skyboxBuffer: ByteBuffer
    ) {
        val op = {
            filamentRenderer?.loadEnvironment(
                iblBuffer,
                skyboxBuffer
            )
        }

        mainHandler.post {
            pendingEnvironmentLoad = {
                op()
                Unit
            }

            initializeRendererIfReady()
            drainPendingOperationsIfReady()
        }
    }

    fun setCameraZoomLevel(zoom: Float) =
        mainHandler.post {
            filamentRenderer?.setCameraZoomLevel(zoom)
        }

    fun setCameraPose(
        horizontalDegrees: Float,
        verticalDegrees: Float,
        targetHeightFactor: Float,
        zoom: Float
    ) =
        mainHandler.post {
            filamentRenderer?.setCameraPose(
                horizontalDegrees = horizontalDegrees,
                verticalDegrees = verticalDegrees,
                targetHeightFactor = targetHeightFactor,
                zoom = zoom
            )
        }

    fun setPartGroupVisibility(
        group: Map<String, Any>,
        isVisible: Boolean
    ) =
        mainHandler.post {
            filamentRenderer?.setPartGroupVisibility(
                group,
                isVisible
            )
        }

    /**
     * MUNJA EXCLUSIVE FRAME VISIBILITY
     *
     * Keeps exactly one named frame entity visible and hides the rest.
     *
     * Example:
     *   entityNames = ["Frame 1", "FRAME 2", "FRAME 3", "frame 4"]
     *   activeEntityName = "FRAME 2"
     *
     * The renderer only changes scene visibility. It does not touch the
     * original GLB material, UVs, textures, normal maps, metallic maps,
     * or roughness maps.
     */
    fun setExclusiveEntityVisibility(
        entityNames: List<String>,
        activeEntityName: String
    ) {
        mainHandler.post {
            val success =
                filamentRenderer?.setExclusiveEntityVisibility(
                    entityNames = entityNames,
                    activeEntityName = activeEntityName
                ) ?: false

            Log.i(
                TAG,
                "MUNJA FRAME VISIBILITY REQUEST: " +
                    "active=$activeEntityName | " +
                    "managed=$entityNames | " +
                    "success=$success"
            )
        }
    }

    fun unselectEntities(entityIds: List<Long>?) =
        mainHandler.post {
            filamentRenderer?.unselectEntities(entityIds)
        }

    fun clearCache() =
        mainHandler.post {
            filamentRenderer?.clearCacheAndRestoreSelections()
        }

    fun refreshCacheHighlights() =
        mainHandler.post {
            filamentRenderer?.refreshCacheHighlights()
        }

    fun removeFromCache(names: List<String>) =
        mainHandler.post {
            filamentRenderer?.removeFromCache(names)
        }

    fun setEntityMaterials(
        overrides: List<Map<String, Any>>
    ) =
        mainHandler.post {
            filamentRenderer?.setEntityMaterials(overrides)
        }

    fun resetEntityMaterials(
        names: List<String>?
    ) =
        mainHandler.post {
            filamentRenderer?.resetEntityMaterials(names)
        }

    /**
     * MUNJA SAFE FRAME COLOR
     *
     * Applies baseColorFactor directly to the MaterialInstance currently
     * assigned to the named entity. The renderer owns the actual Filament
     * operation; this bridge only ensures it runs on the main thread.
     */
    fun setEntityBaseColor(
        entityName: String,
        rgba: List<Double>
    ) {
        mainHandler.post {
            val success =
                filamentRenderer?.setEntityBaseColor(
                    entityName = entityName,
                    rgba = rgba
                ) ?: false

            Log.i(
                TAG,
                "MUNJA FRAME COLOR REQUEST: " +
                    "$entityName | rgba=$rgba | success=$success"
            )
        }
    }

    /**
     * MUNJA DIRECT MATERIAL SWAP
     *
     * Delegates to FilamentRenderer.setEntityMaterialInstance().
     *
     * This lets Flutter select an existing MaterialInstance that is already
     * embedded in the loaded GLB, even when KHR_materials_variants is absent.
     *
     * Example:
     *   entityName = "Frame 1"
     *   materialInstanceName = "Titanium_Frame_1"
     */
    fun setEntityMaterialInstance(
        entityName: String,
        materialInstanceName: String
    ) {
        mainHandler.post {
            val success =
                filamentRenderer?.setEntityMaterialInstance(
                    entityName,
                    materialInstanceName
                ) ?: false

            Log.i(
                TAG,
                "MUNJA DIRECT MATERIAL REQUEST: " +
                    "$entityName -> $materialInstanceName | " +
                    "success=$success"
            )
        }
    }

    /**
     * Restores the original GLB material(s) for one entity after a direct
     * material swap.
     */
    fun resetEntityDirectMaterial(
        entityName: String
    ) {
        mainHandler.post {
            val success =
                filamentRenderer?.resetEntityDirectMaterial(
                    entityName
                ) ?: false

            Log.i(
                TAG,
                "MUNJA DIRECT MATERIAL RESET REQUEST: " +
                    "$entityName | success=$success"
            )
        }
    }

    /**
     * Restores all direct material swaps performed through
     * setEntityMaterialInstance().
     */
    fun resetAllDirectMaterials() {
        mainHandler.post {
            val success =
                filamentRenderer?.resetAllDirectMaterials()
                    ?: false

            Log.i(
                TAG,
                "MUNJA DIRECT MATERIAL RESET ALL REQUEST: " +
                    "success=$success"
            )
        }
    }

    /**
     * Starts native Filament showroom orbit for this texture.
     */
    fun startShowroomRotation(
        amplitudeDegrees: Float,
        durationMs: Long,
        resumeDelayMs: Long
    ) =
        mainHandler.post {
            filamentRenderer?.startShowroomRotation(
                amplitudeDegrees,
                durationMs,
                resumeDelayMs
            )
        }

    /**
     * Stops native showroom orbit for this texture.
     */
    fun stopShowroomRotation() =
        mainHandler.post {
            filamentRenderer?.stopShowroomRotation()
        }

    fun onTap(
        x: Float,
        y: Float
    ) =
        mainHandler.post {
            filamentRenderer?.onTap(
                x.toInt(),
                y.toInt()
            )
        }

    fun onPan(
        deltaX: Float,
        deltaY: Float
    ) =
        mainHandler.post {
            filamentRenderer?.onPan(
                deltaX,
                deltaY
            )
        }

    fun onScale(scale: Float) =
        mainHandler.post {
            filamentRenderer?.onScale(scale)
        }

    fun setBackgroundColor(
        color: List<Double>
    ) {
        mainHandler.post {
            filamentRenderer?.setBackgroundColor(color)
        }
    }

    // -- Events ---------------------------------------------------------------

    private fun sendSelectionEvent(
        entities: List<Map<String, Any>>
    ) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "event" to "selectionChanged",
                    "selectedEntities" to entities
                )
            )
        }
    }

    private fun sendCacheSelectionEvent(
        entities: List<Map<String, Any>>
    ) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "event" to "cacheSelectionChanged",
                    "cachedEntities" to entities
                )
            )
        }
    }

    private fun sendSelectionRejectedEvent(
        name: String
    ) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "event" to "selectionRejected",
                    "name" to name
                )
            )
        }
    }

    // -- Cleanup --------------------------------------------------------------

    fun dispose() {
        eventSink = null

        eventChannel?.setStreamHandler(null)
        eventChannel = null

        mainHandler.removeCallbacksAndMessages(null)

        filamentRenderer?.cleanup()
        filamentRenderer = null

        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducer = null

        pendingModelLoad = null
        pendingEnvironmentLoad = null
    }
}
