import QtQuick
import QtQuick.Shapes
import qs.config

// Frame-coloured panel standing on the bottom border, with concave fillets on both
// sides where it meets the border.
Shape {
    id: root

    readonly property real r: Math.max(0, Math.min(Config.border.rounding, width / 2, height / 2))

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: Config.border.colour
        strokeWidth: -1

        // Overlap the border by 2px to avoid seams.
        startX: -root.r
        startY: root.height + 2

        PathLine { x: -root.r; y: root.height }
        PathArc {
            x: 0
            y: root.height - root.r
            radiusX: root.r
            radiusY: root.r
            direction: PathArc.Counterclockwise
        }
        PathLine { x: 0; y: root.r }
        PathArc {
            x: root.r
            y: 0
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: root.width - root.r; y: 0 }
        PathArc {
            x: root.width
            y: root.r
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: root.width; y: root.height - root.r }
        PathArc {
            x: root.width + root.r
            y: root.height
            radiusX: root.r
            radiusY: root.r
            direction: PathArc.Counterclockwise
        }
        PathLine { x: root.width + root.r; y: root.height + 2 }
    }
}
