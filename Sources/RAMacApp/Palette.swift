import SwiftUI

enum RAMPalette {
    static let ground = Color(red: 0.075, green: 0.094, blue: 0.078)
    static let shelf = Color(red: 0.105, green: 0.132, blue: 0.110)
    static let raised = Color(red: 0.135, green: 0.165, blue: 0.139)
    static let ink = Color(red: 0.946, green: 0.936, blue: 0.891)
    static let muted = Color(red: 0.646, green: 0.665, blue: 0.610)
    static let straw = Color(red: 0.812, green: 0.760, blue: 0.538)
    static let rust = Color(red: 0.647, green: 0.313, blue: 0.236)
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? RAMPalette.ground : RAMPalette.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? RAMPalette.straw : RAMPalette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct LaunchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(RAMPalette.ground)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(configuration.isPressed ? RAMPalette.ink : RAMPalette.straw)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(RAMPalette.ink)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(configuration.isPressed ? RAMPalette.rust : RAMPalette.ground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct AccountCutShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(rect.width, rect.height) * 0.22
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 8))
        path.addQuadCurve(to: CGPoint(x: 8, y: 0), control: .zero)
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 8))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 8, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: 8, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - 8),
            control: CGPoint(x: 0, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

struct LaunchDockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let cut: CGFloat = 34
        var path = Path()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - radius),
            control: CGPoint(x: 0, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}
