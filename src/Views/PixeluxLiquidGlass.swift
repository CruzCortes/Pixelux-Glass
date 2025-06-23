import SwiftUI
import ARKit

/**
 A SwiftUI view that renders a liquid glass effect on ARKit camera frames
 
 This view creates a refractive glass material effect that processes ARKit camera
 frames in real-time. It supports customizable appearance properties and interactive
 mode where multiple glass instances can merge with fluid animations.
 
 Usage:
 ```swift
 PixeluxLiquidGlass(currentFrame: $arFrame)
     .cornerRadius(30)
     .blurIntensity(0.3)
     .interactive(true)
 ```
 */
public struct PixeluxLiquidGlass: View {
    private var cornerRadius: CGFloat = 30
    private var blurIntensity: CGFloat = 0.0
    private var isInteractive: Bool = false
    
    @Binding var currentFrame: ARFrame?
    
    @State private var metalView: PixeluxMetalView?
    @State private var glassID = UUID()
    @StateObject private var interactionManager = PixeluxInteractionManager.shared
    
    /**
     Initializes a new liquid glass view
     
     - Parameter currentFrame: Binding to the current ARFrame from ARKit session
     */
    public init(currentFrame: Binding<ARFrame?>) {
        self._currentFrame = currentFrame
    }
    
    public var body: some View {
        GeometryReader { geometry in
            PixeluxLiquidGlassEffect(
                glassFrame: CGRect(origin: .zero, size: geometry.size),
                cornerRadius: cornerRadius,
                blurIntensity: blurIntensity,
                currentFrame: $currentFrame,
                isInteractive: isInteractive,
                glassID: glassID
            )
            .allowsHitTesting(false)
        }
    }
}

extension PixeluxLiquidGlass {
    /**
     Sets the corner radius of the glass effect
     
     - Parameter radius: Corner radius in points
     - Returns: Modified view with updated corner radius
     */
    public func cornerRadius(_ radius: CGFloat) -> PixeluxLiquidGlass {
        var view = self
        view.cornerRadius = radius
        return view
    }
    
    /**
     Sets the blur intensity of the glass effect
     
     - Parameter intensity: Blur intensity from 0.0 (no blur) to 1.0 (maximum blur)
     - Returns: Modified view with updated blur intensity
     */
    public func blurIntensity(_ intensity: CGFloat) -> PixeluxLiquidGlass {
        var view = self
        view.blurIntensity = min(max(intensity, 0), 1)
        return view
    }
    
    /**
     Sets the distortion strength of the glass refraction
     
     - Parameter strength: Distortion strength value
     - Returns: Modified view (currently unimplemented, returns self)
     */
    public func distortionStrength(_ strength: CGFloat) -> PixeluxLiquidGlass {
        return self
    }
    
    /**
     Sets the opacity of the glass effect
     
     - Parameter opacity: Glass opacity value
     - Returns: Modified view (currently unimplemented, returns self)
     */
    public func glassOpacity(_ opacity: CGFloat) -> PixeluxLiquidGlass {
        return self
    }
    
    /**
     Enables or disables interactive mode for glass merging
     
     - Parameter enabled: Whether interactive merging is enabled
     - Returns: Modified view with updated interactive state
     */
    public func interactive(_ enabled: Bool) -> PixeluxLiquidGlass {
        var view = self
        view.isInteractive = enabled
        return view
    }
}