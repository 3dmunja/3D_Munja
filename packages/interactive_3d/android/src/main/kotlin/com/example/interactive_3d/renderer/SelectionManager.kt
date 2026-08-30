package com.example.interactive_3d.renderer

import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.gltfio.FilamentAsset
import com.example.interactive_3d.Interactive3dCacheManager

/**
 * Handles entity selection, highlighting, and cache coloring.
 *
 * Selection works by replacing Filament material instances with solid-color
 * copies that override the Ubershader texture indices. Original materials
 * are stored in [originalMaterials] so they can be restored on deselection.
 *
 * All material updates execute synchronously on the calling thread (which
 * must be the main thread per Filament's requirement).
 */
internal class SelectionManager {

    private companion object {
        const val TAG = "SelectionManager"
    }

    // Currently selected entity IDs
    val selectedEntities = mutableSetOf<Int>()

    // Configurable colors
    var selectionColor = floatArrayOf(0f, 1f, 0f, 1f)
    var patchColors: List<Map<String, Any>>? = null

    // Set by the renderer after IBL loads — controls emissive fallback in resetColor
    var iblLoaded = false

    // Original material backup for selected/cached entities
    private val originalMaterials = mutableMapOf<Int, MutableMap<Int, MaterialInstance>>()
    private val entitiesWithSelectionColor = mutableSetOf<Int>()
    private val entitiesWithCacheColor = mutableSetOf<Int>()
    private val createdInstances = mutableListOf<MaterialInstance>()

    // Cache
    var enableCache = false
    var cacheManager: Interactive3dCacheManager? = null
    var cacheColor = floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f)
    var clearSelectionsOnHighlight = false

    // PBR override state, independent of selection and cache.
    // overrideParams accumulates merged params per entity across calls.
    // overrideMaterials holds the live MaterialInstances applied to the renderable.
    // entitiesWithOverrideApplied tracks which entities currently render the override.
    private val overrideParams = mutableMapOf<Int, MutableMap<String, Any>>()
    private val overrideMaterials = mutableMapOf<Int, MutableMap<Int, MaterialInstance>>()
    private val entitiesWithOverrideApplied = mutableSetOf<Int>()

    // Part visibility tracking
    val entityVisibilities = mutableMapOf<Int, Boolean>()

    // Event listeners
    var onSelectionChanged: ((List<Map<String, Any>>) -> Unit)? = null
    var onCacheSelectionChanged: ((List<Map<String, Any>>) -> Unit)? = null

    /**
     * Processes a tap on [entity]. Toggles selection state and applies or
     * removes the highlight color.
     */
    fun handleTap(entity: Int, asset: FilamentAsset, engine: Engine) {
        val entityName = asset.getName(entity)

        if (selectedEntities.contains(entity)) {
            resetColor(entity, engine)
            selectedEntities.remove(entity)
        } else {
            // If tapping a cached entity, uncache it first
            if (enableCache && entityName != null && cacheManager?.isCached(entityName) == true) {
                cacheManager?.removeFromCache(entityName)
                resetColor(entity, engine)
                notifyCacheChanged()
            }

            val color = resolveColor(entityName)
            applySelectionColor(entity, color, engine)
            selectedEntities.add(entity)

            if (enableCache && entityName != null) {
                cacheManager?.addToCache(entityName)
                notifyCacheChanged()
            }
        }

        notifySelectionChanged(asset)
    }

    /**
     * Applies a solid selection color to all primitives of [entity].
     *
     * Backs up original materials on first call, then replaces them with
     * solid-color instances that disable texture sampling so baseColorFactor
     * is the sole color source.
     */
    fun applySelectionColor(entity: Int, color: FloatArray, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return

        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Backup originals on first highlight
        if (!originalMaterials.containsKey(entity)) {
            val backup = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try { backup[i] = rcm.getMaterialInstanceAt(ri, i) }
                catch (e: Exception) { Log.w(TAG, "Could not backup material: ${e.message}") }
            }
            originalMaterials[entity] = backup
        }

        // Create solid-color instances
        for (i in 0 until count) {
            try {
                val originalMat = originalMaterials[entity]?.get(i)
                    ?: rcm.getMaterialInstanceAt(ri, i)
                val selectionMat = originalMat.material.createInstance()

                // Disable texture sampling so baseColorFactor is the sole color source
                selectionMat.setParameter("baseColorIndex", -1)
                selectionMat.setParameter("metallicRoughnessIndex", -1)
                selectionMat.setParameter("normalIndex", -1)
                selectionMat.setParameter("emissiveIndex", -1)

                selectionMat.setParameter("baseColorFactor", color[0], color[1], color[2], color[3])
                selectionMat.setParameter("emissiveFactor", 0.0f, 0.0f, 0.0f)
                selectionMat.setParameter("metallicFactor", 0.0f)
                selectionMat.setParameter("roughnessFactor", 1.0f)

                rcm.setMaterialInstanceAt(ri, i, selectionMat)
                createdInstances.add(selectionMat)
            } catch (e: Exception) {
                Log.w(TAG, "Could not apply selection color: ${e.message}")
            }
        }
        entitiesWithSelectionColor.add(entity)
        // Selection takes over visually; override is no longer rendered.
        entitiesWithOverrideApplied.remove(entity)
    }

    /**
     * Applies cache highlight color by creating new MaterialInstances
     * (same approach as selection color). Backs up originals so they can
     * be restored by [resetColor].
     */
    fun applyCacheColor(entity: Int, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return

        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Backup originals on first highlight
        if (!originalMaterials.containsKey(entity)) {
            val backup = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try { backup[i] = rcm.getMaterialInstanceAt(ri, i) }
                catch (e: Exception) { Log.w(TAG, "Could not backup material: ${e.message}") }
            }
            originalMaterials[entity] = backup
        }

        // Create new cache-colored instances
        for (i in 0 until count) {
            try {
                val originalMat = originalMaterials[entity]?.get(i)
                    ?: rcm.getMaterialInstanceAt(ri, i)
                val cacheMat = originalMat.material.createInstance()

                // Disable texture sampling so cacheColor is the sole color source
                cacheMat.setParameter("baseColorIndex", -1)
                cacheMat.setParameter("metallicRoughnessIndex", -1)
                cacheMat.setParameter("normalIndex", -1)
                cacheMat.setParameter("emissiveIndex", -1)

                cacheMat.setParameter("baseColorFactor", cacheColor[0], cacheColor[1], cacheColor[2], cacheColor[3])
                cacheMat.setParameter("emissiveFactor", 0.0f, 0.0f, 0.0f)
                cacheMat.setParameter("metallicFactor", 0.1f)
                cacheMat.setParameter("roughnessFactor", 0.7f)

                rcm.setMaterialInstanceAt(ri, i, cacheMat)
                createdInstances.add(cacheMat)
            } catch (e: Exception) {
                Log.w(TAG, "Could not apply cache color: ${e.message}")
            }
        }
        entitiesWithCacheColor.add(entity)
    }

    /**
     * Merges [params] into the entity's override and applies the override
     * material if the entity is not currently selected. Override visually
     * wins over cache; cache remains in storage.
     */
    fun applyMaterialOverride(entity: Int, params: Map<String, Any>, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Snapshot GLB original on first modification of this entity.
        if (!originalMaterials.containsKey(entity)) {
            val backup = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try { backup[i] = rcm.getMaterialInstanceAt(ri, i) }
                catch (e: Exception) { Log.w(TAG, "Could not backup material: ${e.message}") }
            }
            originalMaterials[entity] = backup
        }

        // Merge new params into the accumulated override state.
        val merged = overrideParams.getOrPut(entity) { mutableMapOf() }
        for ((k, v) in params) merged[k] = v

        // Build override MaterialInstances on first use, reuse afterwards.
        val mats = overrideMaterials.getOrPut(entity) {
            val newMap = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try {
                    val orig = originalMaterials[entity]?.get(i) ?: continue
                    newMap[i] = orig.material.createInstance()
                } catch (e: Exception) {
                    Log.w(TAG, "Could not create override instance: ${e.message}")
                }
            }
            newMap
        }

        // Apply every accumulated param to each override instance.
        for ((_, mat) in mats) applyOverrideParamsToInstance(mat, merged)

        // Selection wins visually; only stash the deselect target.
        if (entity in entitiesWithSelectionColor) return

        for ((idx, mat) in mats) {
            try { rcm.setMaterialInstanceAt(ri, idx, mat) }
            catch (e: Exception) { Log.w(TAG, "Could not apply override: ${e.message}") }
        }
        entitiesWithOverrideApplied.add(entity)
        entitiesWithCacheColor.remove(entity)
    }

    /**
     * Removes the override on [entity] and restores the GLB original safely.
     *
     * Filament does not allow a MaterialInstance to be destroyed while it is
     * still assigned to a Renderable. Restore the original first, then destroy
     * the detached temporary override instances.
     */
    fun resetMaterialOverride(entity: Int, engine: Engine) {
        val rcm = engine.renderableManager

        if (entity in entitiesWithOverrideApplied && rcm.hasComponent(entity)) {
            val ri = rcm.getInstance(entity)

            originalMaterials[entity]?.forEach { (idx, originalMat) ->
                try {
                    rcm.setMaterialInstanceAt(ri, idx, originalMat)
                } catch (e: Exception) {
                    Log.w(
                        TAG,
                        "Could not restore original material before override destroy: ${e.message}",
                    )
                }
            }
        }

        entitiesWithOverrideApplied.remove(entity)
        overrideParams.remove(entity)

        val detachedOverrides = overrideMaterials.remove(entity)
        detachedOverrides?.values?.forEach { mat ->
            try {
                engine.destroyMaterialInstance(mat)
            } catch (e: Exception) {
                Log.w(
                    TAG,
                    "Failed to destroy detached override instance: ${e.message}",
                )
            }
        }

        if (
            entity !in entitiesWithSelectionColor &&
            entity !in entitiesWithCacheColor
        ) {
            originalMaterials.remove(entity)
        }
    }

    /** Removes every active override. */
    fun resetAllMaterialOverrides(engine: Engine) {
        for (entity in overrideParams.keys.toList()) {
            resetMaterialOverride(entity, engine)
        }
    }

    /**
     * Looks up entities by name and applies overrides. Used both on model load
     * (initialMaterialOverrides) and from the controller (setEntityMaterials).
     */
    fun applyOverridesByName(
        overrides: List<Map<String, Any>>,
        asset: FilamentAsset,
        engine: Engine,
    ) {
        if (overrides.isEmpty()) return
        for (entry in overrides) {
            val name = entry["name"] as? String ?: continue
            val params = entry.filterKeys { it != "name" }
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name) {
                    applyMaterialOverride(entity, params, engine)
                }
            }
        }
    }

    /** Resets overrides for entities matched by [names], or all when null. */
    fun resetOverridesByName(
        names: List<String>?,
        asset: FilamentAsset,
        engine: Engine,
    ) {
        if (names == null) {
            resetAllMaterialOverrides(engine)
            return
        }
        for (name in names) {
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name) {
                    resetMaterialOverride(entity, engine)
                }
            }
        }
    }

    /**
     * Applies a generic persistent PBR override.
     *
     * IMPORTANT FOR MUNJA:
     * Real bike skins such as Carbon Fibre / Forest / Titanium should NOT be
     * implemented here. Those skins already exist as real materials inside the
     * exported GLB and must be switched by the renderer / glTF material-variant
     * path.
     *
     * This function remains available for generic per-entity adjustments and
     * backwards compatibility only. It preserves all GLB texture samplers and
     * therefore will not destroy the real material artwork.
     */
    private fun applyOverrideParamsToInstance(
        mat: MaterialInstance,
        params: Map<String, Any>,
    ) {
        (params["color"] as? List<Double>)
            ?.takeIf { it.size == 4 }
            ?.let { c ->
                try {
                    mat.setParameter(
                        "baseColorFactor",
                        c[0].toFloat(),
                        c[1].toFloat(),
                        c[2].toFloat(),
                        c[3].toFloat(),
                    )
                } catch (e: Exception) {
                    Log.w(
                        TAG,
                        "Could not set baseColorFactor: ${e.message}",
                    )
                }
            }

        (params["metallic"] as? Double)?.let { metallic ->
            try {
                mat.setParameter(
                    "metallicFactor",
                    metallic.toFloat(),
                )
            } catch (e: Exception) {
                Log.w(
                    TAG,
                    "Could not set metallicFactor: ${e.message}",
                )
            }
        }

        (params["roughness"] as? Double)?.let { roughness ->
            try {
                mat.setParameter(
                    "roughnessFactor",
                    roughness.toFloat(),
                )
            } catch (e: Exception) {
                Log.w(
                    TAG,
                    "Could not set roughnessFactor: ${e.message}",
                )
            }
        }

        (params["emissive"] as? List<Double>)
            ?.takeIf { it.size == 3 }
            ?.let { e ->
                try {
                    mat.setParameter(
                        "emissiveFactor",
                        e[0].toFloat(),
                        e[1].toFloat(),
                        e[2].toFloat(),
                    )
                } catch (ex: Exception) {
                    Log.w(
                        TAG,
                        "Could not set emissiveFactor: ${ex.message}",
                    )
                }
            }
    }

    /**
     * Restores original materials on [entity], removing any selection or
     * cache highlight.
     */
    fun resetColor(entity: Int, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)

        if (entitiesWithSelectionColor.contains(entity) || entitiesWithCacheColor.contains(entity)) {
            // Restore to override material if one exists, otherwise GLB original.
            val restoreTo = overrideMaterials[entity] ?: originalMaterials[entity]
            if (restoreTo != null) {
                for ((idx, mat) in restoreTo) {
                    try { rcm.setMaterialInstanceAt(ri, idx, mat) }
                    catch (e: Exception) { Log.w(TAG, "Could not restore material: ${e.message}") }
                }
            }
            entitiesWithSelectionColor.remove(entity)
            entitiesWithCacheColor.remove(entity)

            if (overrideMaterials.containsKey(entity)) {
                entitiesWithOverrideApplied.add(entity)
            }
        } else {
            // No backup exists — reset to default PBR values.
            val count = rcm.getPrimitiveCount(ri)
            val emissiveValue = if (iblLoaded) 0.0f else 0.2f
            for (i in 0 until count) {
                try {
                    val mat = rcm.getMaterialInstanceAt(ri, i)
                    mat.setParameter("baseColorFactor", 1.0f, 1.0f, 1.0f, 1.0f)
                    mat.setParameter("emissiveFactor", emissiveValue, emissiveValue, emissiveValue)
                    mat.setParameter("metallicFactor", 0.1f)
                    mat.setParameter("roughnessFactor", 0.8f)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not reset material: ${e.message}")
                }
            }
        }

        // Preserve the GLB-original snapshot if an override is still registered.
        if (entity !in entitiesWithOverrideApplied) {
            originalMaterials.remove(entity)
        }
    }

    /**
     * Highlights all cached entities. Skips overridden entities so the
     * override remains visible.
     */
    fun highlightCachedEntities(asset: FilamentAsset, engine: Engine) {
        if (!enableCache || cacheManager == null) return
        cacheManager?.cachedEntities?.forEach { cachedName ->
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == cachedName &&
                    entity !in selectedEntities &&
                    entity !in entitiesWithOverrideApplied
                ) {
                    applyCacheColor(entity, engine)
                }
            }
        }
    }

    /**
     * Resets everything and re-applies in priority order:
     * selection > override > cache > GLB original.
     */
    fun refreshAllHighlights(asset: FilamentAsset, engine: Engine, clearSelections: Boolean) {
        // 1. Reset entities that had selection or cache visuals. resetColor
        //    internally restores to override material when one is registered.
        asset.entities?.forEach { entity ->
            if (entitiesWithSelectionColor.contains(entity) ||
                entitiesWithCacheColor.contains(entity)) {
                resetColor(entity, engine)
            }
        }

        // 2. Apply cache color, skipping any entity with an override.
        val cachedSet = mutableSetOf<String>()
        if (enableCache && cacheManager != null) {
            cacheManager?.cachedEntities?.forEach { cachedName ->
                cachedSet.add(cachedName)
                asset.entities?.forEach { entity ->
                    if (asset.getName(entity) == cachedName &&
                        entity !in entitiesWithOverrideApplied &&
                        !overrideParams.containsKey(entity)
                    ) {
                        applyCacheColor(entity, engine)
                    }
                }
            }
        }

        // 3. Selection on top regardless of cache or override.
        for (entity in selectedEntities.toSet()) {
            val name = asset.getName(entity)
            if (name != null && !cachedSet.contains(name)) {
                val color = resolveColor(name)
                applySelectionColor(entity, color, engine)
            }
        }

        if (clearSelections) {
            selectedEntities.clear()
        }
    }

    /**
     * Clears the persistent cache and restores materials for previously
     * cached entities. Active selections are re-applied with selection color.
     */
    fun clearCacheAndRestore(asset: FilamentAsset, engine: Engine) {
        if (!enableCache || cacheManager == null) return

        val entitiesToClear = cacheManager!!.cachedEntities.toList()
        cacheManager!!.clearCache()

        asset.entities?.forEach { entity ->
            val name = asset.getName(entity)
            if (name != null && entitiesToClear.contains(name)) {
                resetColor(entity, engine)
                // If entity is still actively selected, re-apply its selection color
                if (selectedEntities.contains(entity)) {
                    val color = resolveColor(name)
                    applySelectionColor(entity, color, engine)
                }
            }
        }
        notifyCacheChanged()
    }

    /**
     * Applies preselected entities. Call after model loading completes.
     */
    fun applyPreselections(names: List<String>?, asset: FilamentAsset, engine: Engine) {
        if (names == null) return
        names.forEach { name ->
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name && entity !in selectedEntities) {
                    val color = resolveColor(name)
                    applySelectionColor(entity, color, engine)
                    selectedEntities.add(entity)
                }
            }
        }
        notifySelectionChanged(asset)
    }

    /**
     * Unselects entities by ID, or all if [entityIds] is null.
     */
    fun unselectEntities(entityIds: List<Long>?, engine: Engine, asset: FilamentAsset?) {
        if (entityIds == null) {
            selectedEntities.forEach { resetColor(it, engine) }
            selectedEntities.clear()
        } else {
            entityIds.forEach { id ->
                val entity = id.toInt()
                if (selectedEntities.remove(entity)) {
                    resetColor(entity, engine)
                }
            }
        }
        asset?.let { notifySelectionChanged(it) }
    }

    /**
     * Resolves the highlight color for [entityName].
     * Checks [patchColors] first, then falls back to the global [selectionColor].
     */
    fun resolveColor(entityName: String?): FloatArray {
        if (entityName == null) return selectionColor
        patchColors?.forEach { patch ->
            if (patch["name"] == entityName) {
                val c = patch["color"] as? List<Double>
                if (c?.size == 4) {
                    return floatArrayOf(c[0].toFloat(), c[1].toFloat(), c[2].toFloat(), c[3].toFloat())
                }
            }
        }
        return selectionColor
    }

    // -- Events --

    fun notifySelectionChanged(asset: FilamentAsset) {
        val items = selectedEntities.mapNotNull { entity ->
            val name = asset.getName(entity)
            if (name != null && name != "Unnamed Entity") {
                mapOf("id" to entity.toLong(), "name" to name)
            } else null
        }
        onSelectionChanged?.invoke(items)
    }

    fun notifyCacheChanged() {
        val cached = cacheManager?.cachedEntities?.map { mapOf("name" to it) } ?: emptyList()
        onCacheSelectionChanged?.invoke(cached)
    }

    // -- Cleanup --

    /**
     * Destroys all created material instances and clears tracking state.
     */
    fun destroyCreatedInstances(engine: Engine) {
        createdInstances.forEach { mat ->
            try { engine.destroyMaterialInstance(mat) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy MaterialInstance: ${e.message}") }
        }
        createdInstances.clear()
    }

    /**
     * Resets all selection and override state. Call before loading a new model.
     */
    fun reset(engine: Engine) {
        selectedEntities.clear()
        entityVisibilities.clear()
        destroyCreatedInstances(engine)
        destroyOverrideInstances(engine)
        originalMaterials.clear()
        entitiesWithSelectionColor.clear()
        entitiesWithCacheColor.clear()
        entitiesWithOverrideApplied.clear()
        overrideParams.clear()
    }

    /**
     * Restores any active override before destroying temporary instances.
     *
     * Destroying a MaterialInstance that is still referenced by a Renderable
     * triggers a native Filament precondition abort.
     */
    private fun destroyOverrideInstances(engine: Engine) {
        val rcm = engine.renderableManager

        for (entity in entitiesWithOverrideApplied.toList()) {
            if (!rcm.hasComponent(entity)) continue

            val ri = rcm.getInstance(entity)
            originalMaterials[entity]?.forEach { (idx, originalMat) ->
                try {
                    rcm.setMaterialInstanceAt(ri, idx, originalMat)
                } catch (e: Exception) {
                    Log.w(
                        TAG,
                        "Could not restore original during override cleanup: ${e.message}",
                    )
                }
            }
        }

        entitiesWithOverrideApplied.clear()

        overrideMaterials.values.forEach { primitives ->
            primitives.values.forEach { mat ->
                try {
                    engine.destroyMaterialInstance(mat)
                } catch (e: Exception) {
                    Log.w(
                        TAG,
                        "Failed to destroy detached override instance: ${e.message}",
                    )
                }
            }
        }

        overrideMaterials.clear()
    }

    /**
     * Full cleanup — restores originals then destroys everything.
     */
    fun cleanup(engine: Engine) {
        val rcm = engine.renderableManager

        val entitiesToRestore =
            entitiesWithSelectionColor +
            entitiesWithCacheColor +
            entitiesWithOverrideApplied

        entitiesToRestore.forEach { entity ->
            if (rcm.hasComponent(entity)) {
                val ri = rcm.getInstance(entity)
                originalMaterials[entity]?.forEach { (idx, mat) ->
                    try {
                        rcm.setMaterialInstanceAt(ri, idx, mat)
                    } catch (e: Exception) {
                        Log.w(
                            TAG,
                            "Could not restore original during cleanup: ${e.message}",
                        )
                    }
                }
            }
        }

        entitiesWithOverrideApplied.clear()
        reset(engine)
    }
}