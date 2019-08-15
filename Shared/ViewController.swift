
import MetalKit

#if targetEnvironment(simulator)
    #warning("Cannot build a Metal target for simulator")
#endif

class ViewController: NUViewController {
    var mtkView: MTKView {
        return view as! MTKView
    }

    var renderer: Renderer!
    var scene = Scene()
    var pointOfView: Node?

    var lastPanLocation = CGPoint()

    override func viewDidLoad() {
        super.viewDidLoad()


        mtkView.delegate = self

        addGestureRecognizers()

        renderer = Renderer(view: mtkView)

        makeScene_xyz_spheres(vertexDescriptor: renderer.vertexDescriptor)
    }

    func makeScene_xyz_spheres(vertexDescriptor: MDLVertexDescriptor, gridSideCountX: Int = 2, gridSideCountY: Int = 4, gridSideCountZ: Int = 3) {
        let sphereRadius: Float = 1
        let sphereDistance: Float = 2 * sphereRadius + 1
        let spherePadding = sphereDistance - 2 * sphereRadius
        let meshAllocator = MTKMeshBufferAllocator(device: renderer.device)
        let mdlMesh = MDLMesh(sphereWithExtent: float3(sphereRadius, sphereRadius, sphereRadius),
                              segments: uint2(20, 20),
                              inwardNormals: false,
                              geometryType: .triangles,
                              allocator: meshAllocator)
        mdlMesh.vertexDescriptor = vertexDescriptor

        guard let sphereMesh = try? MTKMesh(mesh: mdlMesh, device: renderer.device) else {
            print("Could not create MetalKit mesh from ModelIO mesh"); return
        }

        func positionOnAxis(ijk: Int, gridSideCount: Int) -> Float {
            return (Float(ijk) - Float(gridSideCount - 1) / 2) * sphereDistance
        }

        for i in 0 ..< gridSideCountX {
            for j in 0 ..< gridSideCountY {
                for k in 0 ..< gridSideCountZ {
                    let node = Node()
                    node.mesh = sphereMesh
                    node.material.color = float4(hue: Float(drand48()), saturation: 1.0, brightness: 1.0)
                    let position3 = float3(
                        positionOnAxis(ijk: i, gridSideCount: gridSideCountX),
                        positionOnAxis(ijk: j, gridSideCount: gridSideCountY),
                        positionOnAxis(ijk: k, gridSideCount: gridSideCountZ)
                    )
                    node.transform = float4x4(translationBy: position3)
                    node.boundingSphere.radius = sphereRadius
                    node.name = "(\(i), \(j)), \(k))"
                    scene.rootNode.addChildNode(node)
                }
            }
        }

        let cameraNode = Node()
        cameraNode.transform = float4x4(translationBy: float3(0, 0, 15))
        cameraNode.camera = Camera()
        pointOfView = cameraNode
        scene.rootNode.addChildNode(cameraNode)
    }
}

// MARK: - gesture recognizers

extension ViewController: NUGestureRecognizerDelegate {
    fileprivate func addGestureRecognizers() {
        let tapClickRecognizer = NUTapClickGestureRecognizer(target: self, action: #selector(handleTapClick(recognizer:)))
        let panRecognizer = NUPanGestureRecognizer(target: self, action: #selector(handlePan(recognizer:)))

        tapClickRecognizer.delegate = self
        panRecognizer.delegate = self

        view.addGestureRecognizer(tapClickRecognizer)
        view.addGestureRecognizer(panRecognizer)
    }

    func gestureRecognizer(_: NUGestureRecognizer, shouldRecognizeSimultaneouslyWith _: NUGestureRecognizer) -> Bool {
        printClassAndFunc()
        return true
    }

    @objc func handleTapClick(recognizer: NUTapClickGestureRecognizer) {
        let location = recognizer.locationFromTop(in: view)
        printClassAndFunc(info: "\(location)")

        guard let cameraNode = pointOfView, let camera = cameraNode.camera else { return }

        let viewport = mtkView.bounds // Assume viewport matches window; if not, apply additional inverse viewport xform
        let width = Float(viewport.size.width)
        let height = Float(viewport.size.height)
        let aspectRatio = width / height

        let projectionMatrix = camera.projectionMatrix(aspectRatio: aspectRatio)
        let inverseProjectionMatrix = projectionMatrix.inverse

        let viewMatrix = cameraNode.worldTransform.inverse
        let inverseViewMatrix = viewMatrix.inverse

        let clipX = (2 * Float(location.x)) / width - 1
        let clipY = 1 - (2 * Float(location.y)) / height
        let clipCoords = float4(clipX, clipY, 0, 1) // Assume clip space is hemicube, -Z is into the screen

        var eyeRayDir = inverseProjectionMatrix * clipCoords
        eyeRayDir.z = -1
        eyeRayDir.w = 0

        var worldRayDir = (inverseViewMatrix * eyeRayDir).xyz
        worldRayDir = normalize(worldRayDir)

        let eyeRayOrigin = float4(x: 0, y: 0, z: 0, w: 1)
        let worldRayOrigin = (inverseViewMatrix * eyeRayOrigin).xyz

        let ray = Ray(origin: worldRayOrigin, direction: worldRayDir)
        if let hit = scene.hitTest(ray) {
            hit.node.material.highlighted = !hit.node.material.highlighted // In Swift 4.2, this could be written with toggle()
            print("Hit \(hit.node) at \(hit.intersectionPoint)")
        }
    }

    @objc func handlePan(recognizer: NUPanGestureRecognizer) {
        let location = recognizer.locationFromTop(in: view)
        printClassAndFunc(info: "\(location)  \(recognizer.state.rawValue)")
        let panSensitivity: Float = 5.0
        switch recognizer.state {
        case .began:
            lastPanLocation = location
        case .changed:
            _ = Float((lastPanLocation.x - location.x) / view.bounds.width) * panSensitivity
            _ = Float((lastPanLocation.y - location.y) / view.bounds.height) * panSensitivity
            // printClassAndFunc(info: "\(xDelta) \(yDelta) ")
            lastPanLocation = location
        case .ended:
            break
        default:
            break
        }

        // TODO: use pan to rotate sphere cluster
    }
}

// MARK: - MTKViewDelegate

extension ViewController: MTKViewDelegate {
    func draw(in view: MTKView) {
        renderer.frameSemaphore.wait()

        // 2 pull into renderer.draw

        renderer.cameraAngle += 0.01

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // 1 pull into renderer.draw
        pointOfView?.transform = float4x4(rotationAroundAxis: float3(x: 0, y: 1, z: 0), by: renderer.cameraAngle) *
            float4x4(translationBy: float3(0, 0, 15))

        renderer.draw(scene, from: pointOfView, in: renderCommandEncoder)

        renderCommandEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.addCompletedHandler { _ in
            self.renderer.frameSemaphore.signal()
        }

        commandBuffer.commit()
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}
}
