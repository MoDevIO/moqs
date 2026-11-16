import QtQuick
import QtQuick.Shapes
import qs.config

// Frame-coloured panel attached to the bottom-left inner corner, with concave
// fillets where it meets the left and bottom borders.
Shape {
    id: root

    readonly property real r: Math.max(0, Math.min(Config.border.rounding, width / 2, height / 2))

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: Config.border.colour
        strokeWidth: -1

        // Overlap the borders by 2px to avoid seams.
        startX: -2
        startY: -root.r

        PathLine { x: -2; y: root.height + 2 }
        PathLine { x: root.width + root.r; y: root.height + 2 }
        PathLine { x: root.width + root.r; y: root.height }
        PathArc {
            x: root.width
            y: root.height - root.r
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: root.width; y: root.r }
        PathArc {
            x: root.width - root.r
            y: 0
            radiusX: root.r
            radiusY: root.r
            direction: PathArc.Counterclockwise
        }
        PathLine { x: root.r; y: 0 }
        PathArc {
            x: 0
            y: -root.r
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: -2; y: -root.r }
    }
}
