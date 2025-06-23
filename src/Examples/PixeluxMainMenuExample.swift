import SwiftUI
import ARKit

/**
 Example implementation of an AR menu using PixeluxLiquidGlass
 
 Demonstrates interactive glass elements with animation states,
 expandable containers, and button interactions in an AR context.
 */
struct PixeluxMainMenuExample: View {
    @ObservedObject var arDelegate: PixeluxARDelegateWithFrames
    
    let topButtons = [
        ("gearshape", "Settings"),
        ("sparkles", "Sparkles"),
        ("note.text", "Notes"),
        ("bubble.left", "Chat")
    ]
    
    @State private var menuExpanded = false
    @State private var showButtons = false
    @State private var isAnimating = false
    @State private var selectedButton: String? = nil
    @State private var containerExpanded = false
    
    var body: some View {
        VStack {
            Spacer()
            
            ZStack {
                PixeluxLiquidGlass(currentFrame: $arDelegate.currentFrame)
                    .cornerRadius(40)
                    .blurIntensity(0.3)
                    .distortionStrength(1.2)
                    .frame(width: 320, height: containerExpanded ? 470 : 320)
                    .offset(y: containerExpanded ? 0 : -80)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: containerExpanded)
                
                VStack(spacing: 16) {
                    Image("image_placeholder")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 204)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack {
                        if containerExpanded {
                            Text(getTitle())
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("v 1.0")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Always watch your surroundings while\nusing AR apps.")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .offset(y: -80)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding()
                .frame(width: 320, height: 470)
            }
            
            Spacer()
            
            ZStack {
                if showButtons {
                    ZStack {
                        HStack(spacing: 20) {
                            ForEach(Array(topButtons.enumerated()), id: \.offset) { index, _ in
                                PixeluxLiquidGlass(currentFrame: $arDelegate.currentFrame)
                                    .cornerRadius(20)
                                    .blurIntensity(0.3)
                                    .distortionStrength(1.2)
                                    .interactive(true)
                                    .frame(width: 40, height: 40)
                                    .offset(y: menuExpanded ? -70 : 0)
                                    .animation(.easeInOut(duration: 1.0).delay(Double(index) * 0.05), value: menuExpanded)
                            }
                        }
                        
                        HStack(spacing: 20) {
                            ForEach(Array(topButtons.enumerated()), id: \.offset) { index, button in
                                Button(action: {
                                    if selectedButton == button.0 && containerExpanded {
                                        selectedButton = nil
                                        containerExpanded = false
                                    } else {
                                        selectedButton = button.0
                                        containerExpanded = true
                                    }
                                    print("\(button.1) tapped")
                                }) {
                                    Image(systemName: button.0)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.white)
                                }
                                .frame(width: 40, height: 40)
                                .offset(y: menuExpanded ? -70 : 0)
                                .animation(.easeInOut(duration: 1.0).delay(Double(index) * 0.05), value: menuExpanded)
                            }
                        }
                    }
                    .allowsHitTesting(menuExpanded)
                }
                
                PixeluxLiquidGlass(currentFrame: $arDelegate.currentFrame)
                    .cornerRadius(40)
                    .blurIntensity(0.3)
                    .distortionStrength(1.2)
                    .interactive(true)
                    .frame(width: 246, height: 64)
                
                HStack(spacing: 40) {
                    Button(action: {
                        if !isAnimating {
                            isAnimating = true
                            
                            if menuExpanded {
                                menuExpanded = false
                                selectedButton = nil
                                containerExpanded = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    isAnimating = false
                                    if !menuExpanded {
                                        showButtons = false
                                    }
                                }
                            } else {
                                showButtons = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                    menuExpanded = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        isAnimating = false
                                    }
                                }
                            }
                        } else {
                            menuExpanded.toggle()
                        }
                    }) {
                        Image(systemName: "ellipsis")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white)
                    }

                    Button(action: {
                    }) {
                        Image(systemName: "folder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white)
                    }

                    Button(action: {
                    }) {
                        Image(systemName: "pencil")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 246)
            }
        }
    }
    
    func getTitle() -> String {
        switch selectedButton {
        case "gearshape": return "Settings"
        case "sparkles": return "Sparkles"
        case "note.text": return "Notes"
        case "bubble.left": return "Chat"
        default: return ""
        }
    }
}

/**
 Preview provider for SwiftUI canvas
 */
#Preview {
    PixeluxMainMenuExample(arDelegate: PixeluxARDelegateWithFrames())
}