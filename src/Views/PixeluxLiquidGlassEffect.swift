import SwiftUI
import UIKit

/**
 UIViewRepresentable wrapper for integrating Metal-based glass rendering into SwiftUI
 
 This struct bridges the Metal rendering view with SwiftUI, handling layout updates,
 frame synchronization, and interactive state management. It creates the appropriate
 container hierarchy to support overflow rendering for interactive glass merging.
 */
struct PixeluxLiquidGlassEffect: UIViewRepresentable {
    let glassFrame: CGRect
    let cornerRadius: CGFloat
    let blurIntensity: CGFloat
    @Binding var currentFrame: ARFrame?
    let isInteractive: Bool
    let glassID: UUID
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView(frame: .zero)
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = false
        
        let metalView = PixeluxMetalView(frame: .zero, device: nil)
        metalView.glassFrame = glassFrame
        metalView.cornerRadius = cornerRadius
        metalView.blurIntensity = blurIntensity
        metalView.isInteractive = isInteractive
        metalView.glassID = glassID
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.clipsToBounds = false
        
        containerView.addSubview(metalView)
        
        if isInteractive {
            let glassSize = min(glassFrame.width, glassFrame.height)
            let overflow: CGFloat = min(200, glassSize * 0.8)
            
            NSLayoutConstraint.activate([
                metalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: -overflow),
                metalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: overflow),
                metalView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -overflow),
                metalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: overflow)
            ])
            
            context.coordinator.overflow = overflow
        } else {
            NSLayoutConstraint.activate([
                metalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                metalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                metalView.topAnchor.constraint(equalTo: containerView.topAnchor),
                metalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }
        
        context.coordinator.metalView = metalView
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let metalView = context.coordinator.metalView else { return }
        
        if let window = uiView.window {
            let screenFrame = uiView.convert(uiView.bounds, to: window)
            metalView.glassScreenPosition = screenFrame
            
            if isInteractive {
                DispatchQueue.main.async {
                    PixeluxInteractionManager.shared.updatePosition(
                        self.glassID,
                        frame: self.glassFrame,
                        screenPosition: screenFrame
                    )
                }
            }
        }
        
        metalView.glassFrame = glassFrame
        metalView.cornerRadius = cornerRadius
        metalView.blurIntensity = blurIntensity
        metalView.currentARFrame = currentFrame
        metalView.isInteractive = isInteractive
        
        if isInteractive {
            let glassSize = min(glassFrame.width, glassFrame.height)
            let overflow: CGFloat = context.coordinator.overflow ?? min(200, glassSize * 0.8)
            metalView.extendedFrameOffset = overflow
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    /**
     Coordinator for maintaining references between UIViewRepresentable updates
     */
    class Coordinator {
        var metalView: PixeluxMetalView?
        var overflow: CGFloat?
    }
}