import QtQuick
import QtQuick.Shapes
import qs.config

// Frame-coloured panel attached to the top-right inner corner, with concave
// fillets where it meets the top and right borders so it reads as part of the frame.
Shape {
    id: root

    readonly property real r: Math.max(0, Math.min(Config.border.rounding, width / 2, height / 2))

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: Config.border.colour
        strokeWidth: -1

        // Overlap the borders by 2px to avoid seams.
        startX: -root.r
        startY: -2

        PathLine { x: root.width + 2; y: -2 }
        PathLine { x: root.width + 2; y: root.height + root.r }
        PathLine { x: root.width; y: root.height + root.r }
        PathArc {
            x: root.width - root.r
            y: root.height
            radiusX: root.r
            radiusY: root.r
            direction: PathArc.Counterclockwise
        }
        PathLine { x: root.r; y: root.height }
        PathArc {
            x: 0
            y: root.height - root.r
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: 0; y: root.r }
        PathArc {
            x: -root.r
            y: 0
            radiusX: root.r
            radiusY: root.r
            direction: PathArc.Counterclockwise
        }
        PathLine { x: -root.r; y: -2 }
    }
}
