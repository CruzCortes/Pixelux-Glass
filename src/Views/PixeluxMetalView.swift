import MetalKit
import Metal
import ARKit
import CoreVideo

/**
 Metal-based rendering view for the liquid glass effect
 
 This MTKView subclass handles the GPU-accelerated rendering of the glass effect.
 It manages texture creation from ARKit frames, shader pipeline configuration,
 and real-time rendering with support for both YCbCr and BGRA pixel formats.
 */
class PixeluxMetalView: MTKView {
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var textureCache: CVMetalTextureCache!
    
    var glassFrame: CGRect = .zero
    var glassScreenPosition: CGRect = .zero
    var cornerRadius: CGFloat = 30
    var blurIntensity: CGFloat = 0.0
    var extendedFrameOffset: CGFloat = 0
    var isInteractive: Bool = false {
        didSet {
            if oldValue != isInteractive {
                updatePipeline()
            }
        }
    }
    var glassID: UUID = UUID()
    
    var currentARFrame: ARFrame? {
        didSet {
            if oldValue?.timestamp != currentARFrame?.timestamp {
                setNeedsDisplay()
            }
        }
    }
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    deinit {
        if isInteractive {
            PixeluxInteractionManager.shared.unregister(glassID)
        }
    }
    
    /**
     Configures the Metal view and creates necessary resources
     */
    private func setup() {
        guard let device = device else { return }
        
        commandQueue = device.makeCommandQueue()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isOpaque = false
        backgroundColor = .clear
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 60
        colorPixelFormat = .bgra8Unorm
        clipsToBounds = false
        
        updatePipeline()
    }
    
    /**
     Updates the render pipeline state based on current configuration
     */
    private func updatePipeline() {
        guard let device = device else { return }
        
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "liquidGlassVertex"),
              let fragmentFunction = library.makeFunction(name: isInteractive ? "liquidGlassFragmentInteractive" : "liquidGlassFragmentEnhanced") else {
            fatalError("Shaders not found")
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Pipeline failed: \(error)")
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        if isInteractive, let window = window {
            let screenFrame = convert(bounds, to: window)
            DispatchQueue.main.async {
                PixeluxInteractionManager.shared.register(
                    self.glassID,
                    frame: self.glassFrame,
                    screenPosition: screenFrame,
                    cornerRadius: self.cornerRadius,
                    metalView: self
                )
            }
        }
    }
    
    /**
     Main rendering method that processes AR frames through the glass effect
     */
    override func draw(_ rect: CGRect) {
        guard let arFrame = currentARFrame,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor else { return }
        
        let pixelBuffer = arFrame.capturedImage
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var yTexture: MTLTexture?
        var cbcrTexture: MTLTexture?
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            yTexture = createTextureFromPlane(pixelBuffer: pixelBuffer, planeIndex: 0, pixelFormat: .r8Unorm)
            cbcrTexture = createTextureFromPlane(pixelBuffer: pixelBuffer, planeIndex: 1, pixelFormat: .rg8Unorm)
            guard yTexture != nil && cbcrTexture != nil else { return }
        } else {
            guard let texture = createTexture(from: pixelBuffer) else { return }
            yTexture = texture
        }
        
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        if let y = yTexture {
            renderEncoder.setFragmentTexture(y, index: 0)
        }
        if let cbcr = cbcrTexture {
            renderEncoder.setFragmentTexture(cbcr, index: 1)
        }
        
        var drawableSize = SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height))
        let viewportSize = CGSize(width: CGFloat(drawableSize.x), height: CGFloat(drawableSize.y))
        let displayTransform = arFrame.displayTransform(for: .portrait, viewportSize: viewportSize)
        
        var transformMatrix = simd_float3x3(
            SIMD3<Float>(Float(displayTransform.a), Float(displayTransform.b), 0),
            SIMD3<Float>(Float(displayTransform.c), Float(displayTransform.d), 0),
            SIMD3<Float>(Float(displayTransform.tx), Float(displayTransform.ty), 1)
        )
        
        let screenSize = UIScreen.main.bounds.size
        var screenDimensions = SIMD2<Float>(Float(screenSize.width * contentScaleFactor),
                                           Float(screenSize.height * contentScaleFactor))
        
        let cameraImageResolution = arFrame.camera.imageResolution
        var cameraDimensions = SIMD2<Float>(Float(cameraImageResolution.width),
                                           Float(cameraImageResolution.height))
        
        var screenAspectRatio = Float(screenSize.width / screenSize.height)
        
        let orientation = UIDevice.current.orientation
        var isLandscape = orientation.isLandscape
        
        var viewSize = drawableSize
        
        var adjustedGlassFrame = glassFrame
        if isInteractive && extendedFrameOffset > 0 {
            adjustedGlassFrame.origin.x += extendedFrameOffset
            adjustedGlassFrame.origin.y += extendedFrameOffset
        }
        
        var glassFrameData = SIMD4<Float>(
            Float(adjustedGlassFrame.origin.x * contentScaleFactor),
            Float(adjustedGlassFrame.origin.y * contentScaleFactor),
            Float(glassFrame.width * contentScaleFactor),
            Float(glassFrame.height * contentScaleFactor)
        )
        
        var glassScreenPosData = SIMD4<Float>(
            Float(glassScreenPosition.origin.x * contentScaleFactor),
            Float(glassScreenPosition.origin.y * contentScaleFactor),
            Float(glassScreenPosition.width * contentScaleFactor),
            Float(glassScreenPosition.height * contentScaleFactor)
        )
        
        let maxRadius = min(glassFrame.width, glassFrame.height) / 2.0
        let cappedRadius = min(cornerRadius, maxRadius)
        var cornerRadiusData = Float(cappedRadius * contentScaleFactor)
        
        var blurIntensityData = Float(blurIntensity)
        var isYCbCr = cbcrTexture != nil
        
        var interactiveData: [SIMD4<Float>] = []
        var interactiveCount: Int32 = 0
        
        if isInteractive {
            let nearbyGlasses = PixeluxInteractionManager.shared.getNearbyGlasses(for: glassID, within: 200)
            interactiveCount = Int32(min(nearbyGlasses.count, 8))
            
            for i in 0..<Int(interactiveCount) {
                let glass = nearbyGlasses[i]
                
                let currentCenter = CGPoint(
                    x: glassScreenPosition.midX,
                    y: glassScreenPosition.midY
                )
                let otherCenter = CGPoint(
                    x: glass.screenPosition.midX,
                    y: glass.screenPosition.midY
                )
                
                let relativeScreenX = (otherCenter.x - currentCenter.x) * contentScaleFactor
                let relativeScreenY = (otherCenter.y - currentCenter.y) * contentScaleFactor
                
                let relativePos = SIMD2<Float>(
                    Float(relativeScreenX),
                    Float(relativeScreenY)
                )
                
                let radius = Float(min(glass.frame.width, glass.frame.height) * 0.5 * contentScaleFactor)
                interactiveData.append(SIMD4<Float>(relativePos.x, relativePos.y, radius, Float(glass.cornerRadius * contentScaleFactor)))
            }
            
            while interactiveData.count < 8 {
                interactiveData.append(SIMD4<Float>(0, 0, 0, 0))
            }
        }
        
        renderEncoder.setFragmentBytes(&viewSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        renderEncoder.setFragmentBytes(&glassFrameData, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        renderEncoder.setFragmentBytes(&cornerRadiusData, length: MemoryLayout<Float>.size, index: 2)
        renderEncoder.setFragmentBytes(&blurIntensityData, length: MemoryLayout<Float>.size, index: 3)
        renderEncoder.setFragmentBytes(&transformMatrix, length: MemoryLayout<simd_float3x3>.size, index: 4)
        renderEncoder.setFragmentBytes(&isYCbCr, length: MemoryLayout<Bool>.size, index: 5)
        renderEncoder.setFragmentBytes(&screenDimensions, length: MemoryLayout<SIMD2<Float>>.size, index: 6)
        renderEncoder.setFragmentBytes(&glassScreenPosData, length: MemoryLayout<SIMD4<Float>>.size, index: 7)
        renderEncoder.setFragmentBytes(&cameraDimensions, length: MemoryLayout<SIMD2<Float>>.size, index: 8)
        renderEncoder.setFragmentBytes(&screenAspectRatio, length: MemoryLayout<Float>.size, index: 9)
        renderEncoder.setFragmentBytes(&isLandscape, length: MemoryLayout<Bool>.size, index: 10)
        
        if isInteractive {
            renderEncoder.setFragmentBytes(&interactiveCount, length: MemoryLayout<Int32>.size, index: 11)
            renderEncoder.setFragmentBytes(&interactiveData, length: MemoryLayout<SIMD4<Float>>.size * 8, index: 12)
        }
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    /**
     Creates a Metal texture from a specific plane of a YCbCr pixel buffer
     
     - Parameters:
        - pixelBuffer: Source CVPixelBuffer
        - planeIndex: Plane index (0 for Y, 1 for CbCr)
        - pixelFormat: Metal pixel format for the texture
     
     - Returns: Created MTLTexture or nil if creation failed
     */
    private func createTextureFromPlane(pixelBuffer: CVPixelBuffer, planeIndex: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            planeIndex,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        
        return texture
    }
    
    /**
     Creates a Metal texture from a BGRA pixel buffer
     
     - Parameter pixelBuffer: Source CVPixelBuffer
     - Returns: Created MTLTexture or nil if creation failed
     */
    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        
        return texture
    }
}