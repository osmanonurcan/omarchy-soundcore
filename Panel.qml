import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.s-w-3.soundcore"
  ipcTarget: "io.github.s-w-3.soundcore"

  readonly property string statusScript: Model.localPath(Qt.resolvedUrl("soundcore-status"))
  readonly property string setScript: Model.localPath(Qt.resolvedUrl("soundcore-set"))

  property var status: ({ connected: false })
  property var pendingBands: []
  property var draggingFlags: [false, false, false, false, false, false, false, false]
  readonly property bool anyDragging: draggingFlags.indexOf(true) !== -1

  // Writes not yet confirmed by a status read, by setting id. Queued ones
  // wait for the in-flight soundcore-set to finish, then go out together.
  property var queuedWrites: ({})
  property var inflightWrites: ({})
  property string writeError: ""
  property bool refreshQueued: false

  readonly property bool connected: !!status.connected
  readonly property bool detailed: !!status.detailed
  readonly property string readError: status.error || ""
  readonly property string errorText: writeError !== ""
    ? "Couldn't change the setting: " + writeError
    : (readError !== "" ? "Couldn't read the headphones' settings: " + readError : "")
  readonly property var schemaList: status.schema || []
  readonly property var values: status.values || {}
  readonly property string deviceName: status.name || "Soundcore"
  readonly property string batteryText: Model.batteryText(values)

  function categorySettings(catId) {
    for (var i = 0; i < schemaList.length; i++)
      if (schemaList[i].categoryId === catId) return schemaList[i].settings || []
    return []
  }

  function findSetting(catId, settingId) {
    var list = categorySettings(catId)
    for (var i = 0; i < list.length; i++)
      if (list[i].settingId === settingId) return list[i]
    return null
  }

  readonly property var ambientSetting: findSetting("soundModes", "ambientSoundMode")
  readonly property var ancSetting: findSetting("soundModes", "noiseCancelingMode")
  readonly property var presetSetting: findSetting("equalizer", "presetEqualizerProfile")
  readonly property var eqSetting: findSetting("equalizer", "volumeAdjustments")

  readonly property string ambientValue: values.ambientSoundMode || ""
  readonly property string ancValue: values.noiseCancelingMode || ""
  readonly property string presetValue: values.presetEqualizerProfile || ""

  readonly property bool hasSoundModes: !!ambientSetting
  readonly property bool hasEqualizer: !!eqSetting
  readonly property bool hasControls: hasSoundModes || hasEqualizer

  function ambientOptions() { return Model.buildOptions(ambientSetting) }
  function ancOptions() { return Model.buildOptions(ancSetting) }
  function presetOptions() { return Model.presetOptions(presetSetting, presetValue) }

  function refresh() {
    if (statusProc.running) {
      root.refreshQueued = true
      return
    }
    // Reading settings means connecting to the headphones, and openscq30
    // allows one connection at a time. While the panel is closed the bar icon
    // only needs to know whether they're connected, so don't hold the device.
    statusProc.command = root.opened ? [root.statusScript] : [root.statusScript, "--quick"]
    statusProc.running = true
  }

  function refreshSoon() {
    refreshTimer.restart()
  }

  function updateStatus(raw) {
    var next = Model.mergeStatus(root.status, Model.parseStatus(raw))
    root.status = Model.withPendingWrites(next, root.inflightWrites, root.queuedWrites)
    var bands = root.status.values ? root.status.values.volumeAdjustments : null
    if (Array.isArray(bands) && !root.anyDragging) root.pendingBands = bands.slice()
  }

  // Shows the change right away, then writes it once nothing else is being
  // written, so quick successive changes coalesce instead of being dropped.
  function setSetting(id, value) {
    if (!root.connected || !root.status.mac) return
    if (Model.sameValue(root.values[id], value)) return
    var queued = Object.assign({}, root.queuedWrites)
    queued[id] = value
    root.queuedWrites = queued
    root.status = Model.withPendingWrites(root.status, root.inflightWrites, root.queuedWrites)
    flushWrites()
  }

  function flushWrites() {
    if (setProc.running) return
    var args = Model.setArgs(root.queuedWrites)
    if (args.length === 0) return
    if (!root.status.mac) {
      root.queuedWrites = ({})
      return
    }
    root.inflightWrites = root.queuedWrites
    root.queuedWrites = ({})
    setProc.command = [root.setScript, root.status.mac].concat(args)
    setProc.running = true
  }

  function finishWrite(exitCode, exitStatus) {
    root.writeError = exitCode === 0 && exitStatus === 0 ? "" : Model.errorMessage(setErr.text, exitCode)
    root.inflightWrites = ({})
    if (Model.setArgs(root.queuedWrites).length > 0) root.flushWrites()
    else root.refreshSoon()
  }

  function setDragging(index, dragging) {
    var next = draggingFlags.slice()
    next[index] = dragging
    draggingFlags = next
  }

  function bandValue(index) {
    return root.pendingBands.length > index ? root.pendingBands[index] : 0
  }

  function moveBand(index, rawValue) {
    var next = root.pendingBands.slice()
    next[index] = rawValue
    root.pendingBands = next
  }

  function commitBands() {
    setSetting("volumeAdjustments", root.pendingBands.slice())
  }

  onOpenedChanged: {
    if (!opened) return
    root.writeError = ""
    refresh()
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateStatus(text) }
    onExited: {
      if (!root.refreshQueued) return
      root.refreshQueued = false
      root.refresh()
    }
  }

  Process {
    id: setProc
    stderr: StdioCollector { id: setErr; waitForEnd: true }
    onExited: function(exitCode, exitStatus) { root.finishWrite(exitCode, exitStatus) }
  }

  Timer {
    id: refreshTimer
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  // Paused while a slider is held so a status read can't hold the device
  // when the drag's value is written.
  Timer {
    interval: 12000
    running: !root.anyDragging
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋋"
    dimmed: !root.connected
    tooltipText: root.connected ? root.deviceName : "No Soundcore headphones connected"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: root.deviceName
            meta: root.connected ? Model.friendlyModel(root.status.model) : "Disconnected"
            detail: root.batteryText
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰋋"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
                opacity: root.connected ? 1.0 : 0.4
              }
            }
          }

          Text {
            visible: !root.connected
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Connect your Soundcore headphones over Bluetooth to control them here."
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.connected && root.errorText !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.errorText
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.connected && !root.detailed && root.readError === ""
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Reading settings from your headphones…"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.connected && root.detailed && !root.hasControls && root.readError === ""
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "This model doesn't have sound mode or equalizer controls in OpenSCQ30 yet."
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---------- Sound mode ----------
          PanelSeparator {
            visible: root.connected && root.hasSoundModes
            foreground: root.bar.foreground
          }

          Column {
            visible: root.connected && root.hasSoundModes
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "SOUND MODE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            ButtonGroup {
              width: parent.width
              options: root.ambientOptions()
              value: root.ambientValue
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onChanged: function(v) { root.setSetting("ambientSoundMode", v) }
            }

            Column {
              visible: !!root.ancSetting && root.ambientValue === "NoiseCanceling"
              width: parent.width
              spacing: Style.space(6)
              topPadding: Style.space(6)

              PanelSectionHeader {
                text: "NOISE CANCELING"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              ButtonGroup {
                width: parent.width
                options: root.ancOptions()
                value: root.ancValue
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) { root.setSetting("noiseCancelingMode", v) }
              }
            }
          }

          // ---------- Equalizer ----------
          PanelSeparator {
            visible: root.connected && root.hasEqualizer
            foreground: root.bar.foreground
          }

          Column {
            visible: root.connected && root.hasEqualizer
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "EQUALIZER PRESET"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Dropdown {
              id: presetDropdown
              width: parent.width
              showLabel: false
              options: root.presetOptions()
              value: root.presetValue
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onChanged: function(v) {
                root.setSetting("presetEqualizerProfile", v)
                // Dropdown assigns its own `value` when an option is picked,
                // which would otherwise break the binding above for good.
                presetDropdown.value = Qt.binding(function() { return root.presetValue })
              }
            }

            PanelSectionHeader {
              text: "CUSTOM EQ"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              topPadding: Style.space(6)
            }

            Repeater {
              model: root.eqSetting ? root.eqSetting.setting.bandHz.length : 0

              Column {
                id: bandRow
                required property int index
                width: panelColumn.width
                spacing: Style.space(2)

                readonly property real fd: root.eqSetting.setting.fractionDigits
                readonly property real scale: Math.pow(10, fd)
                readonly property real rawValue: root.bandValue(index)

                Row {
                  width: parent.width

                  Text {
                    textFormat: Text.PlainText
                    text: Model.formatBandLabel(root.eqSetting.setting.bandHz[bandRow.index])
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    width: parent.width - dbLabel.implicitWidth
                  }

                  Text {
                    id: dbLabel
                    textFormat: Text.PlainText
                    text: (bandRow.rawValue / bandRow.scale).toFixed(bandRow.fd) + " dB"
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                PanelSlider {
                  bar: root.bar
                  width: parent.width
                  minimum: root.eqSetting.setting.min
                  maximum: root.eqSetting.setting.max
                  step: 1
                  integer: true
                  value: bandRow.rawValue

                  onMoved: function(v) { root.moveBand(bandRow.index, v) }
                  onDraggingChanged: root.setDragging(bandRow.index, dragging)
                  onReleased: function(v) {
                    root.moveBand(bandRow.index, v)
                    root.commitBands()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
