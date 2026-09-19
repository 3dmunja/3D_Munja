import Flutter
import UIKit
import SceneKit

/// The main platform view for the interactive_3d plugin on iOS.
///
/// Owns the SCNView and coordinates sub-managers for scene loading
/// ([SceneManager]), entity selection ([SelectionHandler]), and
/// sequence validation ([SequenceValidator]). Method calls from Dart
/// are dispatched to the appropriate manager.
class Interactive3DPlatformView: NSObject, FlutterPlatformView, FlutterStreamHandler {

    private let scnView: SCNView
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    // Sub-managers
    private let sceneManager: SceneManager
    private let selection: SelectionHandler
    private let sequenceValidator: SequenceValidator

    // State
    private var pendingPreselectedEntities: [String]?
    private var pendingInitialOverrides: [[String: Any]]?
    private var isDisposed = false

    // MUNJA iOS native showroom rotation
    private var showroomDisplayLink: CADisplayLink?
    private var showroomStartTime: CFTimeInterval?
    private var showroomLastTimestamp: CFTimeInterval?
    private var showroomAmplitudeRadians: Float = Float(10.0 * .pi / 180.0)
    private var showroomCycleDuration: CFTimeInterval = 2.6
    private var showroomResumeDelay: CFTimeInterval = 2.0
    private var showroomPausedUntil: CFTimeInterval = 0

    // MUNJA iOS direct-material system
    //
    // materialCatalog stores copies of every named material found in the GLB.
    // directMaterialBackups stores each entity's original geometry materials
    // before a direct skin swap is applied.
    private var materialCatalog: [String: SCNMaterial] = [:]
    private var directMaterialBackups: [SCNNode: [SCNMaterial]] = [:]

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
        scnView = SCNView(frame: frame.isEmpty ? UIScreen.main.bounds : frame)
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = true
        scnView.showsStatistics = false
        scnView.backgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0)
        scnView.cameraControlConfiguration.allowsTranslation = false

        // MUNJA iOS:
        // Keep SceneKit rendering while the native showroom CADisplayLink
        // updates the camera. Without this, the showroom can remain visually
        // frozen until the first user interaction wakes the SCNView.
        scnView.rendersContinuously = true
        scnView.isPlaying = true

        methodChannel = FlutterMethodChannel(
            name: "interactive_3d_\(viewId)",
            binaryMessenger: messenger
        )
        eventChannel = FlutterEventChannel(
            name: "interactive_3d_events_\(viewId)",
            binaryMessenger: messenger
        )

        sceneManager = SceneManager(scnView: scnView)
        selection = SelectionHandler()
        sequenceValidator = SequenceValidator()

        super.init()

        // Use [weak self] to break retain cycle with method channel
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
        // Wrap in WeakStreamHandler to break retain cycle with event channel
        eventChannel.setStreamHandler(WeakStreamHandler(delegate: self))

        // MUNJA iOS gesture fix
        scnView.isUserInteractionEnabled = true
        scnView.allowsCameraControl = true
        scnView.cameraControlConfiguration.allowsTranslation = false

        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTap(_:))
        )

        // Do not block SceneKit camera gestures.
        tapGesture.cancelsTouchesInView = false
        scnView.addGestureRecognizer(tapGesture)

        // Allow SceneKit camera recognizers and selection tap to coexist.
        scnView.gestureRecognizers?.forEach { recognizer in
            recognizer.cancelsTouchesInView = false
        }

        // MUNJA Customize iOS rotation fix:
        // Add an explicit one-finger pan recognizer that drives SceneKit's
        // default camera controller. This keeps Interactive3d's material/frame
        // system intact while restoring reliable 360-degree rotation on iPhone.
        // MUNJA:
        // Keep iOS interaction aligned with Android.
        // Manual one-finger 360-degree camera orbit is intentionally disabled.
        //
        // Do NOT add the custom handleCameraPan recognizer here.
        // Road Bike camera pose/rendering remains unchanged.

        scnView.scene = SCNScene()
    }

    func view() -> UIView {
        return scnView
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        sendSelectionUpdate()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - Method Dispatch

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            handleLoadModel(call, result: result)
        case "setZoomLevel":
            handleSetZoomLevel(call, result: result)
        case "setCameraPose":
            handleSetCameraPose(call, result: result)
        case "loadHdrBackground":
            handleLoadHdrBackground(call, result: result)
        case "unselectEntities":
            handleUnselectEntities(call, result: result)
        case "setPartGroupVisibility":
            handleSetPartGroupVisibility(call, result: result)
        case "setExclusiveEntityVisibility":
            handleSetExclusiveEntityVisibility(call, result: result)
        case "clearCache":
            handleClearCache(result: result)
        case "refreshCacheHighlights":
            handleRefreshCacheHighlights(result: result)
        case "removeFromCache":
            handleRemoveFromCache(call, result: result)
        case "setEntityMaterials":
            handleSetEntityMaterials(call, result: result)
        case "resetEntityMaterials":
            handleResetEntityMaterials(call, result: result)
        case "setEntityBaseColor":
            handleSetEntityBaseColor(call, result: result)
        case "setEntityMaterialInstance":
            handleSetEntityMaterialInstance(call, result: result)
        case "resetEntityDirectMaterial":
            handleResetEntityDirectMaterial(call, result: result)
        case "resetAllDirectMaterials":
            handleResetAllDirectMaterials(result: result)
        case "startShowroomRotation":
            handleStartShowroomRotation(call, result: result)
        case "stopShowroomRotation":
            handleStopShowroomRotation(result: result)
        case "dispose":
            DispatchQueue.main.async { [weak self] in
                self?.dispose()
                result(nil)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Method Handlers

    private func handleLoadModel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelBytes = (args["modelBytes"] as? FlutterStandardTypedData)?.data else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "modelBytes required", details: nil))
            return
        }

        // Configure selection
        selection.selectionColor = args["selectionColor"] as? [Double]
        selection.patchColors = args["patchColors"] as? [[String: Any]]
        selection.clearSelectionsOnHighlight = (args["clearSelectionsOnHighlight"] as? Bool) ?? false
        pendingPreselectedEntities = args["preselectedEntities"] as? [String]
        pendingInitialOverrides = args["initialMaterialOverrides"] as? [[String: Any]]

        // Configure sequence
        if let seqArray = args["selectionSequence"] as? [[String: Any]] {
            sequenceValidator.configure(from: seqArray)
        }

        // Configure cache
        selection.enableCache = (args["enableCache"] as? Bool) ?? false
        if let cacheColorArray = args["cacheColor"] as? [Double], cacheColorArray.count == 4 {
            selection.cacheColor = UIColor(
                red: CGFloat(cacheColorArray[0]),
                green: CGFloat(cacheColorArray[1]),
                blue: CGFloat(cacheColorArray[2]),
                alpha: CGFloat(cacheColorArray[3])
            )
        }
        let modelCacheKey = (args["name"] as? String) ?? UUID().uuidString
        if selection.enableCache {
            selection.cacheManager = Interactive3DCacheManager(
                modelKey: modelCacheKey, cacheColor: selection.cacheColor
            )
            selection.cacheManager?.onCacheChanged = { [weak self] _ in
                self?.sendCacheSelectionUpdate()
            }
        } else {
            selection.cacheManager = nil
        }

        // Configure background
        if let bgColor = args["backgroundColor"] as? [Double], bgColor.count >= 3 {
            let alpha = bgColor.count >= 4 ? CGFloat(bgColor[3]) : 1.0
            sceneManager.useSolidBackground = true
            scnView.backgroundColor = UIColor(
                red: CGFloat(bgColor[0]),
                green: CGFloat(bgColor[1]),
                blue: CGFloat(bgColor[2]),
                alpha: alpha
            )
        } else {
            sceneManager.useSolidBackground = false
        }

        // Reset previous selection state
        selection.reset()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.sceneManager.loadModel(modelBytes: modelBytes)

                // MUNJA DEBUG: inspect actual SceneKit visibility/material state.
                var munjaGeometrySummary = "unavailable"
                var munjaMaterialSummary = "unavailable"
                var munjaTransformSummary = "unavailable"
                var munjaMeshSummary = "unavailable"

                if let scene = self.scnView.scene {
                    var geometryCount = 0
                    var hiddenCount = 0
                    var transparentCount = 0
                    var ancestorHiddenCount = 0
                    var ancestorOpacityZeroCount = 0
                    var zeroScaleAncestorCount = 0
                    var nonDefaultCategoryCount = 0
                    var colorWriteNoneCount = 0
                    var depthWriteOffCount = 0
                    var depthReadOffCount = 0
                    var nonZeroRenderingOrderCount = 0
                    var materialCount = 0
                    var doubleSidedCount = 0
                    var constantCount = 0
                    var physicallyBasedCount = 0
                    var diffuseMissingCount = 0

                    var totalVertices = 0
                    var totalElements = 0
                    var totalPrimitives = 0
                    var emptyVertexGeometryCount = 0
                    var emptyElementGeometryCount = 0
                    var positionSourceCount = 0
                    var normalSourceCount = 0
                    var texcoordSourceCount = 0
                    var primitiveTypeCounts: [String: Int] = [:]
                    var bytesPerIndexCounts: [Int: Int] = [:]
                    var vertexFormatCounts: [String: Int] = [:]

                    scene.rootNode.enumerateChildNodes { node, _ in
                        guard let geometry = node.geometry else { return }

                        geometryCount += 1

                        let positionSources = geometry.sources(for: .vertex)
                        let normalSources = geometry.sources(for: .normal)
                        let texcoordSources = geometry.sources(for: .texcoord)

                        let vertexCount = positionSources.reduce(0) {
                            $0 + $1.vectorCount
                        }

                        let primitiveCount = geometry.elements.reduce(0) {
                            $0 + $1.primitiveCount
                        }

                        totalVertices += vertexCount
                        totalElements += geometry.elements.count
                        totalPrimitives += primitiveCount

                        positionSourceCount += positionSources.count
                        normalSourceCount += normalSources.count
                        texcoordSourceCount += texcoordSources.count

                        for element in geometry.elements {
                            let primitiveType: String
                            switch element.primitiveType {
                            case .triangles:
                                primitiveType = "triangles"
                            case .triangleStrip:
                                primitiveType = "triangleStrip"
                            case .line:
                                primitiveType = "line"
                            case .point:
                                primitiveType = "point"
                            case .polygon:
                                primitiveType = "polygon"
                            @unknown default:
                                primitiveType = "unknown"
                            }

                            primitiveTypeCounts[primitiveType, default: 0] += 1
                            bytesPerIndexCounts[element.bytesPerIndex, default: 0] += 1
                        }

                        for source in positionSources {
                            let format =
                                "cpv\(source.componentsPerVector)" +
                                "-bpc\(source.bytesPerComponent)" +
                                "-stride\(source.dataStride)" +
                                "-offset\(source.dataOffset)"

                            vertexFormatCounts[format, default: 0] += 1
                        }

                        if vertexCount == 0 {
                            emptyVertexGeometryCount += 1
                        }

                        if geometry.elements.isEmpty || primitiveCount == 0 {
                            emptyElementGeometryCount += 1
                        }

                        let parentHidden = node.parent?.isHidden ?? false

                        var ancestor: SCNNode? = node
                        var ancestorHidden = false
                        var effectiveOpacity: CGFloat = 1.0
                        var hasZeroScaleAncestor = false
                        var ancestorChain: [String] = []

                        while let current = ancestor {
                            if current.isHidden {
                                ancestorHidden = true
                            }

                            effectiveOpacity *= current.opacity

                            if abs(current.scale.x) <= 0.000001 ||
                               abs(current.scale.y) <= 0.000001 ||
                               abs(current.scale.z) <= 0.000001 {
                                hasZeroScaleAncestor = true
                            }

                            ancestorChain.append(
                                "\(current.name ?? "<unnamed>")" +
                                "{hidden=\(current.isHidden)," +
                                "opacity=\(current.opacity)," +
                                "scale=(\(current.scale.x),\(current.scale.y),\(current.scale.z))," +
                                "category=\(current.categoryBitMask)}"
                            )

                            if current === scene.rootNode {
                                break
                            }

                            ancestor = current.parent
                        }

                        let effectiveHidden = ancestorHidden

                        if effectiveHidden {
                            hiddenCount += 1
                            ancestorHiddenCount += 1
                        }

                        if effectiveOpacity <= 0.001 {
                            ancestorOpacityZeroCount += 1
                        }

                        if hasZeroScaleAncestor {
                            zeroScaleAncestorCount += 1
                        }

                        if node.categoryBitMask != 1 {
                            nonDefaultCategoryCount += 1
                        }

                        if node.renderingOrder != 0 {
                            nonZeroRenderingOrderCount += 1
                        }

                        print(
                            "MUNJA iOS ANCESTOR STATE: " +
                            "node=\(node.name ?? "<unnamed>") " +
                            "effectiveHidden=\(effectiveHidden) " +
                            "effectiveOpacity=\(effectiveOpacity) " +
                            "chain=[\(ancestorChain.joined(separator: " <- "))]"
                        )

                        let materialInfo = geometry.materials.enumerated().map {
                            index, material in

                            let transparent =
                                material.transparency <= 0.001 ||
                                node.opacity <= 0.001

                            if transparent {
                                transparentCount += 1
                            }

                            materialCount += 1

                            if material.colorBufferWriteMask.isEmpty {
                                colorWriteNoneCount += 1
                            }

                            if !material.writesToDepthBuffer {
                                depthWriteOffCount += 1
                            }

                            if !material.readsFromDepthBuffer {
                                depthReadOffCount += 1
                            }

                            if material.isDoubleSided {
                                doubleSidedCount += 1
                            }

                            if material.lightingModel == .constant {
                                constantCount += 1
                            }

                            if material.lightingModel == .physicallyBased {
                                physicallyBasedCount += 1
                            }

                            if material.diffuse.contents == nil {
                                diffuseMissingCount += 1
                            }

                            return "m\(index){trans=\(material.transparency)," +
                                "double=\(material.isDoubleSided)," +
                                "lighting=\(material.lightingModel.rawValue)," +
                                "diffuse=\(material.diffuse.contents != nil)," +
                                "blend=\(material.blendMode.rawValue)," +
                                "cull=\(material.cullMode.rawValue)}"
                        }.joined(separator: ",")

                        print(
                            "MUNJA iOS GEOMETRY STATE: " +
                            "node=\(node.name ?? "<unnamed>") " +
                            "hidden=\(node.isHidden) " +
                            "parentHidden=\(parentHidden) " +
                            "opacity=\(node.opacity) " +
                            "materials=[\(materialInfo)]"
                        )
                    }

                    let primitiveTypes = primitiveTypeCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key):\($0.value)" }
                        .joined(separator: ",")

                    let indexFormats = bytesPerIndexCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)B:\($0.value)" }
                        .joined(separator: ",")

                    let vertexFormats = vertexFormatCounts
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key):\($0.value)" }
                        .joined(separator: ",")

                    munjaMeshSummary =
                        "vertices=\(totalVertices) " +
                        "elements=\(totalElements) " +
                        "primitives=\(totalPrimitives) " +
                        "emptyVertices=\(emptyVertexGeometryCount) " +
                        "emptyElements=\(emptyElementGeometryCount) " +
                        "positionSources=\(positionSourceCount) " +
                        "normalSources=\(normalSourceCount) " +
                        "texcoordSources=\(texcoordSourceCount) " +
                        "primitiveTypes=[\(primitiveTypes)] " +
                        "indexFormats=[\(indexFormats)] " +
                        "vertexFormats=[\(vertexFormats)]"

                    munjaGeometrySummary =
                        "geometry=\(geometryCount) " +
                        "hidden=\(hiddenCount) " +
                        "transparent=\(transparentCount) " +
                        "ancestorHidden=\(ancestorHiddenCount) " +
                        "ancestorOpacityZero=\(ancestorOpacityZeroCount) " +
                        "zeroScaleAncestor=\(zeroScaleAncestorCount)" +
                        "nonDefaultCategory=\(nonDefaultCategoryCount) " +
                        "colorWriteNone=\(colorWriteNoneCount) " +
                        "depthWriteOff=\(depthWriteOffCount) " +
                        "depthReadOff=\(depthReadOffCount) " +
                        "nonZeroRenderOrder=\(nonZeroRenderingOrderCount)"

                    munjaMaterialSummary =
                        "materials=\(materialCount) " +
                        "doubleSided=\(doubleSidedCount) " +
                        "constant=\(constantCount) " +
                        "physicallyBased=\(physicallyBasedCount) " +
                        "diffuseMissing=\(diffuseMissingCount)"

                    print(
                        "MUNJA iOS GEOMETRY SUMMARY: " +
                        munjaGeometrySummary
                    )

                    print(
                        "MUNJA iOS MATERIAL SUMMARY: " +
                        munjaMaterialSummary
                    )
                }

                // MUNJA DEBUG: inspect top-level model transforms.
                if let scene = self.scnView.scene {
                    var entries: [String] = []

                    for (index, node) in scene.rootNode.childNodes.enumerated() {
                        let name = node.name ?? "<unnamed>"

                        entries.append(
                            "#\(index) \(name) " +
                            "pos=(\(node.position.x),\(node.position.y),\(node.position.z)) " +
                            "scale=(\(node.scale.x),\(node.scale.y),\(node.scale.z)) " +
                            "rot=(\(node.eulerAngles.x),\(node.eulerAngles.y),\(node.eulerAngles.z))"
                        )
                    }

                    munjaTransformSummary = entries.joined(separator: " | ")
                    print(
                        "MUNJA iOS TRANSFORM SUMMARY: " +
                        munjaTransformSummary
                    )
                }

                // MUNJA DEBUG: calculate actual transformed SceneKit world bounds.
                var munjaWorldBounds = "unavailable"
                if let scene = self.scnView.scene {
                    var minX = Float.greatestFiniteMagnitude
                    var minY = Float.greatestFiniteMagnitude
                    var minZ = Float.greatestFiniteMagnitude
                    var maxX = -Float.greatestFiniteMagnitude
                    var maxY = -Float.greatestFiniteMagnitude
                    var maxZ = -Float.greatestFiniteMagnitude
                    var geometryNodeCount = 0

                    scene.rootNode.enumerateChildNodes { node, _ in
                        guard node.geometry != nil else { return }

                        let (localMin, localMax) = node.boundingBox

                        let corners = [
                            SCNVector3(localMin.x, localMin.y, localMin.z),
                            SCNVector3(localMin.x, localMin.y, localMax.z),
                            SCNVector3(localMin.x, localMax.y, localMin.z),
                            SCNVector3(localMin.x, localMax.y, localMax.z),
                            SCNVector3(localMax.x, localMin.y, localMin.z),
                            SCNVector3(localMax.x, localMin.y, localMax.z),
                            SCNVector3(localMax.x, localMax.y, localMin.z),
                            SCNVector3(localMax.x, localMax.y, localMax.z),
                        ]

                        for corner in corners {
                            let world = node.convertPosition(
                                corner,
                                to: scene.rootNode
                            )

                            minX = min(minX, world.x)
                            minY = min(minY, world.y)
                            minZ = min(minZ, world.z)
                            maxX = max(maxX, world.x)
                            maxY = max(maxY, world.y)
                            maxZ = max(maxZ, world.z)
                        }

                        geometryNodeCount += 1
                    }

                    if geometryNodeCount > 0 {
                        let sizeX = maxX - minX
                        let sizeY = maxY - minY
                        let sizeZ = maxZ - minZ

                        let centerX = (minX + maxX) / 2
                        let centerY = (minY + maxY) / 2
                        let centerZ = (minZ + maxZ) / 2

                        munjaWorldBounds =
                            "nodes=\(geometryNodeCount) | " +
                            "min=(\(minX), \(minY), \(minZ)) | " +
                            "max=(\(maxX), \(maxY), \(maxZ)) | " +
                            "size=(\(sizeX), \(sizeY), \(sizeZ)) | " +
                            "center=(\(centerX), \(centerY), \(centerZ))"

                        print("MUNJA iOS WORLD BOUNDS: \(munjaWorldBounds)")
                    }
                }

                // MUNJA DEBUG: dump SceneKit entity/material mapping
                if let scene = self.scnView.scene {
                    print("========== MUNJA iOS SCENE MATERIAL DUMP ==========")

                    func dumpHierarchy(_ node: SCNNode, depth: Int) {
                        let indent = String(repeating: "  ", count: depth)
                        let name = node.name ?? "<unnamed>"
                        let materialCount = node.geometry?.materials.count ?? 0

                        print(
                            "MUNJA TREE: \(indent)\(name) | " +
                            "geometry=\(node.geometry != nil) | " +
                            "materials=\(materialCount) | " +
                            "children=\(node.childNodes.count)"
                        )

                        for child in node.childNodes {
                            dumpHierarchy(child, depth: depth + 1)
                        }
                    }

                    print("========== MUNJA iOS FULL SCENE TREE ==========")
                    dumpHierarchy(scene.rootNode, depth: 0)
                    print("========== END MUNJA iOS FULL SCENE TREE ==========")

                    scene.rootNode.enumerateChildNodes { node, _ in
                        guard let geometry = node.geometry else { return }

                        let nodeName = node.name ?? "<unnamed>"

                        let materialNames = geometry.materials.enumerated().map {
                            index, material in
                            "\(index):\(material.name ?? "<unnamed-material>")"
                        }

                        print(
                            "MUNJA iOS NODE: \(nodeName) | " +
                            "materials=\(materialNames)"
                        )
                    }

                    print("========== END MUNJA iOS SCENE MATERIAL DUMP ==========")
                }

                // Build Munja material catalog from every named SceneKit material
                // embedded in the loaded GLB.
                self.rebuildMaterialCatalog()

                // Apply initial overrides before cache/preselections so override
                // is the deselect target underneath any selection layered above.
                self.applyInitialOverrides()

                // Apply cache highlights (skips overridden entities internally).
                if let scene = self.scnView.scene {
                    self.selection.highlightCachedEntities(in: scene)
                }
                self.sendCacheSelectionUpdate()

                // Apply preselections last; selection wins visually.
                self.applyPreselectedEntities()

                // MUNJA DEBUG:
                // Return the complete imported SceneKit hierarchy to Dart so
                // it is visible in flutter run even when native print() is not.
                var munjaSceneTree: [String] = []

                if let scene = self.scnView.scene {
                    func collectTree(_ node: SCNNode, depth: Int) {
                        let indent = String(repeating: "  ", count: depth)
                        let name = node.name ?? "<unnamed>"
                        let materialCount = node.geometry?.materials.count ?? 0

                        munjaSceneTree.append(
                            "\(indent)\(name) | geometry=\(node.geometry != nil) | materials=\(materialCount) | children=\(node.childNodes.count)"
                        )

                        for child in node.childNodes {
                            collectTree(child, depth: depth + 1)
                        }
                    }

                    collectTree(scene.rootNode, depth: 0)
                }

                result([
                    "munjaSceneTree": munjaSceneTree,
                    "munjaWorldBounds": munjaWorldBounds,
                    "munjaGeometrySummary": munjaGeometrySummary,
                    "munjaMaterialSummary": munjaMaterialSummary,
                    "munjaTransformSummary": munjaTransformSummary,
                    "munjaMeshSummary": munjaMeshSummary,
                    "munjaCameraSummary": self.munjaCameraSummary()
                ])
            } catch {
                result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func munjaCameraSummary() -> String {
        let viewPOV = scnView.pointOfView
        let controllerPOV = scnView.defaultCameraController.pointOfView
        let pov = controllerPOV ?? viewPOV

        guard let pov = pov else {
            return "pov=nil"
        }

        let position = pov.position
        let worldPosition = pov.worldPosition
        let euler = pov.eulerAngles

        let camera = pov.camera
        let zNear = camera?.zNear ?? -1.0
        let zFar = camera?.zFar ?? -1.0
        let fieldOfView = camera?.fieldOfView ?? -1.0
        let orthographic = camera?.usesOrthographicProjection ?? false
        let orthographicScale = camera?.orthographicScale ?? -1.0

        return
            "viewPOV=\(viewPOV != nil) " +
            "controllerPOV=\(controllerPOV != nil) " +
            "samePOV=\(viewPOV === controllerPOV) " +
            "position=(\(position.x),\(position.y),\(position.z)) " +
            "worldPosition=(\(worldPosition.x),\(worldPosition.y),\(worldPosition.z)) " +
            "euler=(\(euler.x),\(euler.y),\(euler.z)) " +
            "zNear=\(zNear) " +
            "zFar=\(zFar) " +
            "fov=\(fieldOfView) " +
            "orthographic=\(orthographic) " +
            "orthographicScale=\(orthographicScale)"
    }

    private func handleSetZoomLevel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let zoom = args["zoom"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "zoom required", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.sceneManager.setCameraZoomLevel(Float(zoom))
            result(nil)
        }
    }


    private func handleSetCameraPose(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard
            let args = call.arguments as? [String: Any],
            let horizontalDegrees = (args["horizontalDegrees"] as? NSNumber)?.doubleValue,
            let verticalDegrees = (args["verticalDegrees"] as? NSNumber)?.doubleValue,
            let targetHeightFactor = (args["targetHeightFactor"] as? NSNumber)?.doubleValue,
            let zoom = (args["zoom"] as? NSNumber)?.doubleValue
        else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "camera pose arguments required",
                    details: nil
                )
            )
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let scene = self.scnView.scene else {
                result(nil)
                return
            }

            var minX = Float.greatestFiniteMagnitude
            var minY = Float.greatestFiniteMagnitude
            var minZ = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude
            var maxY = -Float.greatestFiniteMagnitude
            var maxZ = -Float.greatestFiniteMagnitude
            var geometryCount = 0

            scene.rootNode.enumerateChildNodes { node, _ in
                guard node.geometry != nil else { return }

                let (localMin, localMax) = node.boundingBox
                let corners = [
                    SCNVector3(localMin.x, localMin.y, localMin.z),
                    SCNVector3(localMin.x, localMin.y, localMax.z),
                    SCNVector3(localMin.x, localMax.y, localMin.z),
                    SCNVector3(localMin.x, localMax.y, localMax.z),
                    SCNVector3(localMax.x, localMin.y, localMin.z),
                    SCNVector3(localMax.x, localMin.y, localMax.z),
                    SCNVector3(localMax.x, localMax.y, localMin.z),
                    SCNVector3(localMax.x, localMax.y, localMax.z)
                ]

                for corner in corners {
                    let world = node.convertPosition(corner, to: scene.rootNode)
                    minX = min(minX, world.x)
                    minY = min(minY, world.y)
                    minZ = min(minZ, world.z)
                    maxX = max(maxX, world.x)
                    maxY = max(maxY, world.y)
                    maxZ = max(maxZ, world.z)
                }

                geometryCount += 1
            }

            guard geometryCount > 0 else {
                result(nil)
                return
            }

            let centerX = (minX + maxX) * 0.5
            let centerY = (minY + maxY) * 0.5
            let centerZ = (minZ + maxZ) * 0.5

            let halfX = (maxX - minX) * 0.5
            let halfY = (maxY - minY) * 0.5
            let halfZ = (maxZ - minZ) * 0.5

            let clampedHeight = max(-1.0, min(1.25, targetHeightFactor))

            let target = SCNVector3(
                centerX,
                centerY + halfY * Float(clampedHeight),
                centerZ
            )

            let horizontal = Float(horizontalDegrees * .pi / 180.0)
            let verticalDegreesClamped = max(-30.0, min(30.0, verticalDegrees))
            let vertical = Float(verticalDegreesClamped * .pi / 180.0)

            let modelRadius = max(
                0.001,
                sqrt(halfX * halfX + halfY * halfY + halfZ * halfZ)
            )

            let clampedZoom = Float(max(0.5, min(6.0, zoom)))
            let distance = modelRadius * clampedZoom

            let cosVertical = cos(vertical)

            let cameraPosition = SCNVector3(
                target.x + distance * sin(horizontal) * cosVertical,
                target.y + distance * sin(vertical),
                target.z + distance * cos(horizontal) * cosVertical
            )

            var pov = self.scnView.defaultCameraController.pointOfView
                ?? self.scnView.pointOfView

            if pov == nil {
                let cameraNode = SCNNode()
                cameraNode.camera = SCNCamera()
                scene.rootNode.addChildNode(cameraNode)
                self.scnView.pointOfView = cameraNode
                self.scnView.defaultCameraController.pointOfView = cameraNode
                pov = cameraNode
            }

            guard let cameraNode = pov else {
                result(nil)
                return
            }

            cameraNode.position = cameraPosition
            cameraNode.look(at: target)

            if cameraNode.camera == nil {
                cameraNode.camera = SCNCamera()
            }

            cameraNode.camera?.zNear = Double(max(0.001, modelRadius * 0.01))
            cameraNode.camera?.zFar = Double(max(100.0, modelRadius * 50.0))

            self.scnView.pointOfView = cameraNode
            self.scnView.defaultCameraController.pointOfView = cameraNode
            self.scnView.setNeedsDisplay()

            print(
                "MUNJA iOS SET CAMERA POSE: " +
                "horizontal=\(horizontalDegrees) " +
                "vertical=\(verticalDegreesClamped) " +
                "target=(\(target.x),\(target.y),\(target.z)) " +
                "distance=\(distance)"
            )

            result(nil)
        }
    }

    private func handleLoadHdrBackground(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let bgBytes = (args["backgroundBytes"] as? FlutterStandardTypedData)?.data else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "backgroundBytes required", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            do {
                try self?.sceneManager.loadHdrBackground(bgBytes)
                result(nil)
            } catch {
                result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func handleUnselectEntities(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let entityIds = call.arguments as? [Int]
        DispatchQueue.main.async { [weak self] in
            self?.selection.unselectEntities(entityIds: entityIds)
            self?.sendSelectionUpdate()
            result(nil)
        }
    }

    private func handleSetPartGroupVisibility(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let group = args["group"] as? [String: Any],
              let visibility = args["visibility"] as? [String: Bool],
              let title = group["title"] as? String,
              let isVisible = visibility[title] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid group or visibility", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.sceneManager.setPartGroupVisibility(group: group, isVisible: isVisible)
            result(nil)
        }
    }

    // MARK: - Munja Exclusive Entity Visibility

    private func handleSetExclusiveEntityVisibility(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let entityNames = args["entityNames"] as? [String],
              let activeEntityName = args["activeEntityName"] as? String,
              !entityNames.isEmpty,
              !activeEntityName.isEmpty else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "entityNames and activeEntityName are required",
                    details: nil
                )
            )
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let scene = self.scnView.scene else {
                result(
                    FlutterError(
                        code: "NO_SCENE",
                        message: "Scene is not available",
                        details: nil
                    )
                )
                return
            }

            var matchedNames = Set<String>()

            scene.rootNode.enumerateChildNodes { node, _ in
                guard let nodeName = node.name,
                      entityNames.contains(nodeName) else {
                    return
                }

                let shouldBeVisible = nodeName == activeEntityName
                node.isHidden = !shouldBeVisible
                matchedNames.insert(nodeName)

                print(
                    "MUNJA iOS ENTITY VISIBILITY: " +
                    "\(nodeName) -> \(shouldBeVisible ? "VISIBLE" : "HIDDEN")"
                )
            }

            print(
                "MUNJA iOS EXCLUSIVE VISIBILITY DONE: " +
                "active=\(activeEntityName) " +
                "matched=\(Array(matchedNames).sorted())"
            )

            self.scnView.setNeedsDisplay()
            result(nil)
        }
    }

    private func handleClearCache(result: @escaping FlutterResult) {
        guard let scene = scnView.scene else {
            result(FlutterError(code: "CACHE_DISABLED", message: "No scene", details: nil))
            return
        }
        selection.clearCache(in: scene)
        sendCacheSelectionUpdate()
        result(nil)
    }

    private func handleRefreshCacheHighlights(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let scene = self.scnView.scene else {
                result(nil)
                return
            }
            self.selection.refreshAllHighlights(in: scene)
            self.sendSelectionUpdate()
            self.sendCacheSelectionUpdate()
            result(nil)
        }
    }

    private func handleRemoveFromCache(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let names = call.arguments as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "names required", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let scene = self.scnView.scene else {
                result(nil)
                return
            }
            self.selection.removeFromCache(names: names, in: scene)
            self.sendSelectionUpdate()
            self.sendCacheSelectionUpdate()
            result(nil)
        }
    }

    private func handleStartShowroomRotation(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any] else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "Showroom arguments required",
                    details: nil
                )
            )
            return
        }

        let amplitude =
            (args["amplitudeDegrees"] as? NSNumber)?.doubleValue
            ?? 10.0

        let durationMs =
            (args["durationMs"] as? NSNumber)?.doubleValue
            ?? 2600.0

        let resumeDelayMs =
            (args["resumeDelayMs"] as? NSNumber)?.doubleValue
            ?? 2000.0

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDisposed else {
                result(nil)
                return
            }

            self.showroomResumeDelay =
                max(resumeDelayMs / 1000.0, 0.0)

            self.startShowroomRotationInternal(
                amplitudeDegrees: amplitude,
                durationMs: durationMs
            )

            print(
                "MUNJA iOS SHOWROOM CHANNEL START: " +
                "amplitude=\(amplitude)° | " +
                "duration=\(durationMs)ms | " +
                "resumeDelay=\(resumeDelayMs)ms"
            )

            let viewPOV = self.scnView.pointOfView
            let controllerPOV =
                self.scnView.defaultCameraController.pointOfView

            let liveCameraSummary = self.munjaCameraSummary()

            print(
                "MUNJA iOS LIVE CAMERA SUMMARY: " +
                liveCameraSummary
            )

            result([
                "viewPOV": viewPOV != nil,
                "controllerPOV": controllerPOV != nil,
                "samePOV": viewPOV === controllerPOV,
                "cameraSummary": liveCameraSummary
            ])
        }
    }

    private func handleStopShowroomRotation(
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.stopShowroomRotationInternal()

            print(
                "MUNJA iOS SHOWROOM CHANNEL STOP"
            )

            result(nil)
        }
    }

    // MARK: - MUNJA Native Showroom Rotation

    private func startShowroomRotationInternal(
        amplitudeDegrees: Double = 9.0,
        durationMs: Double = 3000.0
    ) {
        guard !isDisposed else { return }

        stopShowroomRotationInternal()

        // SCNCameraController.rotateBy(x:y:) expects DEGREES.
        // Keep the showroom amplitude in degrees.
        showroomAmplitudeRadians =
            Float(amplitudeDegrees)

        showroomCycleDuration =
            max(durationMs / 1000.0, 0.5)

        showroomStartTime = nil
        showroomLastTimestamp = nil
        showroomPausedUntil = 0

        // MUNJA iOS:
        // SceneKit may already have a valid SCNView pointOfView while the
        // default camera controller is still unbound before first touch.
        // Bind the existing camera only; do not create or reposition one.
        let cameraController = scnView.defaultCameraController
        if cameraController.pointOfView == nil,
           let existingPOV = scnView.pointOfView {
            cameraController.pointOfView = existingPOV
        }

        // MUNJA DEBUG: camera state before automatic showroom movement.
        let showroomViewPOV = scnView.pointOfView
        let showroomControllerPOV =
            scnView.defaultCameraController.pointOfView

        print(
            "MUNJA CAMERA STATE SHOWROOM START: " +
            "viewPOV=\(showroomViewPOV != nil) | " +
            "controllerPOV=\(showroomControllerPOV != nil) | " +
            "samePOV=\(showroomViewPOV === showroomControllerPOV)"
        )

        let link = CADisplayLink(
            target: self,
            selector: #selector(handleShowroomDisplayLink(_:))
        )

        link.add(to: .main, forMode: .common)
        showroomDisplayLink = link

        print(
            "MUNJA iOS SHOWROOM STARTED: " +
            "amplitude=\(amplitudeDegrees)° | " +
            "duration=\(durationMs)ms"
        )
    }

    private func stopShowroomRotationInternal() {
        showroomDisplayLink?.invalidate()
        showroomDisplayLink = nil
        showroomStartTime = nil
        showroomLastTimestamp = nil
    }

    @objc private func handleShowroomDisplayLink(
        _ link: CADisplayLink
    ) {
        guard !isDisposed else {
            stopShowroomRotationInternal()
            return
        }

        let now = link.timestamp

        if now < showroomPausedUntil {
            showroomLastTimestamp = now
            return
        }

        if showroomStartTime == nil {
            showroomStartTime = now
            showroomLastTimestamp = now
            return
        }

        guard let start = showroomStartTime else {
            return
        }

        let elapsed = now - start

        let phase =
            (elapsed / showroomCycleDuration) *
            (2.0 * Double.pi)

        let target =
            Double(showroomAmplitudeRadians) *
            sin(phase)

        let previousElapsed =
            max(
                0.0,
                (showroomLastTimestamp ?? now) - start
            )

        let previousPhase =
            (previousElapsed / showroomCycleDuration) *
            (2.0 * Double.pi)

        let previousTarget =
            Double(showroomAmplitudeRadians) *
            sin(previousPhase)

        // target and previousTarget are now degrees.
        // rotateBy(x:y:) also expects degrees, so use the exact delta.
        let delta =
            Float(target - previousTarget)

        scnView.defaultCameraController.rotateBy(
            x: delta,
            y: 0
        )

        showroomLastTimestamp = now
        scnView.setNeedsDisplay()
    }

    // MARK: - Camera Gesture Handling

    @objc private func handleCameraPan(_ gesture: UIPanGestureRecognizer) {
        guard !isDisposed else { return }

        let translation = gesture.translation(in: scnView)

        switch gesture.state {
        case .began:
            // MUNJA DEBUG: compare camera state when a real finger gesture begins.
            let panViewPOV = scnView.pointOfView
            let panControllerPOV =
                scnView.defaultCameraController.pointOfView

            print(
                "MUNJA CAMERA STATE PAN BEGAN: " +
                "viewPOV=\(panViewPOV != nil) | " +
                "controllerPOV=\(panControllerPOV != nil) | " +
                "samePOV=\(panViewPOV === panControllerPOV)"
            )

            // Pause showroom motion immediately when the user takes control.
            showroomPausedUntil =
                CACurrentMediaTime() + showroomResumeDelay

            showroomStartTime = nil
            showroomLastTimestamp = nil

        case .changed:
            // Keep showroom paused while the finger is moving.
            showroomPausedUntil =
                CACurrentMediaTime() + showroomResumeDelay

            // Direct one-finger orbit for iPhone Customize.
            // Horizontal drag = full orbit, vertical drag = gentler tilt.
            let horizontal = Float(-translation.x * 0.0055)
            let vertical = Float(-translation.y * 0.0030)

            scnView.defaultCameraController.rotateBy(
                x: horizontal,
                y: vertical
            )

            gesture.setTranslation(.zero, in: scnView)
            scnView.setNeedsDisplay()

        case .ended, .cancelled, .failed:
            gesture.setTranslation(.zero, in: scnView)

        default:
            break
        }
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: scnView)
        let hitResults = scnView.hitTest(location, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue
        ])
        guard let hit = hitResults.first else { return }

        // Walk up the hierarchy to find the named parent node
        var targetNode: SCNNode? = hit.node
        while targetNode != nil &&
              (targetNode!.name == nil ||
               targetNode!.name!.isEmpty ||
               targetNode!.name!.starts(with: "Mesh.") ||
               targetNode!.name!.hasSuffix(".001")) {
            targetNode = targetNode?.parent
        }

        guard let nameNode = targetNode, let nodeName = nameNode.name else { return }
        guard let geometryNode = selection.findGeometryNode(in: nameNode) else { return }

        // Sequence validation
        guard sequenceValidator.isTapAllowed(nodeName, selectedNodes: selection.selectedNodes) else {
            eventSink?(["event": "selectionRejected", "name": nodeName])
            return
        }

        // If cached, remove from cache and deselect
        if selection.enableCache,
           let cacheMgr = selection.cacheManager,
           cacheMgr.isCached(nodeName) {
            cacheMgr.removeFromCache(nodeName)
            selection.resetNodeColor(geometryNode)
            sendCacheSelectionUpdate()
            if selection.selectedNodes.contains(nameNode) {
                selection.selectedNodes.remove(nameNode)
                sendSelectionUpdate()
            }
            return
        }

        // Toggle selection
        if selection.selectedNodes.contains(nameNode) {
            selection.selectedNodes.remove(nameNode)
            selection.resetNodeColor(geometryNode)
        } else {
            selection.selectedNodes.insert(nameNode)
            selection.applyHighlight(to: geometryNode, forNodeName: nameNode.name)
            if selection.enableCache {
                selection.cacheManager?.addToCache(nodeName)
            }
        }

        sendSelectionUpdate()
    }

    // MARK: - Preselection

    private func applyPreselectedEntities() {
        guard let names = pendingPreselectedEntities, !names.isEmpty else { return }

        scnView.scene?.rootNode.enumerateChildNodes { (node, _) in
            if let nodeName = node.name, names.contains(nodeName),
               let geometryNode = self.selection.findGeometryNode(in: node) {
                self.selection.selectedNodes.insert(node)
                self.selection.applyHighlight(to: geometryNode, forNodeName: nodeName)
            }
        }
        sendSelectionUpdate()
        pendingPreselectedEntities = nil
    }

    // MARK: - Material Overrides

    private func applyInitialOverrides() {
        guard let entries = pendingInitialOverrides, !entries.isEmpty else { return }
        applyOverrideEntries(entries)
        pendingInitialOverrides = nil
    }

    private func applyOverrideEntries(_ entries: [[String: Any]]) {
        guard let scene = scnView.scene else { return }
        for entry in entries {
            guard let name = entry["name"] as? String else { continue }
            scene.rootNode.enumerateChildNodes { (node, _) in
                if node.name == name,
                   let geometryNode = self.selection.findGeometryNode(in: node) {
                    var params = entry
                    params.removeValue(forKey: "name")
                    self.selection.applyMaterialOverride(to: geometryNode, params: params)
                }
            }
        }
    }

    private func resetOverrideEntries(_ names: [String]?) {
        guard let scene = scnView.scene else { return }
        if let names = names {
            for name in names {
                scene.rootNode.enumerateChildNodes { (node, _) in
                    if node.name == name,
                       let geometryNode = self.selection.findGeometryNode(in: node) {
                        self.selection.resetMaterialOverride(geometryNode)
                    }
                }
            }
        } else {
            // Reset all: snapshot keys before mutating the dict.
            for node in Array(selection.overrideParams.keys) {
                selection.resetMaterialOverride(node)
            }
        }
    }


    // MARK: - Munja Direct Material System

    private func rebuildMaterialCatalog() {
        materialCatalog.removeAll()
        directMaterialBackups.removeAll()

        guard let scene = scnView.scene else { return }

        let keeperMaterialNames: [String: [String]] = [
            "MUNJA_MATERIAL_KEEPER_FRAME1": [
                "Standard_Frame 1",
                "Brushed_Metal_Frame 1",
                "Carbon_Fibre_Frame 1",
                "Forest_Green_Frame 1",
                "Gold_frame 1",
                "Ice_Silver_Frame 1",
                "Lava_Red_Frame 1",
                "Matt_Black_Frame 1",
                "Neon_Green_Frame 1",
                "Titanium_Frame_1"
            ],
            "MUNJA_MATERIAL_KEEPER_FRAME2": [
                "Standard_Texture_Frame 2",
                "Brushed_Metal_Frame 2",
                "Carbon_Fibre_Frame 2",
                "Forest_Green_Frame 2",
                "Gold_Frame 2",
                "Ice_Silver_Frame 2",
                "Lava_Red_Frame 2",
                "Matt_Black_Frame 2",
                "Neon_Green_frame 2",
                "Titanium_Frame_2"
            ],
            "MUNJA_MATERIAL_KEEPER_FRAME3": [
                "Standard_Texture_Frame 3",
                "Brushed_Metal_Frame 3",
                "Carbon_Fibre_Frame 3",
                "Forest_Green_Frame 3",
                "Gold_Frame 3",
                "Ice_Silver_Frame 3",
                "Lava_Red_Frame 3",
                "Matt_Black_Frame 3",
                "Neon_Green_Frame 3",
                "Titanium_Metal_Frame 3"
            ],
            "MUNJA_MATERIAL_KEEPER_FRAME4": [
                "Standard_Texture_Frame 4",
                "Brushed_Metal_Frame 4",
                "Carbon_Fibre_Frame 4",
                "Forest_Green_Frame 4",
                "Gold_Frame 4",
                "Ice_Silver_Frame 4",
                "Lava_Red_Frame 4",
                "Matt_Black_Frame 4",
                "Neon_Green_Frame 4",
                "Titanium_Frame 4"
            ]
        ]

        // GLTFSceneKit preserves the named keeper parent, but splits each
        // GLB primitive/material into an unnamed geometry descendant.
        // The descendant order matches the GLB primitive order.
        for (keeperName, expectedNames) in keeperMaterialNames {
            guard let keeperNode =
                scene.rootNode.childNode(withName: keeperName, recursively: true)
            else {
                print("MUNJA iOS KEEPER NOT FOUND: \(keeperName)")
                continue
            }

            var geometryNodes: [SCNNode] = []

            keeperNode.enumerateChildNodes { child, _ in
                if child.geometry != nil {
                    geometryNodes.append(child)
                }
            }

            print(
                "MUNJA iOS KEEPER FOUND: " +
                "\(keeperName) | geometryNodes=\(geometryNodes.count)"
            )

            for (index, expectedName) in expectedNames.enumerated() {
                guard index < geometryNodes.count,
                      let sourceMaterial =
                        geometryNodes[index].geometry?.materials.first,
                      let copy = sourceMaterial.copy() as? SCNMaterial
                else {
                    print(
                        "MUNJA iOS KEEPER MATERIAL MISSING: " +
                        "\(keeperName)[\(index)] -> \(expectedName)"
                    )
                    continue
                }

                copy.name = expectedName
                materialCatalog[expectedName] = copy

                print(
                    "MUNJA iOS MATERIAL REGISTERED: " +
                    "\(keeperName)[\(index)] -> \(expectedName)"
                )
            }
        }

        // Preserve any normally named materials too.
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }

            for material in geometry.materials {
                guard let name = material.name, !name.isEmpty else {
                    continue
                }

                if self.materialCatalog[name] == nil,
                   let copy = material.copy() as? SCNMaterial {
                    self.materialCatalog[name] = copy
                }
            }
        }

        print(
            "MUNJA iOS MATERIAL CATALOG READY: " +
            "\(materialCatalog.keys.sorted())"
        )
    }

    private func geometryNodes(forEntityName entityName: String) -> [SCNNode] {
        guard let scene = scnView.scene else { return [] }

        var matches: [SCNNode] = []

        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.name == entityName else { return }

            if node.geometry != nil {
                matches.append(node)
            }

            node.enumerateChildNodes { child, _ in
                if child.geometry != nil {
                    matches.append(child)
                }
            }
        }

        return matches
    }

    private func handleSetEntityMaterialInstance(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let entityName = args["entityName"] as? String,
              let materialInstanceName = args["materialInstanceName"] as? String,
              !entityName.isEmpty,
              !materialInstanceName.isEmpty else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "entityName and materialInstanceName required",
                    details: nil
                )
            )
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                result(nil)
                return
            }

            guard let sourceMaterial = self.materialCatalog[materialInstanceName]
            else {
                var sceneNodes: [String] = []

                if let scene = self.scnView.scene {
                    scene.rootNode.enumerateChildNodes { node, _ in
                        guard let geometry = node.geometry else { return }

                        sceneNodes.append(
                            "\(node.name ?? "<unnamed>")" +
                            " | materials=\(geometry.materials.count)"
                        )
                    }
                }

                result(
                    FlutterError(
                        code: "MATERIAL_NOT_FOUND",
                        message: "Material \(materialInstanceName) not found",
                        details: [
                            "catalog": Array(self.materialCatalog.keys).sorted(),
                            "sceneNodes": sceneNodes
                        ]
                    )
                )
                return
            }

            let nodes = self.geometryNodes(forEntityName: entityName)

            guard !nodes.isEmpty else {
                result(
                    FlutterError(
                        code: "ENTITY_NOT_FOUND",
                        message: "Entity \(entityName) not found",
                        details: nil
                    )
                )
                return
            }

            var applied = 0

            for node in nodes {
                guard let geometry = node.geometry else { continue }

                if self.directMaterialBackups[node] == nil {
                    self.directMaterialBackups[node] =
                        geometry.materials.compactMap {
                            $0.copy() as? SCNMaterial
                        }
                }

                let replacementCount = max(geometry.materials.count, 1)

                geometry.materials = (0..<replacementCount).compactMap { _ in
                    sourceMaterial.copy() as? SCNMaterial
                }

                applied += 1
            }

            print(
                "MUNJA iOS DIRECT MATERIAL ACTIVE: " +
                "\(entityName) -> \(materialInstanceName) | nodes=\(applied)"
            )

            self.scnView.setNeedsDisplay()
            result(nil)
        }
    }

    private func handleResetEntityDirectMaterial(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let entityName = args["entityName"] as? String,
              !entityName.isEmpty else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "entityName required",
                    details: nil
                )
            )
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                result(nil)
                return
            }

            let nodes = self.geometryNodes(forEntityName: entityName)
            var restored = 0

            for node in nodes {
                guard let geometry = node.geometry,
                      let backup = self.directMaterialBackups[node] else {
                    continue
                }

                geometry.materials = backup.compactMap {
                    $0.copy() as? SCNMaterial
                }

                self.directMaterialBackups.removeValue(forKey: node)
                restored += 1
            }

            print(
                "MUNJA iOS DIRECT MATERIAL RESET: " +
                "\(entityName) | nodes=\(restored)"
            )

            self.scnView.setNeedsDisplay()
            result(nil)
        }
    }

    private func handleResetAllDirectMaterials(
        result: @escaping FlutterResult
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                result(nil)
                return
            }

            for (node, backup) in self.directMaterialBackups {
                guard let geometry = node.geometry else { continue }

                geometry.materials = backup.compactMap {
                    $0.copy() as? SCNMaterial
                }
            }

            let count = self.directMaterialBackups.count
            self.directMaterialBackups.removeAll()

            print(
                "MUNJA iOS DIRECT MATERIAL RESET ALL: nodes=\(count)"
            )

            self.scnView.setNeedsDisplay()
            result(nil)
        }
    }

    private func handleSetEntityBaseColor(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let args = call.arguments as? [String: Any],
              let entityName = args["entityName"] as? String,
              let rgba = args["rgba"] as? [Double],
              rgba.count == 4 else {
            result(
                FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "entityName and rgba[4] required",
                    details: nil
                )
            )
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                result(nil)
                return
            }

            let color = UIColor(
                red: CGFloat(rgba[0]),
                green: CGFloat(rgba[1]),
                blue: CGFloat(rgba[2]),
                alpha: CGFloat(rgba[3])
            )

            let nodes = self.geometryNodes(forEntityName: entityName)

            for node in nodes {
                guard let geometry = node.geometry else { continue }

                for material in geometry.materials {
                    material.diffuse.contents = color
                    material.multiply.contents = UIColor.white
                }
            }

            print(
                "MUNJA iOS BASE COLOR ACTIVE: " +
                "\(entityName) -> \(rgba)"
            )

            self.scnView.setNeedsDisplay()
            result(nil)
        }
    }

    private func handleSetEntityMaterials(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let entries = call.arguments as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "overrides list required", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.applyOverrideEntries(entries)
            result(nil)
        }
    }

    private func handleResetEntityMaterials(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let names = call.arguments as? [String]
        DispatchQueue.main.async { [weak self] in
            self?.resetOverrideEntries(names)
            result(nil)
        }
    }

    // MARK: - Events

    private func sendSelectionUpdate() {
        guard let eventSink = eventSink else { return }
        let entities = selection.selectedNodes.map { node in
            ["id": node.hash, "name": node.name ?? "Unnamed"] as [String: Any]
        }
        eventSink(["event": "selectionChanged", "selectedEntities": entities])
    }

    private func sendCacheSelectionUpdate() {
        guard let eventSink = eventSink,
              selection.enableCache,
              let cacheMgr = selection.cacheManager else { return }
        let cached = cacheMgr.cachedEntities.map { ["name": $0] }
        eventSink(["event": "cacheSelectionChanged", "cachedEntities": cached])
    }

    // MARK: - Cleanup

    deinit {
        cleanup()
    }

    func dispose() {
        cleanup()
    }

    private func cleanup() {
        guard !isDisposed else { return }
        isDisposed = true

        // Stop Munja showroom animation before destroying the view.
        stopShowroomRotationInternal()

        // Break retain cycles
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
        eventSink = nil

        // Remove gesture recognizers
        scnView.gestureRecognizers?.forEach { scnView.removeGestureRecognizer($0) }

        // Stop rendering
        scnView.isPlaying = false
        scnView.stop(nil)

        // Clean up managers
        selection.cleanup()
        sequenceValidator.reset()
        sceneManager.cleanup()

        pendingPreselectedEntities = nil
        pendingInitialOverrides = nil
        materialCatalog.removeAll()
        directMaterialBackups.removeAll()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension Interactive3DPlatformView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Keep pinch/zoom and selection taps available while the one-finger
        // camera pan is active.
        return true
    }
}

