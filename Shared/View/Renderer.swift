
import Metal
import MetalKit
import simd

struct RendererInitError: Error {
    var description: String
}

struct InstanceConstants {
    var modelViewProjectionMatrix: float4x4
    var normalMatrix: float4x4
    var color: float4
}

let MaxInFlightFrameCount = 3

let ConstantBufferLength = 65536 // Adjust this if you need to draw more objects
let ConstantAlignment = 256 // Adjust this if the size of the instance constants struct changes

class Renderer {
    let view: MTKView
    let device: MTLDevice!
    var commandQueue: MTLCommandQueue!

    let renderPipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let frameSemaphore = DispatchSemaphore(value: MaxInFlightFrameCount)

    var constantBuffers = [MTLBuffer]()
    var frameIndex = 0

    var vertexDescriptor: MDLVertexDescriptor!

    var cameraAngle: Float = 0

    static func makeVertexDescriptor() -> MDLVertexDescriptor {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.vertexAttributes[0].name = MDLVertexAttributePosition
        vertexDescriptor.vertexAttributes[0].format = .float3
        vertexDescriptor.vertexAttributes[0].offset = 0
        vertexDescriptor.vertexAttributes[0].bufferIndex = 0
        vertexDescriptor.vertexAttributes[1].name = MDLVertexAttributeNormal
        vertexDescriptor.vertexAttributes[1].format = .float3
        vertexDescriptor.vertexAttributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.vertexAttributes[1].bufferIndex = 0
        vertexDescriptor.bufferLayouts[0].stride = MemoryLayout<Float>.size * 6
        return vertexDescriptor
    }

    init(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("failed to create MTLDevice")
        }

        self.device = device
        self.view = view

        view.device = device
        view.sampleCount = 4
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float

        commandQueue = device.makeCommandQueue()


        vertexDescriptor = Renderer.makeVertexDescriptor()

        depthStencilState = Renderer.makeDepthStencilState(device: device)

        for _ in 0 ..< MaxInFlightFrameCount {
            constantBuffers.append(device.makeBuffer(length: ConstantBufferLength, options: [.storageModeShared])!)
        }

        renderPipelineState = Renderer.makeRenderPipelineState(device: device, view: view, vertexDescriptor: vertexDescriptor)
    }

    class func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .less
        depthStateDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStateDescriptor)!
    }

    /// Make the RenderPipelineState based on DefaultLibrary, shader programs, RenderPipelineDescriptor and MetalVertexDescriptorFromModelIO
    ///
    /// - Parameters:
    ///   - view: the MTKView
    ///   - vertexDescriptor:
    /// - Returns: MTLRenderPipelineState
    class func makeRenderPipelineState(device: MTLDevice, view: MTKView, vertexDescriptor: MDLVertexDescriptor) -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else { fatalError("Failed to create default Metal library") }

        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")

        let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        pipelineDescriptor.sampleCount = view.sampleCount
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat

        do {
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create render pipeline state object: \(error)")
        }
    }

    func draw(_ scene: Scene, from pointOfView: Node?, in renderCommandEncoder: MTLRenderCommandEncoder) {
        guard let cameraNode = pointOfView, let camera = cameraNode.camera else { return }

        frameIndex = (frameIndex + 1) % MaxInFlightFrameCount

        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        renderCommandEncoder.setDepthStencilState(depthStencilState)

        let viewMatrix = cameraNode.worldTransform.inverse

        let viewport = view.bounds
        let width = Float(viewport.size.width)
        let height = Float(viewport.size.height)
        let aspectRatio = width / height

        let projectionMatrix = camera.projectionMatrix(aspectRatio: aspectRatio)

        let worldMatrix = matrix_identity_float4x4

        let constantBuffer = constantBuffers[frameIndex]
        renderCommandEncoder.setVertexBuffer(constantBuffer, offset: 0, index: 1)

        var constantOffset = 0
        draw(scene.rootNode,
             worldTransform: worldMatrix,
             viewMatrix: viewMatrix,
             projectionMatrix: projectionMatrix,
             constantOffset: &constantOffset,
             in: renderCommandEncoder)
    }

    func draw(_ node: Node, worldTransform: float4x4, viewMatrix: float4x4, projectionMatrix: float4x4,
              constantOffset: inout Int, in renderCommandEncoder: MTLRenderCommandEncoder) {
        let worldMatrix = worldTransform * node.transform

        var constants = InstanceConstants(modelViewProjectionMatrix: projectionMatrix * viewMatrix * worldMatrix,
                                          normalMatrix: viewMatrix * worldMatrix,
                                          color: node.material.color)

        let constantBuffer = constantBuffers[frameIndex]
        memcpy(constantBuffer.contents() + constantOffset, &constants, MemoryLayout<InstanceConstants>.size)

        renderCommandEncoder.setVertexBufferOffset(constantOffset, index: 1)

        if let mesh = node.mesh {
            for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                renderCommandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
            }

            for submesh in mesh.submeshes {
                let fillMode: MTLTriangleFillMode = node.material.highlighted ? .lines : .fill
                renderCommandEncoder.setTriangleFillMode(fillMode)
                renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                           indexCount: submesh.indexCount,
                                                           indexType: submesh.indexType,
                                                           indexBuffer: submesh.indexBuffer.buffer,
                                                           indexBufferOffset: submesh.indexBuffer.offset)
            }
        }

        constantOffset += ConstantAlignment

        for child in node.children {
            draw(child,
                 worldTransform: worldTransform,
                 viewMatrix: viewMatrix,
                 projectionMatrix: projectionMatrix,
                 constantOffset: &constantOffset,
                 in: renderCommandEncoder)
        }
    }
}
