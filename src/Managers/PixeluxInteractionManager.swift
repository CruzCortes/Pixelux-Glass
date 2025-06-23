import SwiftUI
import MetalKit
import Metal
import ARKit

/**
 Manages interaction state between multiple PixeluxLiquidGlass instances
 
 This singleton class tracks all interactive glass views in the application,
 handles their registration/unregistration, and calculates proximity relationships
 for merging effects between nearby glass instances.
 */
public class PixeluxInteractionManager: ObservableObject {
    /**
     Shared singleton instance for global access
     */
    public static let shared = PixeluxInteractionManager()
    
    @Published private var interactiveGlasses: [UUID: PixeluxInteractiveGlassInfo] = [:]
    
    /**
     Information structure for tracking interactive glass instances
     
     - Parameters:
        - id: Unique identifier for the glass instance
        - frame: Local frame bounds of the glass view
        - screenPosition: Absolute screen position for proximity calculations
        - cornerRadius: Corner radius for proper SDF blending
        - metalView: Weak reference to the associated Metal rendering view
     */
    public struct PixeluxInteractiveGlassInfo {
        let id: UUID
        var frame: CGRect
        var screenPosition: CGRect
        var cornerRadius: CGFloat
        weak var metalView: PixeluxMetalView?
    }
    
    private init() {}
    
    /**
     Registers a new interactive glass instance for tracking
     
     - Parameters:
        - id: Unique identifier for the glass
        - frame: Local bounds of the glass
        - screenPosition: Screen-space position
        - cornerRadius: Corner radius value
        - metalView: Associated Metal rendering view
     */
    func register(_ id: UUID, frame: CGRect, screenPosition: CGRect, cornerRadius: CGFloat, metalView: PixeluxMetalView) {
        interactiveGlasses[id] = PixeluxInteractiveGlassInfo(
            id: id,
            frame: frame,
            screenPosition: screenPosition,
            cornerRadius: cornerRadius,
            metalView: metalView
        )
    }
    
    /**
     Removes a glass instance from tracking
     
     - Parameter id: Identifier of the glass to unregister
     */
    func unregister(_ id: UUID) {
        interactiveGlasses.removeValue(forKey: id)
    }
    
    /**
     Updates the position of a tracked glass instance
     
     - Parameters:
        - id: Identifier of the glass to update
        - frame: New local frame bounds
        - screenPosition: New screen-space position
     */
    func updatePosition(_ id: UUID, frame: CGRect, screenPosition: CGRect) {
        interactiveGlasses[id]?.frame = frame
        interactiveGlasses[id]?.screenPosition = screenPosition
    }
    
    /**
     Finds all glass instances within interaction distance of a specified glass
     
     - Parameters:
        - id: Identifier of the glass to check from
        - distance: Maximum distance for interaction consideration
     
     - Returns: Array of nearby interactive glass instances
     */
    func getNearbyGlasses(for id: UUID, within distance: CGFloat) -> [PixeluxInteractiveGlassInfo] {
        guard let currentGlass = interactiveGlasses[id] else { return [] }
        
        return interactiveGlasses.values.filter { glass in
            guard glass.id != id else { return false }
            
            let currentCenter = CGPoint(
                x: currentGlass.screenPosition.midX,
                y: currentGlass.screenPosition.midY
            )
            let otherCenter = CGPoint(
                x: glass.screenPosition.midX,
                y: glass.screenPosition.midY
            )
            
            let dx = currentCenter.x - otherCenter.x
            let dy = currentCenter.y - otherCenter.y
            let centerDistance = sqrt(dx * dx + dy * dy)
            
            let combinedRadii = (currentGlass.frame.width + glass.frame.width) / 2.0
            
            let sizeRatio = min(currentGlass.frame.width, glass.frame.width) /
                           max(currentGlass.frame.width, glass.frame.width)
            let adjustedDistance = distance * (0.5 + 0.5 * sizeRatio)
            
            return centerDistance < combinedRadii + adjustedDistance
        }
    }
}