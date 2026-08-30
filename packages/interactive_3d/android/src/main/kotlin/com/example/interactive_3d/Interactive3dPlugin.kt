package com.example.interactive_3d

import android.content.Context
import android.util.Log
import com.google.android.filament.utils.Utils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap

/**
 * Flutter plugin entry point for interactive_3d.
 *
 * Receives method calls from Dart, creates and manages [Interactive3dTextureEntry]
 * instances per texture ID, and routes all operations to the correct entry.
 */
class Interactive3dPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

  private companion object {
    const val TAG = "Interactive3dPlugin"
    const val METHOD_CHANNEL = "interactive_3d_plugin"

    init {
      Utils.init()
    }
  }

  private lateinit var methodChannel: MethodChannel
  private lateinit var textureRegistry: TextureRegistry
  private lateinit var messenger: BinaryMessenger
  private lateinit var context: Context

  private val textureEntries = ConcurrentHashMap<Long, Interactive3dTextureEntry>()

  /**
   * Munja currently uses one visible native Digital Twin at a time.
   *
   * Keeping more than one Filament Engine alive during route transitions caused
   * native SIGSEGV crashes on Android/Adreno. The plugin therefore owns one
   * active texture at a time and disposes the previous entry synchronously
   * before creating the next renderer.
   */
  @Volatile
  private var activeTextureId: Long? = null

  @Volatile
  private var activeModelName: String? = null

  private val textureLifecycleLock = Any()

  private fun disposeEntrySafely(
    textureId: Long,
    entry: Interactive3dTextureEntry,
    reason: String
  ) {
    try {
      Log.i(
        TAG,
        "MUNJA TEXTURE DISPOSE START: textureId=$textureId | reason=$reason"
      )
      entry.dispose()
      Log.i(
        TAG,
        "MUNJA TEXTURE DISPOSE COMPLETE: textureId=$textureId | reason=$reason"
      )
    } catch (t: Throwable) {
      Log.e(
        TAG,
        "MUNJA TEXTURE DISPOSE ERROR: textureId=$textureId | reason=$reason | ${t.message}",
        t
      )
    }
  }

  private fun disposeAllTextureEntries(reason: String) {
    synchronized(textureLifecycleLock) {
      val snapshot = textureEntries.entries.toList()

      // Remove first. This prevents late MethodChannel calls from reaching an
      // entry while its native renderer is being destroyed.
      textureEntries.clear()
      activeTextureId = null
      activeModelName = null

      snapshot.forEach { (textureId, entry) ->
        disposeEntrySafely(textureId, entry, reason)
      }
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    messenger = binding.binaryMessenger
    textureRegistry = binding.textureRegistry

    methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    methodChannel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    disposeAllTextureEntries("engine_detached")
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "createTexture" -> handleCreateTexture(call, result)
      "disposeTexture" -> handleDisposeTexture(call, result)
      "loadModel" -> handleLoadModel(call, result)
      "isModelLoaded" -> handleIsModelLoaded(call, result)
      "loadEnvironment" -> handleLoadEnvironment(call, result)
      "setZoomLevel" -> handleSetZoomLevel(call, result)
      "setCameraPose" -> handleSetCameraPose(call, result)
      "startShowroomRotation" -> handleStartShowroomRotation(call, result)
      "stopShowroomRotation" -> handleStopShowroomRotation(call, result)
      "setPartGroupVisibility" -> handleSetPartGroupVisibility(call, result)
      "setExclusiveEntityVisibility" -> handleSetExclusiveEntityVisibility(call, result)
      "unselectEntities" -> handleUnselectEntities(call, result)
      "clearCache" -> handleClearCache(call, result)
      "refreshCacheHighlights" -> handleRefreshCacheHighlights(call, result)
      "removeFromCache" -> handleRemoveFromCache(call, result)
      "setEntityMaterials" -> handleSetEntityMaterials(call, result)
      "resetEntityMaterials" -> handleResetEntityMaterials(call, result)
      "setEntityBaseColor" -> handleSetEntityBaseColor(call, result)
      "setEntityMaterialInstance" -> handleSetEntityMaterialInstance(call, result)
      "resetEntityDirectMaterial" -> handleResetEntityDirectMaterial(call, result)
      "resetAllDirectMaterials" -> handleResetAllDirectMaterials(call, result)
      "onTouchEvent" -> handleTouchEvent(call, result)
      else -> result.notImplemented()
    }
  }

  // -------------------------------------------------------------------------
  // Texture lifecycle
  // -------------------------------------------------------------------------

  private fun handleCreateTexture(call: MethodCall, result: MethodChannel.Result) {
    val width = call.argument<Int>("width") ?: 800
    val height = call.argument<Int>("height") ?: 600

    synchronized(textureLifecycleLock) {
      try {
        // MUNJA PERSISTENT RENDERER:
        // Reuse the same SurfaceProducer / Interactive3dTextureEntry / Filament
        // Engine for every Flutter-side Digital Twin owner. Route changes may
        // replace the Texture widget, but they must not repeatedly destroy and
        // recreate Engine.create() on Android/Adreno.
        val existingId = activeTextureId
        val existingEntry =
          existingId?.let { textureEntries[it] }

        if (existingId != null && existingEntry != null) {
          Log.i(
            TAG,
            "MUNJA PERSISTENT RENDERER REUSE: " +
              "textureId=$existingId | requested=${width}x$height"
          )

          result.success(mapOf("textureId" to existingId))
          return
        }

        val entry = Interactive3dTextureEntry(
          context,
          textureRegistry,
          messenger,
          width,
          height
        )

        val textureId = entry.initialize()

        if (textureId == -1L) {
          disposeEntrySafely(
            -1L,
            entry,
            "texture_initialization_failed"
          )

          result.error(
            "TEXTURE_CREATION_FAILED",
            "Failed to create SurfaceProducer",
            null
          )
          return
        }

        textureEntries.clear()
        textureEntries[textureId] = entry
        activeTextureId = textureId
        activeModelName = null

        Log.i(
          TAG,
          "MUNJA PERSISTENT RENDERER CREATED: " +
            "textureId=$textureId | entries=${textureEntries.size}"
        )

        result.success(mapOf("textureId" to textureId))
      } catch (t: Throwable) {
        Log.e(TAG, "Error creating texture: ${t.message}", t)
        result.error(
          "TEXTURE_CREATION_FAILED",
          t.message,
          null
        )
      }
    }
  }

  private fun handleDisposeTexture(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error(
        "INVALID_ARGUMENT",
        "textureId required",
        null
      )

    // MUNJA PERSISTENT RENDERER:
    // Flutter widget disposal means "this Dart owner detached", not "destroy
    // Filament". The renderer is destroyed only when the Flutter engine itself
    // detaches (onDetachedFromEngine -> disposeAllTextureEntries).
    if (textureId == activeTextureId &&
        textureEntries.containsKey(textureId)) {
      Log.i(
        TAG,
        "MUNJA PERSISTENT RENDERER DETACH: " +
          "textureId=$textureId | native renderer retained"
      )
    } else {
      Log.i(
        TAG,
        "MUNJA PERSISTENT RENDERER DETACH IGNORED: " +
          "textureId=$textureId | active=$activeTextureId"
      )
    }

    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Model & Environment
  // -------------------------------------------------------------------------

  private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val modelBytes = call.argument<ByteArray>("modelBytes")
    val modelName = call.argument<String>("name")

    if (textureId == null || modelBytes == null || modelName == null) {
      Log.e(
        TAG,
        "MUNJA MODEL LOAD CHANNEL INVALID: " +
          "textureId=$textureId | name=$modelName | bytes=${modelBytes?.size}"
      )
      return result.error("INVALID_ARGUMENT", "textureId, modelBytes and name required", null)
    }

    Log.i(
      TAG,
      "MUNJA MODEL LOAD CHANNEL RECEIVED: " +
        "textureId=$textureId | name=$modelName | bytes=${modelBytes.size}"
    )

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    if (activeTextureId != textureId) {
      Log.w(
        TAG,
        "MUNJA STALE TEXTURE LOAD BLOCKED: textureId=$textureId | active=$activeTextureId"
      )
      return result.error(
        "STALE_TEXTURE",
        "Texture $textureId is no longer the active renderer",
        null
      )
    }

    // Do not parse the same 26 MB GLB again every time a new Flutter screen
    // attaches to the persistent native texture.
    if (activeModelName == modelName && entry.isModelLoaded()) {
      Log.i(
        TAG,
        "MUNJA PERSISTENT MODEL REUSE: textureId=$textureId | name=$modelName"
      )
      result.success(null)
      return
    }

    try {
      val backgroundColor = call.argument<List<Double>>("backgroundColor")
      if (backgroundColor != null && backgroundColor.size >= 3) {
        entry.setBackgroundColor(backgroundColor)
      }

      Log.i(
        TAG,
        "MUNJA MODEL LOAD ENTRY SEND: textureId=$textureId | name=$modelName"
      )

      entry.loadModel(
        buffer = ByteBuffer.wrap(modelBytes),
        fileName = modelName,
        resources = call.argument<Map<String, ByteArray>>("resources") ?: emptyMap(),
        preselectedEntities = call.argument("preselectedEntities"),
        selectionColor = call.argument("selectionColor"),
        patchColors = call.argument("patchColors"),
        enableCache = call.argument<Boolean>("enableCache") ?: false,
        cacheColor = call.argument("cacheColor"),
        clearSelectionsOnHighlight = call.argument<Boolean>("clearSelectionsOnHighlight") ?: false,
        selectionSequence = call.argument("selectionSequence"),
        initialMaterialOverrides = call.argument("initialMaterialOverrides")
      )

      activeModelName = modelName

      Log.i(
        TAG,
        "MUNJA MODEL LOAD ENTRY RETURNED: textureId=$textureId | name=$modelName"
      )

      result.success(null)
    } catch (e: Exception) {
      Log.e(TAG, "Error loading model: ${e.message}", e)
      result.error("MODEL_LOAD_FAILED", e.message, null)
    }
  }

  /**
   * MUNJA MODEL READINESS
   *
   * Returns whether the native Filament model for the given texture is fully
   * loaded and has a live current asset.
   *
   * Dart polls this method before sending visibility, frame-color or material
   * swap commands. This prevents "no model loaded" races during startup.
   */
  private fun handleIsModelLoaded(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error(
        "INVALID_ARGUMENT",
        "textureId required",
        null
      )

    val entry = textureEntries[textureId]

    if (entry == null) {
      Log.d(
        TAG,
        "MUNJA MODEL READY CHANNEL: textureId=$textureId | entry=false | ready=false"
      )
      result.success(false)
      return
    }

    val ready = entry.isModelLoaded()

    Log.d(
      TAG,
      "MUNJA MODEL READY CHANNEL: textureId=$textureId | entry=true | ready=$ready"
    )

    result.success(ready)
  }

  private fun handleLoadEnvironment(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    val iblBytes = call.argument<ByteArray>("iblBytes")
    val skyboxBytes = call.argument<ByteArray>("skyboxBytes")

    if (iblBytes != null && skyboxBytes != null) {
      try {
        entry.loadEnvironment(ByteBuffer.wrap(iblBytes), ByteBuffer.wrap(skyboxBytes))
      } catch (e: Exception) {
        Log.e(TAG, "Error loading environment: ${e.message}", e)
        return result.error("ENVIRONMENT_LOAD_FAILED", e.message, null)
      }
    }
    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Camera
  // -------------------------------------------------------------------------

  private fun handleSetZoomLevel(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val zoom = call.argument<Double>("zoom")?.toFloat()

    if (textureId == null || zoom == null)
      return result.error("INVALID_ARGUMENT", "textureId and zoom required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.setCameraZoomLevel(zoom)
    result.success(null)
  }

  private fun handleSetCameraPose(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId =
      call.argument<Number>("textureId")?.toLong()
    val horizontalDegrees =
      call.argument<Double>("horizontalDegrees")?.toFloat()
    val verticalDegrees =
      call.argument<Double>("verticalDegrees")?.toFloat()
    val targetHeightFactor =
      call.argument<Double>("targetHeightFactor")?.toFloat()
    val zoom =
      call.argument<Double>("zoom")?.toFloat()

    if (
      textureId == null ||
      horizontalDegrees == null ||
      verticalDegrees == null ||
      targetHeightFactor == null ||
      zoom == null
    ) {
      return result.error(
        "INVALID_ARGUMENT",
        "camera pose arguments required",
        null
      )
    }

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.setCameraPose(
      horizontalDegrees = horizontalDegrees,
      verticalDegrees = verticalDegrees,
      targetHeightFactor = targetHeightFactor,
      zoom = zoom
    )

    result.success(null)
  }

  /**
   * Starts native showroom camera motion on the requested Interactive3d texture.
   *
   * Expected payload:
   * {
   *   textureId: Long,
   *   amplitudeDegrees: Double,
   *   durationMs: Int,
   *   resumeDelayMs: Int
   * }
   */
  private fun handleStartShowroomRotation(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId =
      call.argument<Number>("textureId")?.toLong()

    val amplitudeDegrees =
      call.argument<Number>("amplitudeDegrees")?.toFloat() ?: 10.0f

    val durationMs =
      call.argument<Number>("durationMs")?.toLong() ?: 2600L

    val resumeDelayMs =
      call.argument<Number>("resumeDelayMs")?.toLong() ?: 2000L

    if (textureId == null) {
      return result.error(
        "INVALID_ARGUMENT",
        "textureId required",
        null
      )
    }

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.startShowroomRotation(
      amplitudeDegrees = amplitudeDegrees,
      durationMs = durationMs,
      resumeDelayMs = resumeDelayMs
    )

    Log.i(
      TAG,
      "MUNJA SHOWROOM ROTATION CHANNEL START: " +
        "textureId=$textureId | " +
        "amplitude=${amplitudeDegrees}deg | " +
        "duration=${durationMs}ms | " +
        "resumeDelay=${resumeDelayMs}ms"
    )

    result.success(null)
  }

  /**
   * Stops native showroom camera motion while preserving the current orbit.
   */
  private fun handleStopShowroomRotation(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId =
      call.argument<Number>("textureId")?.toLong()
        ?: return result.error(
          "INVALID_ARGUMENT",
          "textureId required",
          null
        )

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.stopShowroomRotation()

    Log.i(
      TAG,
      "MUNJA SHOWROOM ROTATION CHANNEL STOP: textureId=$textureId"
    )

    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Visibility
  // -------------------------------------------------------------------------

  private fun handleSetPartGroupVisibility(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val group = call.argument<Map<String, Any>>("group")
    val visibility = call.argument<Map<String, Boolean>>("visibility")

    if (textureId == null || group == null || visibility == null)
      return result.error("INVALID_ARGUMENT", "textureId, group, and visibility required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    val title = group["title"] as? String
    val isVisible = visibility[title]

    if (title != null && isVisible != null) {
      entry.setPartGroupVisibility(group, isVisible)
    }
    result.success(null)
  }


  /**
   * MUNJA EXCLUSIVE FRAME VISIBILITY
   *
   * Keeps exactly one entity from [entityNames] visible and hides the rest.
   *
   * Expected Dart payload:
   * {
   *   "textureId": <id>,
   *   "entityNames": ["Frame 1", "FRAME 2", "FRAME 3", "frame 4"],
   *   "activeEntityName": "FRAME 2"
   * }
   *
   * This does not change any material or texture. It only switches which
   * exported frame mesh is present in the Filament scene.
   */
  private fun handleSetExclusiveEntityVisibility(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val entityNames = call.argument<List<String>>("entityNames")
    val activeEntityName = call.argument<String>("activeEntityName")

    if (
      textureId == null ||
      entityNames == null ||
      entityNames.isEmpty() ||
      activeEntityName.isNullOrBlank()
    ) {
      return result.error(
        "INVALID_ARGUMENT",
        "textureId, non-empty entityNames and activeEntityName required",
        null
      )
    }

    if (activeEntityName !in entityNames) {
      return result.error(
        "INVALID_ARGUMENT",
        "activeEntityName must be included in entityNames",
        null
      )
    }

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.setExclusiveEntityVisibility(
      entityNames = entityNames,
      activeEntityName = activeEntityName
    )

    Log.i(
      TAG,
      "MUNJA FRAME VISIBILITY CHANNEL: " +
        "active=$activeEntityName | " +
        "managed=$entityNames | " +
        "textureId=$textureId"
    )

    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Selection & Cache
  // -------------------------------------------------------------------------

  private fun handleUnselectEntities(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.unselectEntities(call.argument("entityIds"))
    result.success(null)
  }

  private fun handleClearCache(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.clearCache()
    result.success(null)
  }

  private fun handleRefreshCacheHighlights(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.refreshCacheHighlights()
    result.success(null)
  }

  private fun handleRemoveFromCache(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val names = call.argument<List<String>>("names")

    if (textureId == null || names == null)
      return result.error("INVALID_ARGUMENT", "textureId and names required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.removeFromCache(names)
    result.success(null)
  }

  private fun handleSetEntityMaterials(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val overrides = call.argument<List<Map<String, Any>>>("overrides")

    if (textureId == null || overrides == null)
      return result.error("INVALID_ARGUMENT", "textureId and overrides required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.setEntityMaterials(overrides)
    result.success(null)
  }

  private fun handleResetEntityMaterials(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.resetEntityMaterials(call.argument("names"))
    result.success(null)
  }

  /**
   * MUNJA SAFE FRAME COLOR
   *
   * Applies RGBA base color to the material currently assigned to a named
   * entity. This avoids creating/destroying replacement MaterialInstances.
   *
   * Expected Dart payload:
   * {
   *   "textureId": <id>,
   *   "entityName": "Frame 1",
   *   "rgba": [1.0, 0.0, 0.0, 1.0]
   * }
   */
  private fun handleSetEntityBaseColor(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val entityName = call.argument<String>("entityName")
    val rgbaRaw = call.argument<List<*>>("rgba")

    if (
      textureId == null ||
      entityName.isNullOrBlank() ||
      rgbaRaw == null ||
      rgbaRaw.size < 4
    ) {
      return result.error(
        "INVALID_ARGUMENT",
        "textureId, entityName and rgba[4] required",
        null
      )
    }

    val rgba = rgbaRaw
      .take(4)
      .mapNotNull { value ->
        (value as? Number)?.toDouble()
      }

    if (rgba.size != 4) {
      return result.error(
        "INVALID_ARGUMENT",
        "rgba must contain exactly four numeric values",
        null
      )
    }

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.setEntityBaseColor(
      entityName = entityName,
      rgba = rgba
    )

    Log.i(
      TAG,
      "MUNJA FRAME COLOR CHANNEL: " +
        "$entityName | rgba=$rgba | textureId=$textureId"
    )

    result.success(null)
  }

  /**
   * MUNJA DIRECT MATERIAL SWAP
   *
   * Applies one existing MaterialInstance from the currently loaded GLB to a
   * named entity. The actual Filament work is performed by FilamentRenderer.
   *
   * Expected Dart payload:
   * {
   *   "textureId": <id>,
   *   "entityName": "Frame 1",
   *   "materialInstanceName": "Titanium_Frame_1"
   * }
   */
  private fun handleSetEntityMaterialInstance(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val entityName = call.argument<String>("entityName")
    val materialInstanceName = call.argument<String>("materialInstanceName")

    if (
      textureId == null ||
      entityName.isNullOrBlank() ||
      materialInstanceName.isNullOrBlank()
    ) {
      return result.error(
        "INVALID_ARGUMENT",
        "textureId, entityName and materialInstanceName required",
        null
      )
    }

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.setEntityMaterialInstance(
      entityName = entityName,
      materialInstanceName = materialInstanceName
    )

    Log.i(
      TAG,
      "MUNJA DIRECT MATERIAL CHANNEL: " +
        "$entityName -> $materialInstanceName | textureId=$textureId"
    )

    result.success(null)
  }

  /**
   * Restores the original GLB material(s) for one entity that was previously
   * modified through setEntityMaterialInstance().
   */
  private fun handleResetEntityDirectMaterial(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val entityName = call.argument<String>("entityName")

    if (textureId == null || entityName.isNullOrBlank()) {
      return result.error(
        "INVALID_ARGUMENT",
        "textureId and entityName required",
        null
      )
    }

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.resetEntityDirectMaterial(entityName)

    Log.i(
      TAG,
      "MUNJA DIRECT MATERIAL RESET CHANNEL: " +
        "$entityName | textureId=$textureId"
    )

    result.success(null)
  }

  /**
   * Restores every entity modified through direct material swapping for the
   * specified texture.
   */
  private fun handleResetAllDirectMaterials(
    call: MethodCall,
    result: MethodChannel.Result
  ) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error(
        "INVALID_ARGUMENT",
        "textureId required",
        null
      )

    val entry = textureEntries[textureId]
      ?: return result.error(
        "TEXTURE_NOT_FOUND",
        "Texture $textureId not found",
        null
      )

    entry.resetAllDirectMaterials()

    Log.i(
      TAG,
      "MUNJA DIRECT MATERIAL RESET ALL CHANNEL: textureId=$textureId"
    )

    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Touch events
  // -------------------------------------------------------------------------

  private fun handleTouchEvent(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val action = call.argument<String>("action")

    if (textureId == null || action == null)
      return result.error("INVALID_ARGUMENT", "textureId and action required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    when (action) {
      "tap" -> {
        val x = call.argument<Double>("x")?.toFloat()
        val y = call.argument<Double>("y")?.toFloat()
        if (x != null && y != null) entry.onTap(x, y)
      }
      "pan" -> {
        val dx = call.argument<Double>("deltaX")?.toFloat()
        val dy = call.argument<Double>("deltaY")?.toFloat()
        if (dx != null && dy != null) entry.onPan(dx, dy)
      }
      "scale" -> {
        val s = call.argument<Double>("scale")?.toFloat()
        if (s != null) entry.onScale(s)
      }
    }
    result.success(null)
  }
}