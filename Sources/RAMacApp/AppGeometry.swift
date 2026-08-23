import AppKit
import SwiftUI

enum AppGeometry {
    static let windowCornerRadius: CGFloat = 20
    static let panelCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 6

    static let windowEdgeControlInset = windowCornerRadius - controlCornerRadius
    static let panelEdgeControlInset = panelCornerRadius - controlCornerRadius
    static let compactInset: CGFloat = 8
    static let windowContentInset: CGFloat = 20

    static let smallThumbnailRadius: CGFloat = 8
    static let largeThumbnailRadius: CGFloat = 12

    static func innerRadius(outerRadius: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outerRadius - inset)
    }

    static func thumbnailRadius(for size: CGFloat) -> CGFloat {
        max(controlCornerRadius, size * 0.15)
    }
}

private struct AppRoundedPanelModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }
}

extension View {
    func appRoundedPanel(radius: CGFloat = AppGeometry.panelCornerRadius) -> some View {
        modifier(AppRoundedPanelModifier(radius: radius))
    }
}
