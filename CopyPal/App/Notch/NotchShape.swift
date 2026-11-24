import SwiftUI

/// The notch silhouette, drawn at the top center of its rect: flush with the top
/// edge, concave flares where it meets the edge, rounded bottom corners. All four
/// values animate, so the same shape grows from the camera housing into the popup
/// and back without resizing any view.
struct NotchShape: Shape {
    var bodyWidth: CGFloat
    var height: CGFloat
    var bottomRadius: CGFloat
    var flare: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(bodyWidth, height), AnimatablePair(bottomRadius, flare)) }
        set {
            bodyWidth = newValue.first.first
            height = newValue.first.second
            bottomRadius = newValue.second.first
            flare = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let flare = max(0, min(flare, (rect.width - bodyWidth) / 2))
        let width = max(0, min(bodyWidth, rect.width - 2 * flare))
        let height = max(0, min(height, rect.height))
        guard width > 0, height > 0 else { return Path() }
        let topFlare = min(flare, height / 2)
        let radius = max(0, min(bottomRadius, width / 2, height - topFlare))

        let left = rect.midX - width / 2
        let right = rect.midX + width / 2
        let top = rect.minY
        let bottom = rect.minY + height

        var path = Path()
        path.move(to: CGPoint(x: left - topFlare, y: top))
        path.addLine(to: CGPoint(x: right + topFlare, y: top))
        corner(&path, at: CGPoint(x: right, y: top), to: CGPoint(x: right, y: top + topFlare), radius: topFlare)
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        corner(&path, at: CGPoint(x: right, y: bottom), to: CGPoint(x: right - radius, y: bottom), radius: radius)
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        corner(&path, at: CGPoint(x: left, y: bottom), to: CGPoint(x: left, y: bottom - radius), radius: radius)
        path.addLine(to: CGPoint(x: left, y: top + topFlare))
        corner(&path, at: CGPoint(x: left, y: top), to: CGPoint(x: left - topFlare, y: top), radius: topFlare)
        path.closeSubpath()
        return path
    }

    /// Rounds the corner at `point` towards `next`; a plain corner when `radius` is 0.
    private func corner(_ path: inout Path, at point: CGPoint, to next: CGPoint, radius: CGFloat) {
        if radius > 0.01 {
            path.addArc(tangent1End: point, tangent2End: next, radius: radius)
        } else {
            path.addLine(to: point)
        }
    }
}
