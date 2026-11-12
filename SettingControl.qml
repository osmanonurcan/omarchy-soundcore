import QtQuick
import qs.Ui
import qs.Commons
import "Model.js" as Model

// One device setting, drawn by its openscq30 type: a row of choices or a
// dropdown for a select, a switch for a toggle, a stepped slider for a range
// or a hue, a line of text for information, a button for an action, and a
// list for the devices headphones with dual connections remember.
Column {
  id: root

  property var setting: null
  property var value
  property string label: ""
  property QtObject bar: null
  // This computer's Bluetooth address, to tell it apart in a device list.
  property string adapter: ""
  readonly property bool popupOpen: dropdown.popupOpen

  // The user picked `value`.
  signal edited(var value)
  // The user asked the headphones to forget the device at `mac`.
  signal forget(string mac)

  readonly property string type: setting ? setting.type : ""
  readonly property var options: Model.selectOptions(setting, value)
  readonly property bool isSelect: type === "select" || type === "optionalSelect" || type === "modifiableSelect"
  readonly property bool asButtons: type === "select" && options.length <= 3
  readonly property var range: Model.rangeOf(setting)
  readonly property bool oneLine: type === "toggle" || type === "information" || type === "action"
  readonly property bool isRange: type === "i32Range" || type === "hueColorPicker"
  readonly property real liveSnapped: root.snap(slider.liveValue)

  // An action can't be undone, so it takes a second click; so does
  // forgetting a device, the one at `armedMac`.
  property bool armed: false
  property string armedMac: ""

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

    Rectangle {
      visible: root.type === "hueColorPicker"
      anchors.right: rangeValue.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: header.verticalCenter
      width: Style.space(12)
      height: width
      radius: width / 2
      color: Qt.hsva(root.liveSnapped / 360, 1, 1, 1)
    }

    Text {
      id: rangeValue
      visible: root.isRange
      anchors.right: parent.right
      anchors.verticalCenter: header.verticalCenter
      textFormat: Text.PlainText
      text: Model.rangeText(root.setting ? root.setting.settingId : "", root.liveSnapped)
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
    onTriggered: {
      root.armed = false
      root.armedMac = ""
    }
  }

  Column {
    visible: root.type === "multiSelectWithRemove"
    width: parent.width
    spacing: Style.space(8)

    Text {
      visible: deviceList.count === 0
      textFormat: Text.PlainText
      text: "None"
      color: Qt.darker(root.bar.foreground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      id: deviceList
      model: root.type === "multiSelectWithRemove" ? Model.devices(root.setting, root.value, root.adapter) : []

      Item {
        id: device
        required property var modelData
        readonly property bool armed: root.armedMac === modelData.mac
        width: parent.width
        implicitHeight: Math.max(deviceText.implicitHeight, forgetButton.implicitHeight)

        Column {
          id: deviceText
          anchors.left: parent.left
          anchors.right: forgetButton.visible ? forgetButton.left : parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: device.modelData.name
            elide: Text.ElideRight
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            visible: text !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: device.modelData.thisComputer
              ? (device.modelData.connected ? "This computer · connected" : "This computer")
              : (device.modelData.connected ? "Connected" : "")
            elide: Text.ElideRight
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Forgetting this computer would drop the connection the panel
        // talks through.
        Button {
          id: forgetButton
          visible: !device.modelData.thisComputer
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: device.armed ? "Forget?" : "Forget"
          bordered: true
          foreground: device.armed ? root.bar.urgent : root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: {
            if (!device.armed) {
              root.armedMac = device.modelData.mac
              disarm.restart()
              return
            }
            root.armedMac = ""
            root.forget(device.modelData.mac)
          }
        }
      }
    }
  }

  PanelSlider {
    id: slider
    visible: root.isRange
    bar: root.bar
    width: parent.width
    minimum: root.range.min
    maximum: root.range.max
    step: root.range.step
    integer: true
    tickCount: root.range.ticks <= 11 ? root.range.ticks : 0
    // A hue's knob takes the color picked; the strip below shows the rest.
    knobColor: root.type === "hueColorPicker" ? Qt.hsva(root.liveSnapped / 360, 1, 1, 1) : root.bar.foreground
    fillColor: root.type === "hueColorPicker" ? trackColor : root.bar.foreground
    value: root.value === undefined || root.value === null ? root.range.min : Number(root.value)
    onReleased: function(v) { root.edited(root.snap(v)) }

    WheelScroll {}
  }

  // The hues along the slider, under its track.
  Rectangle {
    visible: root.type === "hueColorPicker"
    x: slider.knobSize / 2
    width: parent.width - slider.knobSize
    height: Style.space(4)
    radius: height / 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0 / 6; color: Qt.hsva(0 / 6, 1, 1, 1) }
      GradientStop { position: 1 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) }
      GradientStop { position: 2 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
      GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) }
      GradientStop { position: 4 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) }
      GradientStop { position: 5 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) }
      GradientStop { position: 1; color: Qt.hsva(359 / 360, 1, 1, 1) }
    }
  }
}
