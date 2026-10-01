import QtQuick
import QtQuick.Shapes
import qs.Commons

// The omasnapper mark from assets/omasnapper.png: three stacked snapshot
// frames, the front one holding a restore arrow. Drawn on an 18 x 18 grid
// with 1.5-unit strokes so it stays crisp at bar size, in theme colours
// rather than the artwork's fixed teal. The back frames only draw the edges
// the front frame leaves visible, so no fill is needed to hide them and the
// mark works on a transparent bar.
Item {
  id: root

  property real iconSize: Style.space(18)
  property color color: Color.foreground
  // The arrow; the artwork draws it lighter than the frames.
  property color arrowColor: color
  // How strongly the back frames show, nearest first.
  property real middleOpacity: 0.6
  property real backOpacity: 0.32

  readonly property real u: iconSize / 18
  readonly property real stroke: 1.5
  readonly property real r: 2.5

  width: iconSize
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    // Back frame: x 5.25..17.25, y 0.75..12.75; visible where the middle one is not.
    BackEdge { ox: 5.25; oy: 0.75; opacityValue: root.backOpacity }
    // Middle frame: x 3..15, y 3..15; visible where the front one is not.
    BackEdge { ox: 3; oy: 3; opacityValue: root.middleOpacity }

    // Front frame: x 0.75..12.75, y 5.25..17.25.
    ShapePath {
      strokeColor: root.color
      strokeWidth: root.stroke * root.u
      fillColor: "transparent"
      PathRectangle {
        x: 0.75 * root.u; y: 5.25 * root.u
        width: 12 * root.u; height: 12 * root.u
        radius: root.r * root.u
      }
    }

    // Restore arrow: an open circle from the top, round the left and
    // bottom, ending at the right with its gap at the upper right.
    ShapePath {
      strokeColor: root.arrowColor
      strokeWidth: root.stroke * root.u
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: root.cx * root.u; centerY: root.cy * root.u
        radiusX: root.ar * root.u; radiusY: root.ar * root.u
        startAngle: -80; sweepAngle: -270
      }
    }

    // Arrowhead at the arc's end, pointing along it.
    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillColor: root.arrowColor
      startX: root.headTip.x * root.u
      startY: root.headTip.y * root.u
      PathLine { x: root.headLeft.x * root.u; y: root.headLeft.y * root.u }
      PathLine { x: root.headRight.x * root.u; y: root.headRight.y * root.u }
      PathLine { x: root.headTip.x * root.u; y: root.headTip.y * root.u }
    }
  }

  // Arrow geometry, in grid units: the circle, where the arc ends (10
  // degrees, just below three o'clock), and the head's three corners. The
  // arc runs counterclockwise on screen, so at its end it travels along
  // (sin a, -cos a).
  readonly property real cx: 6.75
  readonly property real cy: 11.25
  readonly property real ar: 3
  readonly property real endAngle: 10 * Math.PI / 180
  readonly property point headBase: Qt.point(cx + ar * Math.cos(endAngle), cy + ar * Math.sin(endAngle))
  readonly property point headTip: Qt.point(headBase.x + 2.1 * Math.sin(endAngle), headBase.y - 2.1 * Math.cos(endAngle))
  readonly property point headLeft: Qt.point(headBase.x - 1.6 * Math.cos(endAngle), headBase.y - 1.6 * Math.sin(endAngle))
  readonly property point headRight: Qt.point(headBase.x + 1.6 * Math.cos(endAngle), headBase.y + 1.6 * Math.sin(endAngle))

  // The parts of a back frame (top-left at ox, oy; 12 x 12) not covered by
  // the frame 2.25 units in front of it: the left edge above it, the top,
  // the right edge, and the bottom to its right. One open stroke.
  component BackEdge: ShapePath {
    property real ox: 0
    property real oy: 0
    property real opacityValue: 1
    readonly property real s: 12
    readonly property real d: 2.25   // offset to the frame in front

    strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * opacityValue)
    strokeWidth: root.stroke * root.u
    fillColor: "transparent"
    capStyle: ShapePath.FlatCap
    joinStyle: ShapePath.RoundJoin

    startX: ox * root.u
    startY: (oy + d + 0.75) * root.u
    PathLine { x: ox * root.u; y: (oy + root.r) * root.u }
    PathArc {
      x: (ox + root.r) * root.u; y: oy * root.u
      radiusX: root.r * root.u; radiusY: root.r * root.u
    }
    PathLine { x: (ox + s - root.r) * root.u; y: oy * root.u }
    PathArc {
      x: (ox + s) * root.u; y: (oy + root.r) * root.u
      radiusX: root.r * root.u; radiusY: root.r * root.u
    }
    PathLine { x: (ox + s) * root.u; y: (oy + s - root.r) * root.u }
    PathArc {
      x: (ox + s - root.r) * root.u; y: (oy + s) * root.u
      radiusX: root.r * root.u; radiusY: root.r * root.u
    }
    PathLine { x: (ox + s - d - 0.75) * root.u; y: (oy + s) * root.u }
  }
}
