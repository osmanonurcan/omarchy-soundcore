import QtQuick
import qs.Ui
import qs.Commons
import "Model.js" as Model

// One device setting, drawn by its openscq30 type: a row of choices or a
// dropdown for a select, a switch for a toggle, a stepped slider for a range,
// a line of text for information, and a button for an action.
Column {
  id: root

  property var setting: null
  property var value
  property string label: ""
  property QtObject bar: null
  readonly property bool popupOpen: dropdown.popupOpen

  // The user picked `value`.
  signal edited(var value)

  readonly property string type: setting ? setting.type : ""
  readonly property var options: Model.selectOptions(setting, value)
  readonly property bool isSelect: type === "select" || type === "optionalSelect" || type === "modifiableSelect"
  readonly property bool asButtons: type === "select" && options.length <= 3
  readonly property var range: Model.rangeOf(setting)
  readonly property bool oneLine: type === "toggle" || type === "information" || type === "action"

  // An action can't be undone, so it takes a second click.
  property bool armed: false

  function snap(v) {
    return root.range.min + Math.round((v - root.range.min) / root.range.step) * root.range.step
  }

  spacing: Style.space(6)

  Item {
    visible: !root.oneLine
    width: parent.width
    implicitHeight: header.implicitHeight

    PanelSectionHeader {
      id: header
      anchors.left: parent.left
      text: root.label.toUpperCase()
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Text {
      visible: root.type === "i32Range"
      anchors.right: parent.right
      anchors.verticalCenter: header.verticalCenter
      textFormat: Text.PlainText
      text: Model.rangeText(root.setting ? root.setting.settingId : "", root.snap(slider.liveValue))
      color: Qt.darker(root.bar.foreground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  ButtonGroup {
    visible: root.asButtons
    width: parent.width
    options: root.options
    value: Model.formatValue(root.value)
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    onChanged: function(v) { root.edited(v) }
  }

  Dropdown {
    id: dropdown
    visible: root.isSelect && !root.asButtons
    width: parent.width
    showLabel: false
    options: root.options
    value: Model.formatValue(root.value)
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    onChanged: function(v) {
      root.edited(v)
      // Dropdown assigns its own `value` when an option is picked, which
      // would otherwise break the binding above for good.
      dropdown.value = Qt.binding(function() { return Model.formatValue(root.value) })
    }
  }

  Item {
    visible: root.type === "toggle"
    width: parent.width
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggle.implicitHeight)

    Text {
      id: toggleLabel
      anchors.left: parent.left
      anchors.right: toggle.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.label
      elide: Text.ElideRight
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: root.value === true
      foreground: root.bar.foreground
      onToggled: root.edited(!toggle.checked)
    }
  }

  Item {
    visible: root.type === "information"
    width: parent.width
    implicitHeight: infoLabel.implicitHeight

    Text {
      id: infoLabel
      anchors.left: parent.left
      anchors.right: infoValue.left
      anchors.rightMargin: Style.space(8)
      textFormat: Text.PlainText
      text: root.label
      elide: Text.ElideRight
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: infoValue
      anchors.right: parent.right
      anchors.verticalCenter: infoLabel.verticalCenter
      width: Math.min(implicitWidth, parent.width / 2)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: root.value === undefined || root.value === null ? "–" : String(root.value)
      elide: Text.ElideRight
      color: Qt.darker(root.bar.foreground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Button {
    visible: root.type === "action"
    text: root.armed ? root.label + "?" : root.label
    bordered: true
    foreground: root.armed ? root.bar.urgent : root.bar.foreground
    fontFamily: root.bar.fontFamily
    onClicked: {
      if (!root.armed) {
        root.armed = true
        disarm.restart()
        return
      }
      root.armed = false
      root.edited("")
    }
  }

  Timer {
    id: disarm
    interval: 4000
    onTriggered: root.armed = false
  }

  PanelSlider {
    id: slider
    visible: root.type === "i32Range"
    bar: root.bar
    width: parent.width
    minimum: root.range.min
    maximum: root.range.max
    step: root.range.step
    integer: true
    tickCount: root.range.ticks <= 11 ? root.range.ticks : 0
    value: root.value === undefined || root.value === null ? root.range.min : Number(root.value)
    onReleased: function(v) { root.edited(root.snap(v)) }
  }
}
