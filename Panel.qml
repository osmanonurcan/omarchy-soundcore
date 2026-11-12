import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.osmanonurcan.soundcore"
  ipcTarget: "io.github.osmanonurcan.soundcore"

  readonly property string statusScript: Model.localPath(Qt.resolvedUrl("soundcore-status"))
  readonly property string setScript: Model.localPath(Qt.resolvedUrl("soundcore-set"))

  property var status: ({ connected: false })
  property var pendingBands: []
  property var draggingFlags: [false, false, false, false, false, false, false, false]
  readonly property bool anyDragging: draggingFlags.indexOf(true) !== -1

  // Writes not yet confirmed by the device, in the order they're sent.
  // Queued ones wait for the in-flight soundcore-set to finish, then go out
  // together in one call.
  property var queuedWrites: []
  property var inflightWrites: []
  property string writeError: ""
  property bool refreshQueued: false

  // The bands each preset and saved profile sets, as the device reported
  // them, so picking one again moves the sliders without waiting.
  property var knownBands: ({})
  property string knownBandsModel: ""

  // Settings drawn as rows. Reassigned only when the rows change, so a status
  // update doesn't rebuild them under the pointer.
  property var soundRowIds: []
  property var eqRowIds: []
  // The device's other categories, each a section that starts collapsed:
  // [{ id, title, rows }].
  property var sectionList: []
  property var expandedSections: ({})
  property int openPopups: 0

  property bool namingProfile: false
  property bool deleteArmed: false

  readonly property bool connected: !!status.connected
  readonly property bool detailed: !!status.detailed
  readonly property string readError: status.error || ""
  readonly property string errorText: writeError !== ""
    ? "Couldn't change the setting: " + writeError
    : (readError !== "" ? "Couldn't read the headphones' settings: " + readError : "")
  readonly property var schemaList: status.schema || []
  readonly property var values: status.values || {}
  readonly property string deviceName: status.name || "Soundcore"
  readonly property string unrecognized: status.unrecognized || ""
  readonly property string batteryText: Model.batteryText(values)

  readonly property var eqSetting: Model.findSetting(schemaList, "volumeAdjustments")
  readonly property var customSetting: Model.findSetting(schemaList, "customEqualizerProfile")
  readonly property string customValue: values.customEqualizerProfile || ""
  readonly property var profileOptions: Model.profileOptions(customSetting, customValue)

  readonly property bool hasSoundModes: soundRowIds.length > 0
  readonly property bool hasEqualizer: eqRowIds.length > 0 || !!customSetting || !!eqSetting
  readonly property bool hasControls: hasSoundModes || hasEqualizer || sectionList.length > 0

  function settingFor(id) { return Model.findSetting(schemaList, id) }

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
    var parsed = Model.parseStatus(raw)
    if (parsed.detailed && !parsed.error) learnBands(parsed.model, parsed.values)
    var next = Model.mergeStatus(root.status, parsed)
    root.status = Model.withPendingWrites(next, root.inflightWrites, root.queuedWrites)
    syncBands()
  }

  // Only from values the device reported, never from what the panel shows
  // ahead of it.
  function learnBands(model, values) {
    if (model !== root.knownBandsModel) {
      root.knownBands = ({})
      root.knownBandsModel = model || ""
    }
    root.knownBands = Model.learnBands(root.knownBands, values)
  }

  function syncBands() {
    var bands = root.status.values ? root.status.values.volumeAdjustments : null
    if (Array.isArray(bands) && !root.anyDragging) root.pendingBands = bands.slice()
  }

  function syncRows() {
    // Read from `status` itself: the bindings derived from it may not have
    // caught up yet when this runs.
    var schema = root.status.schema || []
    var values = root.status.values || {}
    var sound = Model.rowIds(schema, "soundModes", values)
    if (sound.join("\n") !== root.soundRowIds.join("\n")) root.soundRowIds = sound
    var eq = Model.rowIds(schema, "equalizer", values, ["customEqualizerProfile", "volumeAdjustments"])
    if (eq.join("\n") !== root.eqRowIds.join("\n")) root.eqRowIds = eq
    var sections = Model.sections(schema, values)
    if (JSON.stringify(sections) !== JSON.stringify(root.sectionList)) root.sectionList = sections
  }

  function toggleSection(id) {
    var next = Object.assign({}, root.expandedSections)
    next[id] = !next[id]
    root.expandedSections = next
  }

  onStatusChanged: syncRows()

  // Shows the change right away, then writes it once nothing else is being
  // written, so quick successive changes coalesce instead of being dropped.
  function setSetting(id, value) {
    if (!root.connected || !root.status.mac) return
    var setting = settingFor(id)
    if (!setting || Model.sameValue(root.values[id], value)) return
    enqueue(Model.writeEntry(setting, value, root.knownBands))
  }

  function enqueue(entry) {
    root.queuedWrites = Model.queueWrite(root.queuedWrites, entry)
    root.status = Model.withPendingWrites(root.status, root.inflightWrites, root.queuedWrites)
    syncBands()
    flushWrites()
  }

  function flushWrites() {
    if (setProc.running || root.queuedWrites.length === 0) return
    if (!root.status.mac) {
      root.queuedWrites = []
      return
    }
    root.inflightWrites = root.queuedWrites
    root.queuedWrites = []
    // Read every setting back over the same connection: a write can change
    // others, like a preset changing the bands.
    setProc.command = [root.setScript, root.status.mac]
      .concat(Model.getArgs(Model.readableIds(root.schemaList)))
      .concat(Model.setArgs(root.inflightWrites))
    setProc.running = true
  }

  function finishWrite(exitCode, exitStatus) {
    var ok = exitCode === 0 && exitStatus === 0
    var sent = root.inflightWrites
    var readBack = ok ? Model.parseValues(setOut.text) : null
    root.inflightWrites = []
    root.writeError = ok ? "" : Model.errorMessage(setErr.text, exitCode)
    if (readBack) {
      learnBands(root.status.model, readBack)
      root.status = Model.withPendingWrites(Model.withValues(root.status, readBack), [], root.queuedWrites)
      syncBands()
    }
    if (root.queuedWrites.length > 0) flushWrites()
    // A failed write leaves the panel showing what was asked for, and saving
    // or deleting a profile changes the list; read the device again for both.
    else if (!readBack || Object.keys(readBack).length === 0 || Model.hasCommand(sent)) refreshSoon()
  }

  function startNaming() {
    root.deleteArmed = false
    root.namingProfile = true
    profileName.text = ""
    profileName.forceActiveFocus()
  }

  function stopNaming() {
    root.namingProfile = false
    keyCatcher.forceActiveFocus()
  }

  function saveProfile(text) {
    var name = Model.cleanProfileName(text)
    if (name === "" || !root.connected) return
    stopNaming()
    root.status = Model.withProfileChange(root.status, name, false)
    enqueue(Model.profileCommand(name, false, root.values))
  }

  // Deleting takes a second click, since a saved profile can't be recovered.
  function deleteProfile() {
    var name = root.customValue
    if (name === "" || !root.connected) return
    if (!root.deleteArmed) {
      root.deleteArmed = true
      disarmTimer.restart()
      return
    }
    root.deleteArmed = false
    root.status = Model.withProfileChange(root.status, name, true)
    enqueue(Model.profileCommand(name, true, root.values))
  }

  function notePopup(open) {
    root.openPopups = Math.max(0, root.openPopups + (open ? 1 : -1))
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
    root.namingProfile = false
    root.deleteArmed = false
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
    stdout: StdioCollector { id: setOut; waitForEnd: true }
    stderr: StdioCollector { id: setErr; waitForEnd: true }
    onExited: function(exitCode, exitStatus) { root.finishWrite(exitCode, exitStatus) }
  }

  Timer {
    id: refreshTimer
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: disarmTimer
    interval: 4000
    repeat: false
    onTriggered: root.deleteArmed = false
  }

  // Paused while a slider is held so a status read can't hold the device
  // when the drag's value is written.
  Timer {
    interval: 12000
    running: !root.anyDragging
    repeat: true
    onTriggered: root.refresh()
  }

  Component {
    id: settingRow

    SettingControl {
      id: row
      required property string modelData
      width: parent ? parent.width : 0
      setting: root.settingFor(modelData)
      value: root.values[modelData]
      label: Model.label(modelData)
      bar: root.bar
      onEdited: function(v) { root.setSetting(row.modelData, v) }
      onPopupOpenChanged: root.notePopup(popupOpen)
      Component.onDestruction: if (popupOpen) root.notePopup(false)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋋"
    dimmed: !root.connected
    tooltipText: root.connected ? root.deviceName
      : (root.unrecognized !== "" ? root.unrecognized + ": model not recognized by OpenSCQ30" : "No Soundcore headphones connected")
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Wider by the scroll bar's room when it shows, so the content keeps its
    // width: a row of choices can't shrink to fit.
    contentWidth: panel.fittedContentWidth(Style.space(360) + scrollArea.barRoom)
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Let an open dropdown or the profile name field have the keys.
      blocked: root.openPopups > 0 || profileDropdown.popupOpen || profileName.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        // Shown for as long as there's more to scroll to, not only while
        // scrolling, so it's clear the panel goes on below. It's drawn over
        // the content, so the content keeps clear of it.
        readonly property bool overflows: panelColumn.implicitHeight > height
        readonly property real barRoom: overflows ? ScrollBar.vertical.width + Style.space(8) : 0
        rightPadding: barRoom
        ScrollBar.vertical.policy: overflows ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

        // The scroll area clips at its own edges, and on a fractionally
        // scaled screen that edge rounds to whole pixels; a control's 1px
        // border right on it is cut away or kept depending on where the panel
        // happens to sit. The content keeps a little clear of both edges.
        readonly property real edgeInset: Style.space(2)
        contentWidth: availableWidth

        Column {
          id: panelColumn
          x: scrollArea.edgeInset
          width: scrollArea.availableWidth - 2 * scrollArea.edgeInset
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: root.deviceName
            // The title already names the device; the line under it has room
            // for every battery level, which the detail pill doesn't.
            meta: root.connected ? (root.batteryText || Model.friendlyModel(root.status.model)) : "Disconnected"
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
            text: root.unrecognized !== ""
              ? "“" + root.unrecognized + "” is connected, but OpenSCQ30 doesn't recognize its model, so it can't be controlled here."
              : "Connect your Soundcore headphones over Bluetooth to control them here."
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
            text: "This model doesn't have any settings OpenSCQ30 can change yet."
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
            spacing: Style.space(12)

            Repeater {
              model: root.soundRowIds
              delegate: settingRow
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
            spacing: Style.space(12)

            Repeater {
              model: root.eqRowIds
              delegate: settingRow
            }

            Column {
              visible: !!root.customSetting
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "MY EQ PROFILES"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Dropdown {
                id: profileDropdown
                visible: root.profileOptions.length > 0 && !root.namingProfile
                width: parent.width
                showLabel: false
                options: root.profileOptions
                value: root.customValue
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onChanged: function(v) {
                  if (v !== "") root.setSetting("customEqualizerProfile", v)
                  // Dropdown assigns its own `value` when an option is picked,
                  // which would otherwise break the binding above for good.
                  profileDropdown.value = Qt.binding(function() { return root.customValue })
                }
              }

              Row {
                visible: !root.namingProfile
                spacing: Style.space(8)

                Button {
                  text: "Save current EQ…"
                  bordered: true
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.startNaming()
                }

                Button {
                  visible: root.customValue !== ""
                  text: root.deleteArmed ? "Delete “" + root.customValue + "”?" : "Delete"
                  bordered: true
                  foreground: root.deleteArmed ? root.bar.urgent : root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.deleteProfile()
                }
              }

              Row {
                visible: root.namingProfile
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: profileName
                  width: parent.width - saveButton.width - cancelButton.width - 2 * parent.spacing
                  placeholderText: "Profile name"
                  maximumLength: 64
                  foreground: root.bar.foreground
                  font.family: root.bar.fontFamily
                  onAccepted: root.saveProfile(text)
                  Keys.onEscapePressed: function(event) {
                    root.stopNaming()
                    event.accepted = true
                  }
                }

                Button {
                  id: saveButton
                  text: "Save"
                  bordered: true
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.saveProfile(profileName.text)
                }

                Button {
                  id: cancelButton
                  text: "Cancel"
                  bordered: true
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.stopNaming()
                }
              }
            }

            // Collapsed like the sections below, since its eight bands are
            // most of the panel's height.
            Column {
              id: customEq
              readonly property bool expanded: !!root.expandedSections.customEq
              visible: !!root.eqSetting
              width: parent.width
              spacing: Style.space(10)

              SectionHeader {
                title: "Custom EQ"
                expanded: customEq.expanded
                bar: root.bar
                onToggled: root.toggleSection("customEq")
              }

              Repeater {
                model: root.eqSetting && customEq.expanded ? root.eqSetting.setting.bandHz.length : 0

                Column {
                  id: bandRow
                  required property int index
                  width: panelColumn.width
                  spacing: Style.space(2)

                  readonly property real fd: root.eqSetting.setting.fractionDigits
                  readonly property real stepsPerDb: Math.pow(10, fd)
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
                      text: (bandRow.rawValue / bandRow.stepsPerDb).toFixed(bandRow.fd) + " dB"
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

                    WheelScroll {}
                  }
                }
              }
            }
          }

          // ---------- Other categories ----------
          Repeater {
            model: root.connected ? root.sectionList : []

            Column {
              id: section
              required property var modelData
              readonly property bool expanded: !!root.expandedSections[modelData.id]
              width: panelColumn.width
              spacing: Style.space(12)

              PanelSeparator {
                foreground: root.bar.foreground
              }

              SectionHeader {
                title: section.modelData.title
                expanded: section.expanded
                bar: root.bar
                onToggled: root.toggleSection(section.modelData.id)
              }

              Column {
                visible: section.expanded
                width: parent.width
                spacing: Style.space(12)

                Repeater {
                  model: section.expanded ? section.modelData.rows : []
                  delegate: settingRow
                }
              }
            }
          }
        }
      }
    }
  }
}
