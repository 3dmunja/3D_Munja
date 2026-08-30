package com.example.interactive_3d.renderer

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import com.google.android.filament.*
import com.google.android.filament.gltfio.*
import com.example.interactive_3d.Interactive3dCacheManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.sin

/**
 * Core Filament renderer for the interactive_3d plugin.
 *
 * Owns the Filament [Engine], [Renderer], [Scene], and [View], and
 * coordinates the sub-managers that handle camera, environment, model
 * loading, and entity selection. All Filament API calls happen on the
 * main thread; background work is limited to file I/O.
 *
 * Render loop uses [Choreographer] with adaptive frame pacing:
 * full 60 fps during interaction, 30 fps after a brief idle, and fully
 * paused after ~1.5 seconds of no input.
 */
class FilamentRenderer(
    private val context: Context,
    private var width: Int,
    private var height: Int
) {

    private companion object {
        const val TAG = "FilamentRenderer"
    }

    // Filament core objects
    private var engine: Engine? = null
    private var renderer: Renderer? = null
    private var scene: Scene? = null
    private var filamentView: View? = null
    private var camera: Camera? = null
    private var cameraEntity: Int = 0
    private var swapChain: SwapChain? = null

    @Volatile
    private var cleaningUp = false

    @Volatile
    private var destroyed = false

    // GLTF infrastructure
    private var materialProvider: MaterialProvider? = null
    private var assetLoader: AssetLoader? = null
    private var resourceLoader: ResourceLoader? = null

    // MUNJA direct material-swap state.
    //
    // The current GLB was exported without KHR_materials_variants, but gltfio
    // still exposes the MaterialInstance objects that are actually embedded in
    // the file. We can therefore assign one of those existing instances directly
    // to a frame renderable at runtime.
    //
    // Backups are kept per entity + primitive so we can restore the original GLB
    // material cleanly after a proof-of-concept swap.
    private val directMaterialBackups =
        mutableMapOf<Int, MutableMap<Int, MaterialInstance>>()

    // MUNJA SAFE FRAME COLOR:
    // Never destroy/clone a gltfio MaterialInstance while a Renderable references it.
    // Frame colors are applied directly to the currently assigned instance by changing
    // baseColorFactor, then requestRender() wakes the adaptive render loop.

    // Sub-managers
    internal val cameraController = CameraController()
    internal val environment = EnvironmentLoader()
    internal val modelLoader = ModelLoader()
    internal val selection = SelectionManager()
    internal val sequenceValidator = SequenceValidator()

    // Notified when a tap is rejected by sequence validation
    private var onSelectionRejected: ((String) -> Unit)? = null

    // Device-adaptive settings
    private val deviceTier: DeviceCapability.Tier
    private val quality: DeviceCapability.QualitySettings
    private val renderScale: Float

    // Render loop
    private val choreographer = Choreographer.getInstance()
    private var isRendering = false
    private val frameCallback = FrameCallback()
    private val mainHandler = Handler(Looper.getMainLooper())

    // ---------------------------------------------------------------------
    // MUNJA NATIVE SHOWROOM ROTATION
    // ---------------------------------------------------------------------
    //
    // The automatic motion is performed directly on Filament's camera inside
    // the existing Choreographer loop. No 60-fps MethodChannel traffic is used.
    //
    // The animation always oscillates around the user's current horizontal
    // orbit. Manual finger rotation therefore becomes the new center point.
    private var showroomRotationEnabled = false
    private var showroomAmplitudeRadians = Math.toRadians(10.0).toFloat()
    private var showroomCycleDurationNanos = 2_600_000_000L
    private var showroomResumeDelayNanos = 2_000_000_000L
    private var showroomCenterAngleY = 0.0f
    private var showroomCycleStartNanos = 0L
    private var showroomLastInteractionNanos = 0L

    // Background I/O (no Filament calls allowed on this scope)
    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    init {
        deviceTier = DeviceCapability.detectTier(context)
        quality = DeviceCapability.settingsFor(deviceTier)
        renderScale = DeviceCapability.renderScaleFor(deviceTier)
        Log.d(TAG, "Device: $deviceTier, MSAA: ${quality.msaaSamples}x, scale: ${renderScale}x")

        initializeEngine()
    }

    // -------------------------------------------------------------------------
    // Engine Initialization
    // -------------------------------------------------------------------------

    private fun initializeEngine() {
        engine = Engine.create()
        val eng = engine ?: throw IllegalStateException("Failed to create Filament Engine")

        renderer = eng.createRenderer()
        scene = eng.createScene()
        filamentView = eng.createView().also { it.setScene(scene) }

        cameraEntity = EntityManager.get().create()
        camera = eng.createCamera(cameraEntity)
        filamentView?.camera = camera

        // Initial camera and exposure
        camera?.let { cam ->
            cameraController.applyProjection(cam, width, height)
            cameraController.applyToCamera(cam)
            cam.setExposure(16.0f, 1.0f / 125.0f, 50.0f)
        }

        environment.setupDefaultLighting(eng, scene!!)
        configureView()

        scene?.skybox = null

        // Post-processing disabled — color output goes straight to the surface.
        // MSAA still works at hardware level without the post-processing pipeline.
        filamentView?.isPostProcessingEnabled = true
        filamentView?.multiSampleAntiAliasingOptions = filamentView!!.multiSampleAntiAliasingOptions.apply {
            enabled = true
            sampleCount = 4
        }

        // Linear tone mapping avoids washed-out colors in the Texture API path
        filamentView?.colorGrading = ColorGrading.Builder()
            .toneMapper(ToneMapper.Linear())
            .build(eng)

        materialProvider = UbershaderProvider(eng)
        assetLoader = AssetLoader(eng, materialProvider!!, EntityManager.get())
        resourceLoader = ResourceLoader(eng, true)
    }

    /**
     * Configures Filament view options based on the detected device tier.
     *
     * Dynamic resolution is always disabled because certain Mali GPUs produce
     * blurred output when the internal resolution doesn't match the surface.
     */
    private fun configureView() {
        val v = filamentView ?: return

        v.antiAliasing = View.AntiAliasing.NONE

        // Dynamic resolution disabled to prevent GPU-driver blur on certain chipsets
        v.dynamicResolutionOptions = v.dynamicResolutionOptions.apply {
            enabled = false
            quality = View.QualityLevel.HIGH
        }

        v.multiSampleAntiAliasingOptions = v.multiSampleAntiAliasingOptions.apply {
            enabled = quality.msaaSamples > 0
            sampleCount = quality.msaaSamples
        }

        v.ambientOcclusionOptions = v.ambientOcclusionOptions.apply {
            enabled = false
            quality = if (deviceTier == DeviceCapability.Tier.HIGH_END)
                View.QualityLevel.HIGH else View.QualityLevel.LOW
        }

        v.bloomOptions = v.bloomOptions.apply {
            enabled = false
            quality = if (deviceTier == DeviceCapability.Tier.HIGH_END)
                View.QualityLevel.HIGH else View.QualityLevel.LOW
        }

        v.temporalAntiAliasingOptions = v.temporalAntiAliasingOptions.apply { enabled = false }
        v.dithering = View.Dithering.TEMPORAL
        v.blendMode = if (environment.useSolidBackground)
            View.BlendMode.OPAQUE else View.BlendMode.TRANSLUCENT

        v.renderQuality = v.renderQuality.apply {
            hdrColorBuffer = if (deviceTier == DeviceCapability.Tier.HIGH_END)
                View.QualityLevel.HIGH else View.QualityLevel.MEDIUM
        }

        renderer?.let { environment.applyClearColor(it) }
    }

    // -------------------------------------------------------------------------
    // SwapChain / Surface
    // -------------------------------------------------------------------------

    fun createSwapChain(surface: Surface) {
        if (destroyed || cleaningUp) return

        val eng = engine ?: return
        destroySwapChain()

        // In createSwapChain, when solid background is used:
        swapChain = if (environment.useSolidBackground) {
            eng.createSwapChain(surface)  // No flags = opaque
        } else {
            eng.createSwapChain(surface, SwapChainFlags.CONFIG_TRANSPARENT)
        }
        filamentView?.viewport = Viewport(0, 0, width, height)
        camera?.let {
            cameraController.applyProjection(it, width, height)
            cameraController.applyToCamera(it)
        }
    }

    fun destroySwapChain() {
        val eng = engine
        val chain = swapChain

        // Null the field first so the render callback cannot pick up a chain
        // that is already being destroyed.
        swapChain = null

        if (eng != null && chain != null) {
            try {
                eng.destroySwapChain(chain)
            } catch (t: Throwable) {
                Log.e(TAG, "MUNJA SWAPCHAIN DESTROY ERROR: ${t.message}", t)
            }
        }
    }

    fun updateViewport(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        this.width = width
        this.height = height

        filamentView?.viewport = Viewport(0, 0, width, height)
        camera?.let { cameraController.applyProjection(it, width, height) }
    }

    // -------------------------------------------------------------------------
    // Render Loop
    // -------------------------------------------------------------------------

    fun startRenderLoop() {
        if (destroyed || cleaningUp || isRendering) return
        isRendering = true
        choreographer.postFrameCallback(frameCallback)
    }

    fun stopRenderLoop() {
        isRendering = false
        choreographer.removeFrameCallback(frameCallback)
    }

    /**
     * Wakes the render loop from idle so that material/scene changes
     * are drawn to screen. Call after any programmatic visual change
     * (clear, refresh, visibility toggle, etc.).
     */
    private fun requestRender() {
        if (destroyed || cleaningUp) return
        cameraController.markInteracting()
    }

    // -------------------------------------------------------------------------
    // Model Loading
    // -------------------------------------------------------------------------

    /**
     * Returns true only when ModelLoader has completed loading and a current
     * FilamentAsset is available. Used by the Flutter side to avoid sending
     * frame/skin commands before the GLB is ready.
     */
    fun isModelLoaded(): Boolean {
        if (destroyed || cleaningUp) return false
        return modelLoader.modelLoaded && modelLoader.currentAsset != null
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
        if (destroyed || cleaningUp) {
            Log.w(
                TAG,
                "MUNJA RENDERER LOAD BLOCKED: renderer is disposing/destroyed | file=$fileName"
            )
            return
        }

        Log.i(
            TAG,
            "MUNJA RENDERER LOAD ENTER: " +
                "file=$fileName | bytes=${buffer.remaining()} | " +
                "engine=${engine != null} | scene=${scene != null} | " +
                "assetLoader=${assetLoader != null} | resourceLoader=${resourceLoader != null}"
        )

        val eng = engine ?: run {
            Log.e(TAG, "MUNJA RENDERER LOAD STOP: engine=null | file=$fileName")
            return
        }
        val scn = scene ?: run {
            Log.e(TAG, "MUNJA RENDERER LOAD STOP: scene=null | file=$fileName")
            return
        }
        val loader = assetLoader ?: run {
            Log.e(TAG, "MUNJA RENDERER LOAD STOP: assetLoader=null | file=$fileName")
            return
        }
        val resLoader = resourceLoader ?: run {
            Log.e(TAG, "MUNJA RENDERER LOAD STOP: resourceLoader=null | file=$fileName")
            return
        }

        // Clean up previous model
        selection.reset(eng)
        selection.iblLoaded = environment.iblLoaded
        directMaterialBackups.clear()
        modelLoader.cleanupCurrentModel(scn, loader)

        // Configure selection
        selection.selectionColor = selectionColor.toFloatArrayOrDefault(floatArrayOf(0f, 1f, 0f, 1f))
        selection.patchColors = patchColors
        selection.enableCache = enableCache
        selection.clearSelectionsOnHighlight = clearSelectionsOnHighlight

        // Configure sequence validation (active whenever the list is non-empty)
        if (selectionSequence != null) {
            sequenceValidator.configure(selectionSequence)
        } else {
            sequenceValidator.reset()
        }

        if (enableCache) {
            selection.cacheColor = cacheColor.toFloatArrayOrDefault(floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f))
            selection.cacheManager = Interactive3dCacheManager(context, fileName, selection.cacheColor)
        }

        // Load
        Log.i(
            TAG,
            "MUNJA RENDERER -> MODELLOADER START: file=$fileName"
        )

        val asset = modelLoader.loadModel(
            eng,
            scn,
            loader,
            resLoader,
            buffer,
            fileName,
            resources
        ) ?: run {
            Log.e(
                TAG,
                "MUNJA RENDERER -> MODELLOADER FAILED: file=$fileName"
            )
            return
        }

        Log.i(
            TAG,
            "MUNJA RENDERER -> MODELLOADER SUCCESS: " +
                "file=$fileName | ready=${modelLoader.modelLoaded} | " +
                "asset=${modelLoader.currentAsset != null}"
        )

        // MUNJA: expose the exact KHR_materials_variants names exported in the GLB.
        // Filament 1.68.1 exposes these on FilamentInstance.
        val filamentInstance = asset.instance
        val variantNames = filamentInstance?.materialVariantNames ?: emptyArray()
        Log.i(
            TAG,
            "MUNJA GLB MATERIAL VARIANTS: ${variantNames.toList()}"
        )

        // MUNJA MATERIAL SCAN:
        // Even when no KHR_materials_variants were exported, gltfio still exposes
        // all MaterialInstance objects that actually exist in the loaded GLB.
        // We log both the instance name and its underlying Material name so we can
        // verify whether Blender materials such as Carbon_Fibre_Frame 1 were
        // really exported and are available for a direct runtime material swap.
        val loadedMaterialInstances =
            filamentInstance?.materialInstances ?: emptyArray()

        Log.i(
            TAG,
            "===== MUNJA GLB MATERIAL SCAN START | count=${loadedMaterialInstances.size} ====="
        )

        loadedMaterialInstances.forEachIndexed { index, materialInstance ->
            val instanceName = try {
                materialInstance.name
            } catch (_: Exception) {
                "<instance-name-error>"
            }

            val materialName = try {
                materialInstance.material.name
            } catch (_: Exception) {
                "<material-name-error>"
            }

            Log.i(
                TAG,
                "MUNJA GLB MATERIAL [$index] | " +
                    "instance=$instanceName | " +
                    "material=$materialName"
            )
        }

        Log.i(
            TAG,
            "===== MUNJA GLB MATERIAL SCAN END ====="
        )

        // Fit camera to model
        modelLoader.getBoundingBox()?.let { (center, halfExtent) ->
            cameraController.fitToBoundingBox(center, halfExtent)
            camera?.let {
                cameraController.applyProjection(it, width, height)
                cameraController.applyToCamera(it)
            }
        }

        // Apply overrides first so they sit underneath any selection that follows.
        if (!initialMaterialOverrides.isNullOrEmpty()) {
            selection.applyOverridesByName(initialMaterialOverrides, asset, eng)
        }

        // Apply preselections and cache highlights
        selection.applyPreselections(preselectedEntities, asset, eng)
        if (enableCache) {
            selection.highlightCachedEntities(asset, eng)
            selection.notifyCacheChanged()
        }
    }

    /**
     * Returns all KHR_materials_variants names exported in the current GLB.
     *
     * This is intentionally read from FilamentInstance instead of inferred
     * from Blender material names. Only variants actually exported into the
     * GLB are valid runtime choices.
     */
    /**
     * Returns the names of all MaterialInstance objects loaded from the current
     * GLB. This is useful for Munja models that contain multiple Blender
     * materials but were exported without KHR_materials_variants.
     *
     * The returned list uses MaterialInstance.getName(), because those names are
     * the most useful runtime identifiers for the next direct-material-swap step.
     */
    fun getLoadedMaterialInstanceNames(): List<String> {
        val instance = modelLoader.currentAsset?.instance
        if (instance == null) {
            Log.w(TAG, "MUNJA GLB MATERIALS: no loaded FilamentInstance")
            return emptyList()
        }

        val names = instance.materialInstances
            .map { materialInstance ->
                try {
                    materialInstance.name
                } catch (_: Exception) {
                    "<instance-name-error>"
                }
            }

        Log.i(TAG, "MUNJA GLB MATERIAL INSTANCE NAMES: $names")
        return names
    }

    fun getMaterialVariantNames(): List<String> {
        val asset = modelLoader.currentAsset
        if (asset == null) {
            Log.w(TAG, "MUNJA MATERIAL VARIANTS: no model loaded")
            return emptyList()
        }

        val instance = asset.instance
        if (instance == null) {
            Log.w(TAG, "MUNJA MATERIAL VARIANTS: current asset has no instance")
            return emptyList()
        }

        val names = instance.materialVariantNames.toList()
        Log.i(TAG, "MUNJA GLB MATERIAL VARIANTS: $names")
        return names
    }

    /**
     * Applies a real glTF KHR_materials_variants material set by its exported
     * variant name.
     *
     * Example:
     *   setMaterialVariant("Carbon")
     *
     * Filament's applyMaterialVariant() applies the complete mapping stored in
     * the GLB, so all primitives assigned to that variant switch together.
     *
     * Returns true only when the requested variant exists and was applied.
     */
    fun setMaterialVariant(variantName: String): Boolean {
        val asset = modelLoader.currentAsset
        if (asset == null) {
            Log.w(
                TAG,
                "MUNJA MATERIAL VARIANT FAILED: no model loaded | requested=$variantName"
            )
            return false
        }

        val instance = asset.instance
        if (instance == null) {
            Log.w(
                TAG,
                "MUNJA MATERIAL VARIANT FAILED: asset has no instance | requested=$variantName"
            )
            return false
        }

        val variantNames = instance.materialVariantNames
        val variantIndex = variantNames.indexOf(variantName)

        if (variantIndex < 0) {
            Log.w(
                TAG,
                "MUNJA MATERIAL VARIANT NOT FOUND: $variantName | " +
                    "available=${variantNames.toList()}"
            )
            return false
        }

        return try {
            instance.applyMaterialVariant(variantIndex)

            // Wake the adaptive render loop so the new materials are visible
            // immediately even when the viewport was idle.
            requestRender()

            Log.i(
                TAG,
                "MUNJA MATERIAL VARIANT ACTIVE: " +
                    "$variantName -> index=$variantIndex"
            )
            true
        } catch (e: Exception) {
            Log.e(
                TAG,
                "MUNJA MATERIAL VARIANT ERROR: " +
                    "$variantName -> index=$variantIndex | ${e.message}",
                e
            )
            false
        }
    }

    /**
     * Applies an existing MaterialInstance from the loaded GLB directly to all
     * primitives of a named renderable entity.
     *
     * This is the Munja fallback for models that contain extra materials but
     * were exported without KHR_materials_variants.
     *
     * Example:
     *   setEntityMaterialInstance(
     *       entityName = "Frame 1",
     *       materialInstanceName = "Titanium_Frame_1"
     *   )
     *
     * Returns true only when both the entity and material instance exist and
     * at least one primitive was updated.
     */
    fun setEntityMaterialInstance(
        entityName: String,
        materialInstanceName: String,
    ): Boolean {
        val eng = engine
        if (eng == null) {
            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL FAILED: engine unavailable"
            )
            return false
        }

        val asset = modelLoader.currentAsset
        if (asset == null) {
            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL FAILED: no model loaded"
            )
            return false
        }

        val filamentInstance = asset.instance
        if (filamentInstance == null) {
            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL FAILED: asset has no FilamentInstance"
            )
            return false
        }

        val entity = asset.entities
            ?.firstOrNull { asset.getName(it) == entityName }

        if (entity == null) {
            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL ENTITY NOT FOUND: $entityName"
            )
            return false
        }

        val rcm = eng.renderableManager

        if (!rcm.hasComponent(entity)) {
            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL ENTITY NOT RENDERABLE: " +
                    "$entityName | entity=$entity"
            )
            return false
        }

        val targetMaterial = filamentInstance.materialInstances
            .firstOrNull { materialInstance ->
                try {
                    materialInstance.name == materialInstanceName
                } catch (_: Exception) {
                    false
                }
            }

        if (targetMaterial == null) {
            val available = filamentInstance.materialInstances
                .mapNotNull { materialInstance ->
                    try {
                        materialInstance.name
                    } catch (_: Exception) {
                        null
                    }
                }

            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL NOT FOUND: $materialInstanceName | " +
                    "available=$available"
            )
            return false
        }

        val renderableInstance = rcm.getInstance(entity)
        val primitiveCount = rcm.getPrimitiveCount(renderableInstance)

        if (primitiveCount <= 0) {
            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL NO PRIMITIVES: " +
                    "$entityName | entity=$entity"
            )
            return false
        }

        // Snapshot the GLB originals only once for this entity.
        val backup = directMaterialBackups.getOrPut(entity) {
            mutableMapOf()
        }

        for (primitiveIndex in 0 until primitiveCount) {
            if (!backup.containsKey(primitiveIndex)) {
                try {
                    backup[primitiveIndex] =
                        rcm.getMaterialInstanceAt(
                            renderableInstance,
                            primitiveIndex,
                        )
                } catch (e: Exception) {
                    Log.w(
                        TAG,
                        "MUNJA DIRECT MATERIAL BACKUP FAILED: " +
                            "$entityName primitive=$primitiveIndex | ${e.message}"
                    )
                }
            }
        }

        var appliedCount = 0

        for (primitiveIndex in 0 until primitiveCount) {
            try {
                rcm.setMaterialInstanceAt(
                    renderableInstance,
                    primitiveIndex,
                    targetMaterial,
                )
                appliedCount++
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "MUNJA DIRECT MATERIAL APPLY ERROR: " +
                        "$entityName primitive=$primitiveIndex -> " +
                        "$materialInstanceName | ${e.message}",
                    e,
                )
            }
        }

        if (appliedCount == 0) {
            return false
        }

        requestRender()

        Log.i(
            TAG,
            "MUNJA DIRECT MATERIAL ACTIVE: " +
                "$entityName -> $materialInstanceName | " +
                "primitives=$appliedCount"
        )

        return true
    }

    /**
     * Restores the original GLB material(s) for one entity after a direct
     * material swap.
     */
    fun resetEntityDirectMaterial(entityName: String): Boolean {
        val eng = engine ?: return false
        val asset = modelLoader.currentAsset ?: return false

        val entity = asset.entities
            ?.firstOrNull { asset.getName(it) == entityName }
            ?: run {
                Log.w(
                    TAG,
                    "MUNJA DIRECT MATERIAL RESET ENTITY NOT FOUND: $entityName"
                )
                return false
            }

        val backup = directMaterialBackups[entity]
        if (backup.isNullOrEmpty()) {
            Log.w(
                TAG,
                "MUNJA DIRECT MATERIAL RESET: no backup for $entityName"
            )
            return false
        }

        val rcm = eng.renderableManager
        if (!rcm.hasComponent(entity)) return false

        val renderableInstance = rcm.getInstance(entity)
        var restoredCount = 0

        backup.forEach { (primitiveIndex, materialInstance) ->
            try {
                rcm.setMaterialInstanceAt(
                    renderableInstance,
                    primitiveIndex,
                    materialInstance,
                )
                restoredCount++
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "MUNJA DIRECT MATERIAL RESET ERROR: " +
                        "$entityName primitive=$primitiveIndex | ${e.message}",
                    e,
                )
            }
        }

        directMaterialBackups.remove(entity)

        if (restoredCount > 0) {
            requestRender()
            Log.i(
                TAG,
                "MUNJA DIRECT MATERIAL RESET: " +
                    "$entityName | primitives=$restoredCount"
            )
            return true
        }

        return false
    }

    /**
     * Restores all entities modified through [setEntityMaterialInstance].
     */
    fun resetAllDirectMaterials(): Boolean {
        val eng = engine ?: return false
        val asset = modelLoader.currentAsset ?: return false
        val rcm = eng.renderableManager

        var restoredCount = 0

        directMaterialBackups.toMap().forEach { (entity, backup) ->
            if (!rcm.hasComponent(entity)) {
                return@forEach
            }

            val renderableInstance = rcm.getInstance(entity)

            backup.forEach { (primitiveIndex, materialInstance) ->
                try {
                    rcm.setMaterialInstanceAt(
                        renderableInstance,
                        primitiveIndex,
                        materialInstance,
                    )
                    restoredCount++
                } catch (e: Exception) {
                    Log.e(
                        TAG,
                        "MUNJA DIRECT MATERIAL RESET ALL ERROR: " +
                            "entity=$entity primitive=$primitiveIndex | ${e.message}",
                        e,
                    )
                }
            }
        }

        directMaterialBackups.clear()

        if (restoredCount > 0) {
            requestRender()
            Log.i(
                TAG,
                "MUNJA DIRECT MATERIAL RESET ALL: primitives=$restoredCount"
            )
            return true
        }

        return false
    }

    /**
     * MUNJA SAFE FRAME COLOR.
     *
     * Changes baseColorFactor on the MaterialInstance that is CURRENTLY assigned
     * to every primitive of [entityName].
     *
     * We deliberately do not create, clone or destroy MaterialInstances here.
     * gltfio owns the instances loaded from the GLB, and destroying an instance
     * while a Renderable still references it causes Filament to abort the app.
     *
     * [rgba] must contain 4 values in the 0..1 range.
     */
    fun setEntityBaseColor(
        entityName: String,
        rgba: List<Double>,
    ): Boolean {
        val eng = engine ?: run {
            Log.w(TAG, "MUNJA FRAME COLOR FAILED: engine unavailable")
            return false
        }

        val asset = modelLoader.currentAsset ?: run {
            Log.w(TAG, "MUNJA FRAME COLOR FAILED: no model loaded")
            return false
        }

        if (rgba.size != 4) {
            Log.w(TAG, "MUNJA FRAME COLOR FAILED: invalid RGBA=$rgba")
            return false
        }

        val entity = asset.entities
            ?.firstOrNull { asset.getName(it) == entityName }
            ?: run {
                Log.w(TAG, "MUNJA FRAME COLOR ENTITY NOT FOUND: $entityName")
                return false
            }

        val rcm = eng.renderableManager
        if (!rcm.hasComponent(entity)) {
            Log.w(
                TAG,
                "MUNJA FRAME COLOR ENTITY NOT RENDERABLE: $entityName | entity=$entity",
            )
            return false
        }

        val renderableInstance = rcm.getInstance(entity)
        val primitiveCount = rcm.getPrimitiveCount(renderableInstance)

        if (primitiveCount <= 0) {
            Log.w(TAG, "MUNJA FRAME COLOR NO PRIMITIVES: $entityName")
            return false
        }

        val r = rgba[0].toFloat().coerceIn(0f, 1f)
        val g = rgba[1].toFloat().coerceIn(0f, 1f)
        val b = rgba[2].toFloat().coerceIn(0f, 1f)
        val a = rgba[3].toFloat().coerceIn(0f, 1f)

        var changedCount = 0

        for (primitiveIndex in 0 until primitiveCount) {
            try {
                val materialInstance = rcm.getMaterialInstanceAt(
                    renderableInstance,
                    primitiveIndex,
                )

                // UbershaderProvider's base_lit_* materials expose baseColorFactor.
                // We modify the instance currently bound to the primitive.
                materialInstance.setParameter(
                    "baseColorFactor",
                    r,
                    g,
                    b,
                    a,
                )

                changedCount++

                val instanceName = try {
                    materialInstance.name
                } catch (_: Exception) {
                    "<unnamed>"
                }

                Log.i(
                    TAG,
                    "MUNJA FRAME COLOR PRIMITIVE: " +
                        "$entityName primitive=$primitiveIndex | " +
                        "material=$instanceName | rgba=[$r, $g, $b, $a]",
                )
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "MUNJA FRAME COLOR APPLY ERROR: " +
                        "$entityName primitive=$primitiveIndex | ${e.message}",
                    e,
                )
            }
        }

        if (changedCount <= 0) {
            Log.w(TAG, "MUNJA FRAME COLOR FAILED: nothing changed | $entityName")
            return false
        }

        requestRender()

        Log.i(
            TAG,
            "MUNJA FRAME COLOR ACTIVE: " +
                "$entityName | rgba=[$r, $g, $b, $a] | primitives=$changedCount",
        )

        return true
    }

    fun setEntityMaterials(overrides: List<Map<String, Any>>) {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        selection.applyOverridesByName(overrides, asset, eng)
        requestRender()
    }

    fun resetEntityMaterials(names: List<String>?) {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        selection.resetOverridesByName(names, asset, eng)
        requestRender()
    }

    // -------------------------------------------------------------------------
    // Environment
    // -------------------------------------------------------------------------

    fun loadEnvironment(iblBuffer: ByteBuffer, skyboxBuffer: ByteBuffer) {
        val eng = engine ?: return
        val scn = scene ?: return

        environment.loadEnvironment(eng, scn, iblBuffer, skyboxBuffer)

        // Enable AO/bloom now that IBL is loaded
        filamentView?.apply {
            ambientOcclusionOptions = ambientOcclusionOptions.apply { enabled = this@FilamentRenderer.quality.enableAO }
            bloomOptions = bloomOptions.apply { enabled = this@FilamentRenderer.quality.enableBloom }
        }

        // Remove default emissive now that IBL provides ambient light
        modelLoader.restoreEmissiveAfterIBL(eng)

        // Selection manager needs to know IBL state for correct reset behavior
        selection.iblLoaded = true
    }

    fun setBackgroundColor(color: List<Double>) {
        val rend = renderer ?: return
        val scn = scene ?: return
        environment.setBackgroundColor(color, rend, scn)
    }

    // -------------------------------------------------------------------------
    // Gestures
    // -------------------------------------------------------------------------

    /**
     * Starts Munja's gentle native showroom orbit.
     *
     * [amplitudeDegrees] is intentionally capped so the bike sways around a
     * premium presentation angle instead of continuously spinning.
     *
     * [durationMs] is one complete left -> right -> left cycle.
     *
     * [resumeDelayMs] controls how long we wait after manual interaction before
     * the automatic movement continues.
     */
    fun startShowroomRotation(
        amplitudeDegrees: Float,
        durationMs: Long,
        resumeDelayMs: Long
    ) {
        val safeAmplitude =
            amplitudeDegrees.coerceIn(2.0f, 30.0f)

        val safeDurationMs =
            durationMs.coerceIn(900L, 12_000L)

        val safeResumeDelayMs =
            resumeDelayMs.coerceIn(0L, 10_000L)

        showroomAmplitudeRadians =
            Math.toRadians(safeAmplitude.toDouble()).toFloat()

        showroomCycleDurationNanos =
            safeDurationMs * 1_000_000L

        showroomResumeDelayNanos =
            safeResumeDelayMs * 1_000_000L

        showroomCenterAngleY =
            cameraController.orbitAngleY

        showroomCycleStartNanos = 0L
        showroomLastInteractionNanos = System.nanoTime()
        showroomRotationEnabled = true

        // Keep the renderer awake while showroom rotation is active.
        cameraController.idleFrameCount = 0

        Log.i(
            TAG,
            "MUNJA SHOWROOM ROTATION START: " +
                "amplitude=${safeAmplitude}deg | " +
                "duration=${safeDurationMs}ms | " +
                "resumeDelay=${safeResumeDelayMs}ms | " +
                "center=${showroomCenterAngleY}rad"
        )
    }

    /**
     * Stops automatic showroom rotation without changing the current camera
     * angle. Manual 360-degree finger rotation remains available.
     */
    fun stopShowroomRotation() {
        showroomRotationEnabled = false
        showroomCycleStartNanos = 0L

        // The current visual angle becomes the retained manual angle.
        showroomCenterAngleY =
            cameraController.orbitAngleY

        Log.i(
            TAG,
            "MUNJA SHOWROOM ROTATION STOP: " +
                "angle=${cameraController.orbitAngleY}rad"
        )
    }

    /**
     * Marks the beginning/continuation of a manual camera gesture.
     *
     * The automatic animation pauses immediately and later resumes around the
     * user's newly chosen viewing angle.
     */
    private fun noteManualCameraInteraction() {
        showroomLastInteractionNanos = System.nanoTime()
        showroomCycleStartNanos = 0L
        showroomCenterAngleY = cameraController.orbitAngleY
    }

    /**
     * Advances the native showroom camera for the current Choreographer frame.
     *
     * Returns true when the camera was changed and the frame should be rendered.
     */
    private fun updateShowroomRotation(frameTimeNanos: Long): Boolean {
        if (!showroomRotationEnabled || !isModelLoaded()) {
            return false
        }

        // Never fight the existing touch/gesture camera controller.
        if (cameraController.isInteracting) {
            showroomLastInteractionNanos = frameTimeNanos
            showroomCycleStartNanos = 0L
            showroomCenterAngleY = cameraController.orbitAngleY
            return false
        }

        val sinceInteraction =
            frameTimeNanos - showroomLastInteractionNanos

        if (sinceInteraction < showroomResumeDelayNanos) {
            return false
        }

        if (showroomCycleStartNanos == 0L) {
            // Start from sin(0)=0 so resuming never causes a visual jump.
            showroomCenterAngleY = cameraController.orbitAngleY
            showroomCycleStartNanos = frameTimeNanos
        }

        val elapsed =
            frameTimeNanos - showroomCycleStartNanos

        val normalized =
            (elapsed % showroomCycleDurationNanos).toDouble() /
                showroomCycleDurationNanos.toDouble()

        val phase =
            normalized * PI * 2.0

        val orbitY =
            showroomCenterAngleY +
                sin(phase).toFloat() *
                showroomAmplitudeRadians

        cameraController.setHorizontalOrbitAngle(orbitY)

        camera?.let {
            cameraController.applyToCamera(it)
        }

        return true
    }

    fun onTap(x: Int, y: Int) {
        cameraController.markInteracting()
        val v = filamentView ?: return
        val flippedY = height - y

        v.pick(x, flippedY, mainHandler) { result ->
            val entity = result.renderable
            if (entity == 0) return@pick

            val asset = modelLoader.currentAsset ?: return@pick
            val isModelEntity = asset.entities?.contains(entity) ?: false
            if (!isModelEntity) return@pick

            val eng = engine ?: return@pick

            // Sequence validation — mirror iOS Interactive3dView.handleTap
            val nodeName = asset.getName(entity)
            if (nodeName != null) {
                val selectedNames = selection.selectedEntities
                    .mapNotNull { asset.getName(it) }
                    .toSet()
                if (!sequenceValidator.isTapAllowed(nodeName, selectedNames)) {
                    onSelectionRejected?.invoke(nodeName)
                    return@pick
                }
            }

            selection.handleTap(entity, asset, eng)
        }
    }

    fun onPan(deltaX: Float, deltaY: Float) {
        noteManualCameraInteraction()

        if (cameraController.onPan(deltaX, deltaY)) {
            camera?.let { cameraController.applyToCamera(it) }

            // The user's latest finger-selected angle becomes the new showroom
            // center when automatic motion resumes.
            showroomCenterAngleY = cameraController.orbitAngleY
            showroomLastInteractionNanos = System.nanoTime()
            showroomCycleStartNanos = 0L
        }
    }

    fun onScale(scale: Float) {
        noteManualCameraInteraction()

        if (cameraController.onScale(scale)) {
            // Re-lock render quality during zoom to prevent driver-side blur
            filamentView?.let { v ->
                v.dynamicResolutionOptions = v.dynamicResolutionOptions.apply {
                    enabled = false
                    quality = View.QualityLevel.HIGH
                }
                v.renderQuality = v.renderQuality.apply {
                    hdrColorBuffer = View.QualityLevel.HIGH
                }
            }
            camera?.let {
                cameraController.applyProjection(it, width, height)
                cameraController.applyToCamera(it)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    fun setCameraZoomLevel(zoom: Float) {
        cameraController.setZoom(zoom)
        camera?.let {
            cameraController.applyProjection(it, width, height)
            cameraController.applyToCamera(it)
        }
    }

    fun setCameraPose(
        horizontalDegrees: Float,
        verticalDegrees: Float,
        targetHeightFactor: Float,
        zoom: Float
    ) {
        cameraController.setCameraPose(
            horizontalDegrees = horizontalDegrees,
            verticalDegrees = verticalDegrees,
            targetHeightFactor = targetHeightFactor,
            zoom = zoom
        )

        camera?.let {
            cameraController.applyProjection(it, width, height)
            cameraController.applyToCamera(it)
        }
    }

    /**
     * Shows or hides every entity whose glTF node name is included in [group].
     *
     * Munja uses this for the four native frame meshes:
     *
     *   Frame 1
     *   FRAME 2
     *   FRAME 3
     *   frame 4
     *
     * The materials/textures stay untouched. Only scene membership changes,
     * which means the GLB keeps the exact PBR material exported by Blender.
     */
    fun setPartGroupVisibility(
        group: Map<String, Any>,
        isVisible: Boolean,
    ) {
        val asset = modelLoader.currentAsset
        if (asset == null) {
            Log.w(
                TAG,
                "MUNJA VISIBILITY FAILED: no model loaded",
            )
            return
        }

        val scn = scene
        if (scn == null) {
            Log.w(
                TAG,
                "MUNJA VISIBILITY FAILED: scene unavailable",
            )
            return
        }

        @Suppress("UNCHECKED_CAST")
        val names = (group["names"] as? List<*>)
            ?.filterIsInstance<String>()
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        if (names.isEmpty()) {
            Log.w(
                TAG,
                "MUNJA VISIBILITY FAILED: group contains no entity names | group=$group",
            )
            return
        }

        var matchedCount = 0

        asset.entities?.forEach { entity ->
            val entityName = asset.getName(entity) ?: return@forEach

            if (entityName !in names) {
                return@forEach
            }

            matchedCount++

            if (isVisible) {
                scn.addEntity(entity)
            } else {
                scn.removeEntity(entity)
            }

            selection.entityVisibilities[entity] = isVisible

            Log.i(
                TAG,
                "MUNJA ENTITY VISIBILITY: " +
                    "$entityName -> ${if (isVisible) "VISIBLE" else "HIDDEN"} | " +
                    "entity=$entity",
            )
        }

        if (matchedCount == 0) {
            Log.w(
                TAG,
                "MUNJA VISIBILITY NO MATCH: names=$names",
            )
            return
        }

        // A hidden entity must not remain logically selected.
        if (!isVisible) {
            val eng = engine

            if (eng != null) {
                names.forEach { targetName ->
                    asset.entities
                        ?.firstOrNull { asset.getName(it) == targetName }
                        ?.let { entity ->
                            if (selection.selectedEntities.contains(entity)) {
                                selection.resetColor(entity, eng)
                                selection.selectedEntities.remove(entity)
                            }
                        }
                }

                selection.onSelectionChanged?.invoke(
                    selection.selectedEntities.mapNotNull { entity ->
                        val entityName = asset.getName(entity)

                        if (
                            entityName != null &&
                            entityName != "Unnamed Entity"
                        ) {
                            mapOf(
                                "id" to entity.toLong(),
                                "name" to entityName,
                            )
                        } else {
                            null
                        }
                    },
                )
            }
        }

        // Wake the adaptive render loop after every visibility update.
        requestRender()
    }

    /**
     * Convenience method for Munja's native frame system.
     *
     * Exactly one entity in [entityNames] stays visible. Every other listed
     * entity is removed from the Filament scene. This preserves each frame's
     * original mesh, UVs, textures, normal map, metallic map and roughness map.
     *
     * This is deliberately implemented on top of the same scene-membership
     * mechanism as [setPartGroupVisibility], so the existing Flutter API remains
     * fully compatible.
     */
    fun setExclusiveEntityVisibility(
        entityNames: List<String>,
        activeEntityName: String,
    ): Boolean {
        val asset = modelLoader.currentAsset
        if (asset == null) {
            Log.w(
                TAG,
                "MUNJA EXCLUSIVE VISIBILITY FAILED: no model loaded",
            )
            return false
        }

        val scn = scene
        if (scn == null) {
            Log.w(
                TAG,
                "MUNJA EXCLUSIVE VISIBILITY FAILED: scene unavailable",
            )
            return false
        }

        if (
            entityNames.isEmpty() ||
            activeEntityName.isBlank() ||
            activeEntityName !in entityNames
        ) {
            Log.w(
                TAG,
                "MUNJA EXCLUSIVE VISIBILITY INVALID: " +
                    "active=$activeEntityName | names=$entityNames",
            )
            return false
        }

        var activeFound = false
        var changedCount = 0

        asset.entities?.forEach { entity ->
            val entityName = asset.getName(entity) ?: return@forEach

            if (entityName !in entityNames) {
                return@forEach
            }

            val shouldBeVisible = entityName == activeEntityName

            if (shouldBeVisible) {
                scn.addEntity(entity)
                activeFound = true
            } else {
                scn.removeEntity(entity)
            }

            selection.entityVisibilities[entity] = shouldBeVisible
            changedCount++

            Log.i(
                TAG,
                "MUNJA FRAME VISIBILITY: " +
                    "$entityName -> " +
                    "${if (shouldBeVisible) "VISIBLE" else "HIDDEN"}",
            )
        }

        if (!activeFound) {
            Log.w(
                TAG,
                "MUNJA EXCLUSIVE VISIBILITY ACTIVE ENTITY NOT FOUND: " +
                    activeEntityName,
            )
            return false
        }

        val eng = engine

        if (eng != null) {
            val hiddenSelectedEntities =
                selection.selectedEntities.filter { entity ->
                    val entityName = asset.getName(entity)
                    entityName in entityNames &&
                        entityName != activeEntityName
                }

            hiddenSelectedEntities.forEach { entity ->
                selection.resetColor(entity, eng)
                selection.selectedEntities.remove(entity)
            }

            if (hiddenSelectedEntities.isNotEmpty()) {
                selection.onSelectionChanged?.invoke(
                    selection.selectedEntities.mapNotNull { entity ->
                        val entityName = asset.getName(entity)

                        if (
                            entityName != null &&
                            entityName != "Unnamed Entity"
                        ) {
                            mapOf(
                                "id" to entity.toLong(),
                                "name" to entityName,
                            )
                        } else {
                            null
                        }
                    },
                )
            }
        }

        requestRender()

        Log.i(
            TAG,
            "MUNJA FRAME ACTIVE: " +
                "$activeEntityName | managed=$changedCount",
        )

        return true
    }

    fun unselectEntities(entityIds: List<Long>?) {
        val eng = engine ?: return
        selection.unselectEntities(entityIds, eng, modelLoader.currentAsset)
        requestRender()
    }

    fun clearCacheAndRestoreSelections() {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        selection.clearCacheAndRestore(asset, eng)
        requestRender()
    }

    fun refreshCacheHighlights() {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        selection.refreshAllHighlights(asset, eng, selection.clearSelectionsOnHighlight)
        selection.notifySelectionChanged(asset)
        selection.notifyCacheChanged()
        requestRender()
    }

    fun removeFromCache(names: List<String>) {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        names.forEach { name ->
            selection.cacheManager?.removeFromCache(name)
            asset.entities?.find { asset.getName(it) == name }?.let { entity ->
                selection.resetColor(entity, eng)
                selection.selectedEntities.remove(entity)
            }
        }
        selection.onSelectionChanged?.invoke(
            selection.selectedEntities.mapNotNull { e ->
                val n = asset.getName(e)
                if (n != null) mapOf("id" to e.toLong(), "name" to n) else null
            }
        )
        selection.notifyCacheChanged()
        requestRender()
    }

    fun setSelectionListener(listener: (List<Map<String, Any>>) -> Unit) {
        selection.onSelectionChanged = listener
    }

    fun setCacheSelectionListener(listener: (List<Map<String, Any>>) -> Unit) {
        selection.onCacheSelectionChanged = listener
    }

    fun setSelectionRejectedListener(listener: (String) -> Unit) {
        onSelectionRejected = listener
    }

    // -------------------------------------------------------------------------
    // Cleanup
    // -------------------------------------------------------------------------

    @Synchronized
    fun cleanup() {
        if (destroyed || cleaningUp) {
            Log.i(
                TAG,
                "MUNJA RENDERER CLEANUP IGNORED: already disposing/destroyed"
            )
            return
        }

        cleaningUp = true

        Log.i(
            TAG,
            "MUNJA RENDERER CLEANUP START: " +
                "engine=${engine != null} | swapChain=${swapChain != null} | " +
                "model=${modelLoader.currentAsset != null}"
        )

        // Stop every source of future renderer work before touching Filament.
        stopRenderLoop()
        choreographer.removeFrameCallback(frameCallback)
        mainHandler.removeCallbacksAndMessages(null)

        showroomRotationEnabled = false
        showroomCycleStartNanos = 0L
        showroomLastInteractionNanos = 0L

        cameraController.cancelCallbacks()
        ioScope.cancel()

        val eng = engine
        if (eng == null) {
            cleaningUp = false
            destroyed = true
            Log.i(TAG, "MUNJA RENDERER CLEANUP COMPLETE: engine already null")
            return
        }

        try {
            // The surface/swapchain is detached first. This prevents the render
            // loop or Android Surface lifecycle from presenting through a chain
            // while GLTF/scene objects are being destroyed.
            destroySwapChain()

            selection.cleanup(eng)
            directMaterialBackups.clear()
            sequenceValidator.reset()

            val scn = scene
            val loader = assetLoader

            if (scn != null && loader != null) {
                modelLoader.cleanupCurrentModel(scn, loader)
            }

            if (scn != null) {
                environment.cleanup(eng, scn)
            }

            // Destroy gltfio infrastructure only after the current asset is gone.
            try {
                resourceLoader?.destroy()
            } catch (t: Throwable) {
                Log.e(TAG, "MUNJA RESOURCE LOADER DESTROY ERROR: ${t.message}", t)
            }
            resourceLoader = null

            try {
                assetLoader?.destroy()
            } catch (t: Throwable) {
                Log.e(TAG, "MUNJA ASSET LOADER DESTROY ERROR: ${t.message}", t)
            }
            assetLoader = null

            try {
                materialProvider?.destroyMaterials()
                materialProvider?.destroy()
            } catch (t: Throwable) {
                Log.e(TAG, "MUNJA MATERIAL PROVIDER DESTROY ERROR: ${t.message}", t)
            }
            materialProvider = null

            // Camera component/entity must not outlive the engine.
            if (cameraEntity != 0) {
                try {
                    eng.destroyCameraComponent(cameraEntity)
                } catch (t: Throwable) {
                    Log.e(TAG, "MUNJA CAMERA DESTROY ERROR: ${t.message}", t)
                }

                try {
                    EntityManager.get().destroy(cameraEntity)
                } catch (t: Throwable) {
                    Log.e(TAG, "MUNJA CAMERA ENTITY DESTROY ERROR: ${t.message}", t)
                }

                cameraEntity = 0
                camera = null
            }

            filamentView?.let {
                try {
                    eng.destroyView(it)
                } catch (t: Throwable) {
                    Log.e(TAG, "MUNJA VIEW DESTROY ERROR: ${t.message}", t)
                }
            }
            filamentView = null

            scene?.let {
                try {
                    eng.destroyScene(it)
                } catch (t: Throwable) {
                    Log.e(TAG, "MUNJA SCENE DESTROY ERROR: ${t.message}", t)
                }
            }
            scene = null

            renderer?.let {
                try {
                    eng.destroyRenderer(it)
                } catch (t: Throwable) {
                    Log.e(TAG, "MUNJA FILAMENT RENDERER DESTROY ERROR: ${t.message}", t)
                }
            }
            renderer = null

            // Null the shared engine reference BEFORE final native destruction so
            // any stale callback immediately sees renderer-unavailable.
            engine = null

            try {
                eng.destroy()
            } catch (t: Throwable) {
                Log.e(TAG, "MUNJA ENGINE DESTROY ERROR: ${t.message}", t)
            }
        } finally {
            swapChain = null
            camera = null
            materialProvider = null
            assetLoader = null
            resourceLoader = null

            cleaningUp = false
            destroyed = true

            Log.i(TAG, "MUNJA RENDERER CLEANUP COMPLETE")
        }
    }

    // -------------------------------------------------------------------------
    // Frame Callback
    // -------------------------------------------------------------------------

    private inner class FrameCallback : Choreographer.FrameCallback {
        private val startTime = System.nanoTime()
        private var frameCount = 0

        override fun doFrame(frameTimeNanos: Long) {
            if (!isRendering || destroyed || cleaningUp) return
            choreographer.postFrameCallback(this)

            if (destroyed || cleaningUp) return

            // Native showroom orbit is advanced inside the renderer itself.
            // When active, it keeps rendering smoothly without pretending that
            // the user is touching the screen.
            val showroomFrameChanged =
                updateShowroomRotation(frameTimeNanos)

            // Adaptive frame pacing based on user interaction.
            // Do not enter idle throttling while showroom motion is actively
            // changing the camera.
            if (!cameraController.isInteracting && !showroomFrameChanged) {
                cameraController.idleFrameCount++
                if (cameraController.idleFrameCount > 90) return       // Fully idle — save battery
                if (cameraController.idleFrameCount > 30 && frameCount % 2 != 0) return // 30 fps
            } else if (showroomFrameChanged) {
                cameraController.idleFrameCount = 0
            }

            val rend = renderer ?: return
            val sc = swapChain ?: return
            val v = filamentView ?: return

            // Animate if the model has animations
            modelLoader.currentAsset?.instance?.animator?.apply {
                if (animationCount > 0) {
                    val elapsed = (frameTimeNanos - startTime) / 1_000_000_000.0
                    applyAnimation(0, elapsed.toFloat())
                    updateBoneMatrices()
                }
            }

            try {
                if (rend.beginFrame(sc, frameTimeNanos)) {
                    rend.render(v)
                    rend.endFrame()
                    frameCount++
                }
            } catch (e: Exception) {
                Log.e(TAG, "Render error: ${e.message}")
            }
        }
    }
}

// -------------------------------------------------------------------------
// Extension
// -------------------------------------------------------------------------

/**
 * Converts a nullable List<Double> to a FloatArray, or returns [default].
 */
private fun List<Double>?.toFloatArrayOrDefault(default: FloatArray): FloatArray {
    if (this == null || size != 4) return default
    return floatArrayOf(get(0).toFloat(), get(1).toFloat(), get(2).toFloat(), get(3).toFloat())
}