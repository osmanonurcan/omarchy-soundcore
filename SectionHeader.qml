import QtQuick
import qs.Ui
import qs.Commons

// The title of a section that expands and collapses when clicked.
Item {
  id: root

  property string title: ""
  property bool expanded: false
  property QtObject bar: null

  signal toggled()

  width: parent ? parent.width : implicitWidth
  implicitHeight: titleText.implicitHeight

  PanelSectionHeader {
    id: titleText
    anchors.left: parent.left
    anchors.right: chevron.left
    text: root.title.toUpperCase()
    elide: Text.ElideRight
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
  }

  Text {
    id: chevron
    anchors.right: parent.right
    anchors.verticalCenter: titleText.verticalCenter
    textFormat: Text.PlainText
    text: root.expanded ? "󰅀" : "󰅂"
    color: Qt.darker(root.bar.foreground, area.containsMouse ? 1.0 : 1.4)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
