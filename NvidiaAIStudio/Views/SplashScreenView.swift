import SwiftUI

/// Apple-style animated splash screen shown as the first view.
/// Uses the same neural brain aesthetic as the app icon.
struct SplashScreenView: View {
    @Binding var isFinished: Bool
    
    @State private var iconScale: CGFloat = 0.6
    @State private var iconBlur: CGFloat = 20
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 12
    @State private var subtitleOpacity: Double = 0
    @State private var glowOpacity: Double = 0.4
    @State private var dotsIndex = 0
    
    // Timer for animating dots
    private let dotsTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Deep dark gradient background (navy → dark purple)
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.06, green: 0.03, blue: 0.12),
                    Color(red: 0.04, green: 0.04, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Neural brain icon
                ZStack {
                    // Glow behind icon
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.46, green: 0.72, blue: 0).opacity(glowOpacity * 0.4),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 140
                            )
                        )
                        .frame(width: 280, height: 280)
                    
                    // Brain neural network — drawn with SF Symbol + stylized paths
                    NeuralBrainShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.46, green: 0.72, blue: 0),    // NVIDIA green
                                    Color(red: 0.30, green: 0.85, blue: 0.20)  // bright green
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: Color(red: 0.46, green: 0.72, blue: 0).opacity(0.8), radius: 8)
                        .shadow(color: Color(red: 0.46, green: 0.72, blue: 0).opacity(0.4), radius: 20)
                        .frame(width: 120, height: 100)
                }
                .scaleEffect(iconScale)
                .blur(radius: iconBlur)
                
                Spacer()
                    .frame(height: 40)
                
                // Title
                Text("Nvidia AI Studio")
                    .font(.system(size: 32, weight: .ultraLight, design: .default))
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)
                
                Spacer()
                    .frame(height: 10)
                
                // Subtitle with animated dots
                Text("AI Development Environment" + String(repeating: ".", count: dotsIndex))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .opacity(subtitleOpacity)
                    .onReceive(dotsTimer) { _ in
                        dotsIndex = (dotsIndex + 1) % 4
                    }
                
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Icon: scale + blur → clear (spring)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3)) {
            iconScale = 1.0
            iconBlur = 0
        }
        
        // Glow pulse
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.5)) {
            glowOpacity = 1.0
        }
        
        // Title fade-in + slide
        withAnimation(.easeOut(duration: 0.6).delay(0.9)) {
            titleOpacity = 1.0
            titleOffset = 0
        }
        
        // Subtitle
        withAnimation(.easeOut(duration: 0.5).delay(1.1)) {
            subtitleOpacity = 1.0
        }
        
        // Dismiss after 2.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isFinished = false
            }
        }
    }
}

// MARK: - Neural Brain Shape

/// A stylized neural network / brain outline drawn with paths.
struct NeuralBrainShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Brain outline (simplified)
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.05))
        path.addCurve(
            to: CGPoint(x: w * 0.95, y: h * 0.40),
            control1: CGPoint(x: w * 0.75, y: h * 0.02),
            control2: CGPoint(x: w * 0.95, y: h * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.70, y: h * 0.80),
            control1: CGPoint(x: w * 0.95, y: h * 0.60),
            control2: CGPoint(x: w * 0.85, y: h * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.95),
            control1: CGPoint(x: w * 0.62, y: h * 0.85),
            control2: CGPoint(x: w * 0.55, y: h * 0.95)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.25, y: h * 0.78),
            control1: CGPoint(x: w * 0.42, y: h * 0.95),
            control2: CGPoint(x: w * 0.30, y: h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.05, y: h * 0.42),
            control1: CGPoint(x: w * 0.10, y: h * 0.72),
            control2: CGPoint(x: w * 0.05, y: h * 0.60)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.05),
            control1: CGPoint(x: w * 0.05, y: h * 0.20),
            control2: CGPoint(x: w * 0.25, y: h * 0.02)
        )
        
        // Internal neural connections
        let nodes: [CGPoint] = [
            CGPoint(x: w * 0.35, y: h * 0.25),
            CGPoint(x: w * 0.55, y: h * 0.20),
            CGPoint(x: w * 0.72, y: h * 0.30),
            CGPoint(x: w * 0.65, y: h * 0.50),
            CGPoint(x: w * 0.45, y: h * 0.45),
            CGPoint(x: w * 0.30, y: h * 0.50),
            CGPoint(x: w * 0.20, y: h * 0.38),
            CGPoint(x: w * 0.40, y: h * 0.65),
            CGPoint(x: w * 0.60, y: h * 0.65),
            CGPoint(x: w * 0.50, y: h * 0.80),
        ]
        
        // Draw connections between nodes
        let connections = [(0,1), (1,2), (2,3), (3,4), (4,5), (5,6), (6,0), (4,1), (3,8), (5,7), (7,8), (7,9), (8,9), (4,7), (4,8)]
        for (a, b) in connections {
            path.move(to: nodes[a])
            path.addLine(to: nodes[b])
        }
        
        // Draw node dots
        for node in nodes {
            path.addEllipse(in: CGRect(x: node.x - 3, y: node.y - 3, width: 6, height: 6))
        }
        
        return path
    }
}
