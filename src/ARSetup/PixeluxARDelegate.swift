import SwiftUI
import ARKit
import RealityKit
// Any other imports

/**
 PixeluxLiquidGlass ARKit Integration Guide
 
 This guide shows how to integrate PixeluxLiquidGlass into your EXISTING ARKit project.
 PixeluxLiquidGlass requires ARFrame updates from your AR session to render the glass effect.
 
 IMPORTANT: You need to add specific code to your existing ARDelegate class.
 */

/**
 STEP 1: Update Your Existing ARDelegate
 
 Add the required property and frame update code to your existing ARDelegate.
 Below is an example of what your ARDelegate should look like after integration.
 */
class ARDelegate: NSObject, ARSessionDelegate, ObservableObject {
    var session: ARSession
    var arView: ARView!
    
    @Published var statusMessage = ""
    
    /**
     REQUIRED: Add this property to your existing ARDelegate
     This publishes frame updates that PixeluxLiquidGlass needs
     */
    @Published var currentFrame: ARFrame?
    
    override init() {
        self.session = ARSession()
        self.arView = ARView(frame: .zero)
        super.init()
        
        self.session.delegate = self
        self.arView.session = session
        self.arView.session.delegate = self
    }
    
    /**
     REQUIRED: Add frame publishing to your session delegate method
     If you already have this method, just add the currentFrame update
     */
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        /**
         Add this code block to publish frames for PixeluxLiquidGlass
         This MUST be dispatched on the main queue
         */
        DispatchQueue.main.async {
            self.currentFrame = frame
        }
        
        /**
         Your existing session update code goes here...
         Don't remove any of your existing functionality
         */
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Session error: \(error)")
        statusMessage = "AR Error"
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        statusMessage = "Session interrupted"
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        statusMessage = ""
    }
    
    func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        session.run(config)
        print("AR Session started")
    }
}

/**
 STEP 2: Create ARDelegateWithFrames (Optional Subclass)
 
 If you prefer to keep your main ARDelegate clean, you can create a subclass
 that adds the frame publishing functionality.
 */
class ARDelegateWithFrames: ARDelegate {
    /**
     This subclass adds currentFrame publishing to your base ARDelegate
     */
    @Published var currentFrame: ARFrame?
    
    override func session(_ session: ARSession, didUpdate frame: ARFrame) {
        super.session(session, didUpdate: frame)
        DispatchQueue.main.async {
            self.currentFrame = frame
        }
    }
}

/**
 INTEGRATION SUMMARY - Add This To Your Existing Code:
 
 1. Add to your ARDelegate class properties:
    @Published var currentFrame: ARFrame?
 
 2. Add to your session(_:didUpdate:) method:
    DispatchQueue.main.async {
        self.currentFrame = frame
    }
 
 That's it! Your ARDelegate is now ready for PixeluxLiquidGlass.
 */

/**
 USAGE EXAMPLE: Using PixeluxLiquidGlass with Your Updated ARDelegate
 */
struct YourARView: View {
    /**
     Use your existing ARDelegate with the added currentFrame property
     */
    @StateObject private var arDelegate = ARDelegate()
    
    var body: some View {
        ZStack {
            /**
             Your existing AR view setup
             */
            ARViewContainer(arDelegate: arDelegate)
                .ignoresSafeArea()
            
            /**
             Add PixeluxLiquidGlass components anywhere in your UI
             The binding to currentFrame is REQUIRED
             */
            VStack {
                Spacer()
                
                PixeluxLiquidGlass(currentFrame: $arDelegate.currentFrame)
                    .cornerRadius(30)
                    .blurIntensity(0.3)
                    .frame(width: 200, height: 200)
                
                HStack(spacing: 20) {
                    PixeluxLiquidGlass(currentFrame: $arDelegate.currentFrame)
                        .cornerRadius(20)
                        .interactive(true)
                        .frame(width: 80, height: 80)
                    
                    PixeluxLiquidGlass(currentFrame: $arDelegate.currentFrame)
                        .cornerRadius(20)
                        .interactive(true)
                        .frame(width: 80, height: 80)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            arDelegate.startSession()
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let arDelegate: ARDelegate
    
    func makeUIView(context: Context) -> ARView {
        return arDelegate.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}