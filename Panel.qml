import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget and panel for videinfra.omasnapper, styled after dotsync,
// omaudiopanel and tandem: an accent header with a gear, compact sections,
// and a settings view whose choices save as soon as they are picked. The
// snapper work itself is done by bin/omasnapper-helper.
Panel {
  id: root
  moduleName: "videinfra.omasnapper"
  ipcTarget: "videinfra.omasnapper"

  readonly property string helperBin: decodeURIComponent(
    String(Qt.resolvedUrl("bin/omasnapper-helper")).replace(/^file:\/\//, ""))

  // ---- Display settings (shell.json, set from the gear view) ----
  readonly property string density: String(setting("density", "normal"))
  readonly property real densityScale: Model.densityScale(density)
  readonly property string fontSize: String(setting("fontSize", "normal"))
  // Text shrinks half as fast as spacing so compact stays readable, then the
  // font size setting scales it on top. Sized off the title token, as in
  // tandem and dotsync.
  readonly property real fontScale: (0.5 + 0.5 * densityScale) * Model.fontSizeScale(fontSize)
  readonly property real fontTitle: Math.round(Style.font.title * fontScale * 1.1)
  readonly property real fontBody: Math.round(Style.font.title * fontScale)
  readonly property real fontSmall: Math.max(9, Math.round(Style.font.title * fontScale * 0.9))
  readonly property real fontCaption: Math.max(9, Math.round(Style.font.caption * fontScale))
  readonly property real fontDisplay: Math.round(Style.font.display * fontScale)
  readonly property int refreshSec: Math.max(60, Number(setting("refreshIntervalSec", 300)))
  readonly property bool showRetention: Model.settingBool(setting("showRetention", true), true)
  property bool settingsOpen: false
  // Dates follow the bar clock's 12- or 24-hour choice.
  readonly property string clockFmt: Model.clockFormat(bar ? bar.layoutConfig : null)

  function sp(px) {
    return Style.space(px * densityScale)
  }

  function setSetting(key, value) {
    Quickshell.execDetached(["omarchy", "bar", "set", "videinfra.omasnapper", key, JSON.stringify(value), "--json"])
  }

  // ---- Snapshots ----
  // Latest `omasnapper-helper status` document, or null until the first read.
  property var snapData: null
  readonly property var snapshots: snapData ? (snapData.snapshots || []) : []
  // Selected row, as "config:number".
  property string selected: ""
  readonly property var selectedSnap: {
    for (var i = 0; i < snapshots.length; i++)
      if (keyOf(snapshots[i]) === selected) return snapshots[i]
    return null
  }

  // One mutating helper command at a time; `action` names it for the status
  // line and for what to do when it finishes.
  property bool busy: false
  property string action: ""
  property var actionSnap: null
  property string errorText: ""
  property string doneText: ""
  // Which confirm is up in place of the row actions: "restore", "delete",
  // "browse" or none.
  property string confirmKind: ""
  // Row whose description is being edited, as "config:number".
  property string renaming: ""
  // Files changed since a snapshot: which row asked, the first lines, the count.
  property string filesKey: ""
  property var files: []
  property int filesTotal: 0

  // Retention and schedule as saved in snapper, and the choices made in the
  // panel but not applied yet (-1, null and "" mean unchanged).
  readonly property var saved: snapData && snapData.settings ? snapData.settings
    : ({ keep: 5, auto_delete: true, schedule: "off", browse: false })
  property int draftKeep: -1
  property var draftAuto: null
  property string draftSchedule: ""
  readonly property int keepChoice: draftKeep >= 0 ? draftKeep : saved.keep
  readonly property bool autoChoice: draftAuto !== null ? draftAuto : saved.auto_delete
  readonly property string scheduleChoice: draftSchedule !== "" ? draftSchedule : saved.schedule
  readonly property bool retentionDirty: keepChoice !== saved.keep || autoChoice !== saved.auto_delete
    || scheduleChoice !== saved.schedule
  readonly property var retentionDeletes: Model.wouldDelete(snapshots, keepChoice, autoChoice)
  // Set once a restore has worked; the panel then offers the reboot.
  property int restoredNumber: 0

  function keyOf(snap) {
    return snap.config + ":" + snap.number
  }

  readonly property string statusText: {
    if (busy) {
      var doing = {
        create: "Taking snapshot",
        delete: "Deleting #" + (actionSnap ? actionSnap.number : ""),
        restore: "Restoring #" + (actionSnap ? actionSnap.number : ""),
        pin: "Saving",
        rename: "Renaming",
        files: "Comparing #" + (actionSnap ? actionSnap.number : "") + " with now",
        "apply-settings": "Applying retention",
        "allow-browse": "Allowing browsing",
        "quota-enable": "Enabling quotas"
      }
      return (doing[action] || "Working").toUpperCase() + "..."
    }
    if (doneText !== "") return doneText.toUpperCase()
    if (!snapData) return "READING SNAPSHOTS..."
    return Model.statusLine(snapshots.length, snapData.fs ? snapData.fs.free : 0)
  }

  readonly property string pillText: {
    if (!snapData) return errorText !== "" ? "󰁯 !" : "󰁯"
    if (snapData.quota_enabled) {
      var total = Number(snapData.total_exclusive_bytes || 0)
      var warnAt = Number(setting("warnThresholdGB", 5)) * 1024 * 1024 * 1024
      return "󰁯 " + Model.fmtBytes(total) + (total >= warnAt && total > 0 ? " !" : "")
    }
    return "󰁯 " + snapshots.length
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      doneText = ""
      refresh()
    } else {
      settingsOpen = false
      confirmKind = ""
      renaming = ""
    }
  }

  function close() {
    if (confirmKind !== "") { confirmKind = ""; return }
    if (renaming !== "") { renaming = ""; return }
    controller.hide()
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = [root.helperBin, "status"]
    statusProc.running = true
  }

  // Restore and quota-enable need root and go through pkexec; the rest run
  // as the user through snapperd (ALLOW_USERS).
  function run(name, snap, args, asRoot) {
    if (busy) return
    busy = true
    action = name
    actionSnap = snap
    errorText = ""
    doneText = ""
    confirmKind = ""
    runProc.stdoutDone = false
    runProc.exitCode = -1
    runProc.command = (asRoot ? ["pkexec", root.helperBin] : [root.helperBin]).concat(args)
    runProc.running = true
  }

  function createSnapshot() {
    run("create", null, ["create", "Manual snapshot"], false)
  }

  function confirmed() {
    var kind = confirmKind
    var snap = selectedSnap
    if (!snap) return
    if (kind === "delete") run("delete", snap, ["delete", snap.config, String(snap.number)], false)
    else if (kind === "restore") run("restore", snap, ["restore", String(snap.number)], true)
    else if (kind === "browse") run("allow-browse", snap, ["allow-browse"], true)
  }

  function togglePin(snap) {
    run("pin", snap, ["pin", snap.config, String(snap.number), snap.pinned ? "off" : "on"], false)
  }

  function rename(snap, text) {
    var description = text.trim()
    if (description === "" || description === snap.description) { renaming = ""; return }
    run("rename", snap, ["rename", snap.config, String(snap.number), description], false)
  }

  function showFiles(snap) {
    if (filesKey === keyOf(snap)) { filesKey = ""; return }
    run("files", snap, ["files", snap.config, String(snap.number)], false)
  }

  // /.snapshots is root-only until snapper's SYNC_ACL grants ALLOW_USERS
  // read access, so the first open asks for that.
  function openFolder(snap) {
    if (saved.browse) Quickshell.execDetached(["xdg-open", snap.path])
    else confirmKind = "browse"
  }

  function applyRetention() {
    run("apply-settings", null, ["apply-settings", String(keepChoice), autoChoice ? "yes" : "no", scheduleChoice], true)
  }

  function resetRetention() {
    draftKeep = -1
    draftAuto = null
    draftSchedule = ""
  }

  function enableQuotas() {
    run("quota-enable", null, ["quota-enable"], true)
  }

  function finish(stdout, code) {
    busy = false
    if (code !== 0) {
      errorText = Model.helperError(stdout, code)
      refresh()
      return
    }
    if (action === "create") doneText = "Snapshot taken"
    else if (action === "delete") {
      doneText = "Deleted #" + actionSnap.number
      selected = ""
    } else if (action === "restore") {
      restoredNumber = actionSnap.number
      selected = ""
    } else if (action === "quota-enable") doneText = "Quotas on"
    else if (action === "pin") doneText = actionSnap.pinned ? "#" + actionSnap.number + " can be auto-deleted" : "Keeping #" + actionSnap.number
    else if (action === "rename") renaming = ""
    else if (action === "apply-settings") {
      doneText = "Retention saved"
      resetRetention()
    } else if (action === "allow-browse") {
      doneText = "Browsing allowed"
      if (actionSnap) Quickshell.execDetached(["xdg-open", actionSnap.path])
    } else if (action === "files") {
      var doc = JSON.parse(stdout)
      files = doc.files || []
      filesTotal = doc.total || 0
      filesKey = keyOf(actionSnap)
      return
    }
    refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var doc = null
        try { doc = JSON.parse(String(text || "")) } catch (e) { doc = null }
        if (doc && doc.ok) {
          root.snapData = doc
          if (!root.busy && root.errorText.indexOf("Could not read") === 0) root.errorText = ""
        } else if (!root.busy) {
          root.errorText = "Could not read snapshots: " + Model.helperError(String(text || ""), 1)
        }
      }
    }
  }

  Process {
    id: runProc
    property bool stdoutDone: false
    property int exitCode: -1

    // Output and exit arrive separately; finish once both are in.
    function settle() {
      if (stdoutDone && exitCode >= 0) root.finish(stdout.text || "", exitCode)
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { runProc.stdoutDone = true; runProc.settle() }
    }
    onExited: function(code) { exitCode = code; settle() }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    tooltipText: "Omasnapper · system snapshots"
    onPressed: function(b) { if (b === Qt.LeftButton) root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Math.max(root.sp(380), Style.space(260)))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, root.sp(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: if (root.confirmKind !== "") root.confirmed()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: root.sp(12)

          // ---------- Header: icon · title/status · gear ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(headerIcon.implicitHeight, headerLabels.implicitHeight, gearButton.implicitHeight)

            Text {
              id: headerIcon
              textFormat: Text.PlainText
              text: "󰁯"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: root.fontDisplay
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: headerLabels
              anchors.left: headerIcon.right
              anchors.leftMargin: root.sp(14)
              anchors.right: gearButton.left
              anchors.rightMargin: root.sp(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.sp(2)

              Text {
                width: parent.width
                text: "Omasnapper"
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: root.fontTitle
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.statusText
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: root.fontCaption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            Text {
              id: gearButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.settingsOpen ? "󰅖" : "󰒓"
              color: gearMouse.containsMouse || root.settingsOpen ? Color.accent : root.barForeground
              font.family: Style.font.family
              font.pixelSize: Math.round(root.fontTitle * 1.45)
              opacity: gearMouse.containsMouse || root.settingsOpen ? 1.0 : 0.85

              MouseArea {
                id: gearMouse
                anchors.fill: parent
                anchors.margins: -root.sp(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsOpen = !root.settingsOpen
              }

              PanelToolTip {
                visible: gearMouse.containsMouse
                text: root.settingsOpen ? "Close settings" : "Panel settings"
                fontFamily: Style.font.family
              }
            }
          }

          MainView {
            width: parent.width
            visible: !root.settingsOpen
          }

          SettingsView {
            width: parent.width
            visible: root.settingsOpen
          }

          Text {
            width: parent.width
            visible: root.errorText !== ""
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.errorText
            color: root.bar ? root.bar.urgent : Color.urgent
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
          }
        }
      }
    }
  }

  component MainView: Column {
    spacing: root.sp(10)

    // After a restore: the old system keeps running until a reboot.
    CursorSurface {
      width: parent.width
      visible: root.restoredNumber > 0
      bordered: true
      foreground: root.barForeground
      implicitHeight: rebootColumn.implicitHeight + 2 * root.sp(8)

      Column {
        id: rebootColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.sp(8)
        spacing: root.sp(8)

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Restored #" + root.restoredNumber + ". Reboot to start the restored system."
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: root.fontBody
          font.bold: true
        }

        Row {
          spacing: root.sp(16)
          ActionLink {
            text: "󰜉  Reboot now"
            strong: true
            onClicked: Quickshell.execDetached(["systemctl", "reboot"])
          }
          ActionLink {
            text: "Later"
            onClicked: root.restoredNumber = 0
          }
        }
      }
    }

    PanelSeparator { foreground: root.barForeground }
    SectionHeader { text: "SNAPSHOTS" }

    Caption {
      width: parent.width
      visible: root.snapData !== null && root.snapshots.length === 0
      text: "None yet. Take one before a risky change."
    }

    Column {
      width: parent.width
      spacing: root.sp(3)

      Repeater {
        model: root.snapshots

        SnapshotRow {
          required property var modelData
          width: parent.width
          snap: modelData
        }
      }
    }

    PanelSeparator { foreground: root.barForeground }

    ActionLink {
      text: "󰄄  Snapshot now"
      strong: true
      active: !root.busy
      onClicked: root.createSnapshot()
    }

    RetentionView {
      width: parent.width
      visible: root.showRetention
    }

    Caption {
      width: parent.width
      text: "Restore rolls back the system, not your home folder. The current system is saved as a safety copy first."
    }
  }

  // How many snapshots to keep, whether older ones are deleted, and
  // scheduled snapshots. Choices apply together, with one password.
  component RetentionView: Column {
    spacing: root.sp(10)

    PanelSeparator { foreground: root.barForeground }
    SectionHeader { text: "RETENTION" }

    Item {
      width: parent.width
      implicitHeight: Math.max(keepLabel.implicitHeight, keepStepper.implicitHeight)
      opacity: root.autoChoice ? 1.0 : 0.45

      Text {
        id: keepLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Keep the newest"
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: root.fontBody
      }

      Row {
        id: keepStepper
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.sp(12)

        ActionLink {
          text: "−"
          active: root.autoChoice && root.keepChoice > 1
          onClicked: root.draftKeep = root.keepChoice - 1
        }
        Text {
          textFormat: Text.PlainText
          text: String(root.keepChoice)
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: root.fontBody
          font.bold: true
          width: root.sp(24)
          horizontalAlignment: Text.AlignHCenter
        }
        ActionLink {
          text: "+"
          active: root.autoChoice && root.keepChoice < 50
          onClicked: root.draftKeep = root.keepChoice + 1
        }
      }
    }

    SettingSwitch {
      width: parent.width
      label: "Auto-delete older snapshots"
      checked: root.autoChoice
      onToggled: root.draftAuto = !root.autoChoice
    }

    Text {
      textFormat: Text.PlainText
      text: "Scheduled snapshots"
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: root.fontBody
    }

    ChoiceChips {
      width: parent.width
      choices: [
        { value: "off", label: "Off" },
        { value: "daily", label: "Daily" },
        { value: "hourly", label: "Hourly" }
      ]
      selected: root.scheduleChoice
      onPicked: function(value) { root.draftSchedule = value }
    }

    Caption {
      width: parent.width
      text: root.scheduleChoice === "hourly"
        ? "One an hour, kept 12 hours, plus one a day kept 7 days. Pinned and update snapshots are not counted."
        : (root.scheduleChoice === "daily"
          ? "One a day, kept 7 days. Pinned and update snapshots are not counted."
          : "Only update, manual and restore snapshots.")
    }

    Column {
      width: parent.width
      visible: root.retentionDirty
      spacing: root.sp(8)

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.retentionDeletes.length > 0
          ? "Applying deletes " + root.retentionDeletes.map(function(n) { return "#" + n }).join(", ") + " now."
          : "Nothing is deleted now."
        color: root.retentionDeletes.length > 0 ? (root.bar ? root.bar.urgent : Color.urgent) : root.barForeground
        font.family: Style.font.family
        font.pixelSize: root.fontSmall
      }

      Row {
        spacing: root.sp(16)

        ActionLink {
          text: root.retentionDeletes.length > 0 ? "Apply and delete " + root.retentionDeletes.length : "Apply"
          strong: true
          danger: root.retentionDeletes.length > 0
          active: !root.busy
          onClicked: root.applyRetention()
        }
        ActionLink {
          text: "Reset"
          active: !root.busy
          onClicked: root.resetRetention()
        }
      }

      Caption {
        width: parent.width
        text: "Needs your password. The boot menu grows to fit, so every kept snapshot stays restorable."
      }
    }
  }

  component SettingsView: Column {
    spacing: root.sp(10)

    PanelSeparator { foreground: root.barForeground }

    Text {
      textFormat: Text.PlainText
      text: "󰁍 Back"
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: root.fontSmall
      font.bold: true
      opacity: backMouse.containsMouse ? 1.0 : 0.75

      MouseArea {
        id: backMouse
        anchors.fill: parent
        anchors.margins: -root.sp(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.settingsOpen = false
      }
    }

    SectionHeader { text: "DENSITY" }

    ChoiceChips {
      width: parent.width
      choices: [
        { value: "compact", label: "Compact" },
        { value: "normal", label: "Normal" },
        { value: "comfortable", label: "Comfortable" }
      ]
      selected: root.density
      onPicked: function(value) { root.setSetting("density", value) }
    }

    SectionHeader { text: "FONT SIZE" }

    ChoiceChips {
      width: parent.width
      choices: [
        { value: "small", label: "Small" },
        { value: "normal", label: "Normal" },
        { value: "large", label: "Large" }
      ]
      selected: root.fontSize
      onPicked: function(value) { root.setSetting("fontSize", value) }
    }

    PanelSeparator { foreground: root.barForeground }
    SectionHeader { text: "SHOW" }

    SettingSwitch {
      width: parent.width
      label: "Retention section"
      checked: root.showRetention
      onToggled: root.setSetting("showRetention", !root.showRetention)
    }

    PanelSeparator { foreground: root.barForeground }
    SectionHeader { text: "SNAPSHOT FOLDERS" }

    Caption {
      width: parent.width
      text: root.saved.browse
        ? "Your user can read snapshot folders. Open one from its row with Folder."
        : "Snapshot folders under /.snapshots are root-only. Allowing browsing lets your user read them."
    }

    ActionLink {
      visible: !root.saved.browse
      text: "󰉋  Allow browsing"
      active: !root.busy
      onClicked: root.run("allow-browse", null, ["allow-browse"], true)
    }

    PanelSeparator { foreground: root.barForeground }
    SectionHeader { text: "SNAPSHOT SIZES" }

    Caption {
      width: parent.width
      text: root.snapData && root.snapData.quota_enabled
        ? "Btrfs quotas are on. Each row shows the space only that snapshot holds."
        : "Sizes need btrfs quotas. They add a small, constant cost to disk writes."
    }

    ActionLink {
      visible: !(root.snapData && root.snapData.quota_enabled)
      text: "󰋊  Enable quotas"
      active: !root.busy
      onClicked: root.enableQuotas()
    }
  }

  component SectionHeader: PanelSectionHeader {
    foreground: root.barForeground
    fontFamily: Style.font.family
    fontSize: root.fontCaption
  }

  component Caption: Text {
    color: root.barForeground
    opacity: 0.45
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: root.fontSmall
  }

  // A snapshot in the list: why it was made, when, and its size. Click to
  // select it; the selected row shows Restore and Delete, and their confirm
  // replaces them in place.
  component SnapshotRow: CursorSurface {
    id: row
    property var snap: ({})
    readonly property bool isSelected: root.selected === root.keyOf(snap)
    readonly property bool isRenaming: root.renaming === root.keyOf(snap)
    readonly property bool isRestoring: root.busy && root.action === "restore"
      && root.actionSnap && root.keyOf(root.actionSnap) === root.keyOf(snap)

    hasCursor: rowMouse.containsMouse
    current: isSelected
    foreground: root.barForeground
    implicitHeight: rowColumn.implicitHeight + root.sp(12)

    Rectangle {
      visible: row.isSelected
      anchors.left: parent.left
      anchors.leftMargin: root.sp(2)
      anchors.top: parent.top
      anchors.topMargin: root.sp(8)
      width: Math.max(2, root.sp(3))
      height: rowTop.height - root.sp(4)
      radius: width / 2
      color: Color.accent
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.confirmKind = ""
        root.selected = row.isSelected ? "" : root.keyOf(row.snap)
      }
    }

    Column {
      id: rowColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: root.sp(6)
      anchors.leftMargin: root.sp(6)
      anchors.rightMargin: root.sp(6)
      spacing: root.sp(8)

      Row {
        id: rowTop
        width: parent.width
        spacing: root.sp(8)

        Text {
          textFormat: Text.PlainText
          text: Model.originIcon(row.snap.origin)
          color: row.isSelected ? Color.accent : root.barForeground
          font.family: Style.font.family
          font.pixelSize: root.fontTitle
          width: root.sp(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - root.sp(22) - rowSide.width - 2 * root.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.sp(2)

          Text {
            width: parent.width
            visible: !row.isRenaming
            textFormat: Text.PlainText
            text: row.snap.title || ""
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: root.fontBody
            font.bold: row.isSelected
            elide: Text.ElideRight
          }

          TextField {
            id: renameField
            width: parent.width
            visible: row.isRenaming
            foreground: root.barForeground
            font.family: Style.font.family
            font.pixelSize: root.fontBody
            verticalPadding: root.sp(3)
            onAccepted: root.rename(row.snap, text)
            onVisibleChanged: if (visible) {
              text = row.snap.description || ""
              forceActiveFocus()
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: row.snap.detail || ""
            color: root.barForeground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
            elide: Text.ElideRight
          }
        }

        Column {
          id: rowSide
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.sp(2)

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: Model.shortDate(row.snap.date, root.clockFmt)
            color: root.barForeground
            opacity: 0.75
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: (row.snap.pinned ? "󰐃 " : "") + "#" + row.snap.number
              + (row.snap.size !== null && row.snap.size !== undefined ? " · " + Model.fmtBytes(row.snap.size) : "")
            color: root.barForeground
            opacity: 0.45
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
          }
        }
      }

      // What the update behind this snapshot changed, which is what a
      // restore undoes. Long lists stop at ten lines.
      Column {
        visible: row.isSelected && (row.snap.changes || []).length > 0
        x: root.sp(30)
        width: parent.width - x
        spacing: root.sp(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "That update changed:"
          color: root.barForeground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: root.fontCaption
          font.bold: true
        }

        Repeater {
          model: (row.snap.changes || []).slice(0, 10)

          Text {
            required property var modelData
            width: parent.width
            textFormat: Text.PlainText
            text: Model.changeLine(modelData)
            color: root.barForeground
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
            elide: Text.ElideRight
          }
        }

        Text {
          visible: (row.snap.changes || []).length > 10
          textFormat: Text.PlainText
          text: "and " + ((row.snap.changes || []).length - 10) + " more"
          color: root.barForeground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: root.fontCaption
        }
      }

      // Files that differ between this snapshot and now.
      Column {
        visible: root.filesKey === root.keyOf(row.snap)
        x: root.sp(30)
        width: parent.width - x
        spacing: root.sp(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.filesTotal === 0 ? "No files changed since this snapshot."
            : root.filesTotal + (root.filesTotal === 1 ? " file differs" : " files differ") + " from now:"
          color: root.barForeground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: root.fontCaption
          font.bold: true
        }

        Repeater {
          model: root.filesKey === root.keyOf(row.snap) ? root.files.slice(0, 30) : []

          Text {
            required property var modelData
            width: parent.width
            textFormat: Text.PlainText
            text: Model.fileLine(modelData)
            color: root.barForeground
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
            elide: Text.ElideMiddle
          }
        }

        Text {
          visible: root.filesTotal > 30
          textFormat: Text.PlainText
          text: "and " + (root.filesTotal - 30) + " more"
          color: root.barForeground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: root.fontCaption
        }
      }

      // Actions, or the confirm that replaces them.
      Item {
        width: parent.width
        visible: row.isSelected || row.isRestoring
        implicitHeight: row.isRestoring ? restoringText.implicitHeight
          : (root.confirmKind === "" ? actionRow.implicitHeight : confirmColumn.implicitHeight)

        Text {
          id: restoringText
          visible: row.isRestoring
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Restoring… this can take a minute."
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: root.fontSmall
        }

        Flow {
          id: actionRow
          visible: !row.isRestoring && root.confirmKind === ""
          x: root.sp(30)
          width: parent.width - x
          spacing: root.sp(16)

          ActionLink {
            text: "󰁯  Restore"
            strong: true
            active: !root.busy
            onClicked: root.confirmKind = "restore"
          }
          ActionLink {
            text: "󰆴  Delete"
            danger: true
            active: !root.busy
            onClicked: root.confirmKind = "delete"
          }
          ActionLink {
            text: row.snap.pinned ? "󰐄  Unpin" : "󰐃  Pin"
            active: !root.busy
            onClicked: root.togglePin(row.snap)
          }
          ActionLink {
            text: "󰏫  Rename"
            active: !root.busy
            onClicked: root.renaming = row.isRenaming ? "" : root.keyOf(row.snap)
          }
          ActionLink {
            text: "󰈔  Files"
            active: !root.busy
            onClicked: root.showFiles(row.snap)
          }
          ActionLink {
            text: "󰉋  Folder"
            active: !root.busy
            onClicked: root.openFolder(row.snap)
          }
        }

        Column {
          id: confirmColumn
          visible: !row.isRestoring && root.confirmKind !== ""
          x: root.sp(30)
          width: parent.width - x
          spacing: root.sp(8)

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.confirmKind === "delete"
              ? "Delete snapshot #" + row.snap.number + "? This cannot be undone."
              : (root.confirmKind === "browse"
                ? "Snapshot folders are root-only. Let your user read them? Needs your password once."
                : "Roll the system back to #" + row.snap.number + "? Your password is needed, then a reboot.")
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: root.fontSmall
          }

          Row {
            spacing: root.sp(16)

            ActionLink {
              text: root.confirmKind === "delete" ? "󰆴  Delete"
                : (root.confirmKind === "browse" ? "󰉋  Allow and open" : "󰁯  Restore")
              strong: true
              danger: root.confirmKind === "delete"
              onClicked: root.confirmed()
            }
            ActionLink {
              text: "Cancel"
              onClicked: root.confirmKind = ""
            }
          }
        }
      }
    }
  }

  // A text action: accent when strong or under the pointer, dim while busy.
  // A danger action uses the urgent colour instead.
  component ActionLink: Text {
    id: link
    property bool strong: false
    property bool danger: false
    property bool active: true
    signal clicked()

    textFormat: Text.PlainText
    color: !link.active ? root.barForeground
      : (link.danger
        ? (link.strong || linkMouse.containsMouse ? (root.bar ? root.bar.urgent : Color.urgent) : root.barForeground)
        : (link.strong || linkMouse.containsMouse ? Color.accent : root.barForeground))
    opacity: !link.active ? 0.4 : (linkMouse.containsMouse ? 1.0 : 0.85)
    font.family: Style.font.family
    font.pixelSize: root.fontBody
    font.bold: link.strong

    MouseArea {
      id: linkMouse
      anchors.fill: parent
      anchors.margins: -root.sp(4)
      enabled: link.active
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
  }

  // A wrapping row of text choices; the selected one is accent, bold and
  // underlined. choices: [{ value, label }].
  component ChoiceChips: Flow {
    id: chips
    property var choices: []
    property var selected
    signal picked(var value)

    spacing: root.sp(10)

    Repeater {
      model: chips.choices

      Text {
        required property var modelData
        readonly property bool chosen: chips.selected === modelData.value
        textFormat: Text.PlainText
        text: modelData.label
        color: chosen ? Color.accent : root.barForeground
        font.family: Style.font.family
        font.pixelSize: root.fontSmall
        font.bold: chosen
        font.underline: chosen
        opacity: chosen || chipMouse.containsMouse ? 1.0 : 0.55

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          anchors.margins: -root.sp(3)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: chips.picked(parent.modelData.value)
        }
      }
    }
  }

  // A labelled on/off switch row; the whole row takes the click.
  component SettingSwitch: Item {
    id: settingRow
    property string label: ""
    property bool checked: false
    signal toggled()

    implicitHeight: Math.max(settingLabel.implicitHeight, settingToggle.implicitHeight)

    Text {
      id: settingLabel
      anchors.left: parent.left
      anchors.right: settingToggle.left
      anchors.rightMargin: root.sp(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: settingRow.label
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: root.fontBody
      elide: Text.ElideRight
    }

    AccentSwitch {
      id: settingToggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: settingRow.checked
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: settingRow.toggled()
    }
  }

  // On/off switch in the theme accent: accent track and knob when on, a dim
  // neutral track when off. Presentation only; its row owns the click.
  component AccentSwitch: Item {
    id: sw
    property bool checked: false

    implicitWidth: root.sp(34)
    implicitHeight: root.sp(18)

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: sw.checked ? Util.alpha(Color.accent, 0.3) : Util.alpha(root.barForeground, 0.1)
      border.width: 1
      border.color: sw.checked ? Color.accent : Util.alpha(root.barForeground, 0.25)
      Behavior on color { ColorAnimation { duration: 120 } }

      Rectangle {
        width: parent.height - root.sp(6)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - root.sp(3) : root.sp(3)
        color: sw.checked ? Color.accent : Qt.darker(root.barForeground, 1.4)
        Behavior on x { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }
  }
}
