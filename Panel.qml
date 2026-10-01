import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget and panel for videinfra.omasnapper, in tandem's panel style:
// a header with the version and repository link, icon section labels, boxed
// choices and steppers, card rows, and tinted banners for pending changes
// and errors. Like omaudiopanel it keeps a gear for its settings view, whose
// choices save as soon as they are picked. The snapper work itself is done
// by bin/omasnapper-helper.
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
  readonly property bool askName: Model.settingBool(setting("askName", true), true)
  // True while the name field for a new snapshot is up.
  property bool naming: false
  signal namingStarted()
  property bool settingsOpen: false
  // Dates follow the bar clock's 12- or 24-hour choice.
  readonly property string clockFmt: Model.clockFormat(bar ? bar.layoutConfig : null)

  function sp(px) {
    return Style.space(px * densityScale)
  }

  // The bar foreground at a given opacity, for card fills and outlines.
  function tint(alpha) {
    return Util.alpha(root.barForeground, alpha)
  }

  // Text on an accent fill: black or white by the accent's luminance, so it
  // stays readable whatever the theme's accent is.
  readonly property color onAccent: {
    var c = Color.accent
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.5 ? "#101014" : "#ffffff"
  }
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent

  readonly property string repoUrl: "https://github.com/thevideinfra/omasnapper"
  // Shown in the header's pill; read from manifest.json so it cannot drift.
  property string version: ""

  FileView {
    path: decodeURIComponent(String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, ""))
    onLoaded: {
      try { root.version = JSON.parse(text()).version || "" } catch (e) { root.version = "" }
    }
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
      naming = false
    }
  }

  function close() {
    if (confirmKind !== "") { confirmKind = ""; return }
    if (renaming !== "") { renaming = ""; return }
    if (naming) { naming = false; return }
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

  // With askName on, the first click asks for a name and the field's Enter
  // or Take snapshot creates it.
  function createSnapshot() {
    if (askName && !naming) {
      naming = true
      namingStarted()
      return
    }
    run("create", null, ["create", Model.snapshotName(draftName)], false)
    naming = false
  }

  property string draftName: ""

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

  // Opens a folder from settings; asks for read access first if needed.
  function openPath(path) {
    if (saved.browse) Quickshell.execDetached(["xdg-open", path])
    else run("allow-browse", { path: path }, ["allow-browse"], true)
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, root.sp(860))

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
          spacing: root.sp(10)

          // ---------- Header: icon · title, version, repo / status · gear ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(headerIcon.implicitHeight, headerLabels.implicitHeight)

            Text {
              id: headerIcon
              textFormat: Text.PlainText
              text: "󰁯"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Math.round(root.fontDisplay * 1.2)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: headerLabels
              anchors.left: headerIcon.right
              anchors.leftMargin: root.sp(12)
              anchors.right: gearButton.left
              anchors.rightMargin: root.sp(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.sp(2)

              // The name on the left; the version and the repository link on
              // the right of the same line, as in tandem.
              Item {
                width: parent.width
                implicitHeight: Math.max(titleText.implicitHeight, versionRow.implicitHeight)

                Text {
                  id: titleText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Omasnapper"
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: root.fontTitle
                  font.bold: true
                }

                Row {
                  id: versionRow
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.sp(7)

                  Rectangle {
                    visible: root.version !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: versionText.implicitWidth + root.sp(10)
                    height: versionText.implicitHeight + root.sp(4)
                    radius: height / 2
                    color: Util.alpha(Color.accent, 0.15)
                    border.width: 1
                    border.color: Util.alpha(Color.accent, 0.45)

                    Text {
                      id: versionText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "v" + root.version
                      color: Color.accent
                      font.family: Style.font.family
                      font.pixelSize: root.fontCaption
                      font.bold: true
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: ""
                    color: repoMouse.containsMouse ? Color.accent : root.barForeground
                    opacity: repoMouse.containsMouse ? 1.0 : 0.6
                    font.family: Style.font.family
                    font.pixelSize: root.fontBody

                    MouseArea {
                      id: repoMouse
                      anchors.fill: parent
                      anchors.margins: -root.sp(4)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        Quickshell.execDetached(["xdg-open", root.repoUrl])
                        root.close()
                      }
                    }

                    PanelToolTip {
                      visible: repoMouse.containsMouse
                      text: "Open on GitHub"
                      fontFamily: Style.font.family
                    }
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.statusText
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: root.fontCaption
                font.bold: true
                font.letterSpacing: 0.6
                elide: Text.ElideRight
              }
            }

            // Opens the settings view in place of the panel content.
            Rectangle {
              id: gearButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: root.sp(28)
              height: root.sp(28)
              radius: root.sp(6)
              color: gearMouse.containsMouse || root.settingsOpen ? Util.alpha(Color.accent, 0.15) : "transparent"
              border.width: root.settingsOpen ? 1 : 0
              border.color: Util.alpha(Color.accent, 0.45)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.settingsOpen ? "󰅖" : "󰒓"
                color: gearMouse.containsMouse || root.settingsOpen ? Color.accent : root.barForeground
                font.family: Style.font.family
                font.pixelSize: Math.round(root.fontTitle * 1.2)
              }

              MouseArea {
                id: gearMouse
                anchors.fill: parent
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

          PanelSeparator { foreground: root.barForeground }

          MainView {
            width: parent.width
            visible: !root.settingsOpen
          }

          SettingsView {
            width: parent.width
            visible: root.settingsOpen
          }

          Banner {
            width: parent.width
            visible: root.errorText !== ""
            danger: true

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: root.errorText
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: root.fontSmall
            }
          }
        }
      }
    }
  }

  // ===================== views =====================

  component MainView: Column {
    spacing: root.sp(10)

    // After a restore: the old system keeps running until a reboot.
    Banner {
      width: parent.width
      visible: root.restoredNumber > 0

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "Restored #" + root.restoredNumber + ". Reboot to start the restored system."
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: root.fontSmall
        font.bold: true
      }

      Row {
        spacing: root.sp(8)
        SmallButton {
          text: "󰜉  Reboot now"
          kind: "primary"
          onClicked: Quickshell.execDetached(["systemctl", "reboot"])
        }
        SmallButton {
          text: "Later"
          onClicked: root.restoredNumber = 0
        }
      }
    }

    SectionLabel { icon: ""; text: "SNAPSHOTS" }

    Caption {
      width: parent.width
      visible: root.snapData !== null && root.snapshots.length === 0
      text: "None yet. Take one before a risky change."
    }

    Column {
      width: parent.width
      spacing: root.sp(5)

      Repeater {
        model: root.snapshots

        SnapshotRow {
          required property var modelData
          width: parent.width
          snap: modelData
        }
      }
    }

    SmallButton {
      visible: !root.naming
      text: "󰄄  Snapshot now"
      kind: "primary"
      active: !root.busy
      onClicked: root.createSnapshot()
    }

    Column {
      width: parent.width
      visible: root.naming
      spacing: root.sp(8)

      TextField {
        id: nameField
        width: parent.width
        placeholderText: "Name, e.g. before kernel swap"
        foreground: root.barForeground
        font.family: Style.font.family
        font.pixelSize: root.fontBody
        verticalPadding: root.sp(5)
        onTextChanged: root.draftName = text
        onAccepted: root.createSnapshot()

        Connections {
          target: root
          function onNamingStarted() {
            nameField.text = ""
            nameField.forceActiveFocus()
          }
        }
      }

      Row {
        spacing: root.sp(8)

        SmallButton {
          text: "󰄄  Take snapshot"
          kind: "primary"
          active: !root.busy
          onClicked: root.createSnapshot()
        }
        SmallButton {
          text: "Cancel"
          onClicked: root.naming = false
        }
      }

      Caption {
        width: parent.width
        text: "Blank uses \"Manual snapshot\"."
      }
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
    spacing: root.sp(9)

    PanelSeparator { foreground: root.barForeground }
    SectionLabel { icon: ""; text: "RETENTION"; tag: "NEEDS PASSWORD" }

    Item {
      width: parent.width
      implicitHeight: Math.max(keepLabel.implicitHeight, keepStepper.implicitHeight)

      Text {
        id: keepLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Keep the newest"
        color: root.barForeground
        opacity: root.autoChoice ? 1.0 : 0.45
        font.family: Style.font.family
        font.pixelSize: root.fontBody
      }

      Row {
        id: keepStepper
        anchors.right: parent.right
        spacing: root.sp(8)

        StepButton {
          iconText: ""
          tooltipText: "Keep one fewer"
          active: root.autoChoice && root.keepChoice > 1
          onClicked: if (active) root.draftKeep = root.keepChoice - 1
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.sp(24)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: String(root.keepChoice)
          color: Color.accent
          opacity: root.autoChoice ? 1.0 : 0.45
          font.family: Style.font.family
          font.pixelSize: root.fontTitle
          font.bold: true
        }

        StepButton {
          iconText: ""
          tooltipText: "Keep one more"
          active: root.autoChoice && root.keepChoice < 50
          onClicked: if (active) root.draftKeep = root.keepChoice + 1
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

    Segmented {
      width: parent.width
      columns: 3
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

    // Pending changes, in tandem's banner: what applying does, then the
    // buttons. Red when it deletes snapshots.
    Banner {
      width: parent.width
      visible: root.retentionDirty
      danger: root.retentionDeletes.length > 0

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.retentionDeletes.length > 0
          ? "Applying deletes " + root.retentionDeletes.map(function(n) { return "#" + n }).join(", ") + " now."
          : "Nothing is deleted now."
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: root.fontSmall
        font.bold: true
      }

      Caption {
        width: parent.width
        text: "The boot menu grows to fit every kept snapshot."
      }

      Item {
        width: parent.width
        implicitHeight: applyRow.implicitHeight

        Row {
          id: applyRow
          anchors.right: parent.right
          spacing: root.sp(8)

          SmallButton {
            text: "Reset"
            active: !root.busy
            onClicked: root.resetRetention()
          }
          SmallButton {
            text: root.retentionDeletes.length > 0 ? "Apply & delete " + root.retentionDeletes.length : "Apply"
            kind: root.retentionDeletes.length > 0 ? "danger-fill" : "primary"
            active: !root.busy
            onClicked: root.applyRetention()
          }
        }
      }
    }
  }

  // Replaces the main view while the gear is on. Everything here saves as
  // soon as it is picked.
  component SettingsView: Column {
    spacing: root.sp(9)

    SectionLabel { icon: ""; text: "DENSITY" }

    Segmented {
      width: parent.width
      columns: 3
      choices: [
        { value: "compact", label: "Compact" },
        { value: "normal", label: "Normal" },
        { value: "roomy", label: "Roomy" }
      ]
      selected: root.density === "comfortable" ? "roomy" : root.density
      onPicked: function(value) { root.setSetting("density", value) }
    }

    SectionLabel { icon: ""; text: "FONT SIZE" }

    Segmented {
      width: parent.width
      columns: 3
      choices: [
        { value: "small", label: "Small" },
        { value: "normal", label: "Normal" },
        { value: "large", label: "Large" }
      ]
      selected: root.fontSize
      onPicked: function(value) { root.setSetting("fontSize", value) }
    }

    PanelSeparator { foreground: root.barForeground }
    SectionLabel { icon: ""; text: "SHOW" }

    SettingSwitch {
      width: parent.width
      label: "Retention section"
      checked: root.showRetention
      onToggled: root.setSetting("showRetention", !root.showRetention)
    }

    SettingSwitch {
      width: parent.width
      label: "Name snapshots before taking them"
      checked: root.askName
      onToggled: root.setSetting("askName", !root.askName)
    }

    PanelSeparator { foreground: root.barForeground }
    SectionLabel { icon: "\uf07c"; text: "LOCATION"; tag: root.saved.browse ? "" : "OPEN NEEDS PASSWORD" }

    // Where each snapper config keeps its snapshots. Every snapshot is a
    // read-only copy of the system at <folder>/<number>/snapshot.
    Repeater {
      model: root.snapData ? (root.snapData.locations || []) : []

      Rectangle {
        id: locationCard
        required property var modelData
        width: parent.width
        implicitHeight: locationColumn.implicitHeight + root.sp(14)
        radius: root.sp(7)
        color: root.tint(0.05)
        border.width: 1
        border.color: root.tint(0.1)

        Column {
          id: locationColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: root.sp(7)
          spacing: root.sp(6)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: locationCard.modelData.path
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: root.fontBody
            font.bold: true
            elide: Text.ElideMiddle
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Snapshots of " + locationCard.modelData.subvolume + " (snapper config \"" + locationCard.modelData.config
              + "\"). Each one is a read-only copy at " + locationCard.modelData.path + "/<number>/snapshot."
            color: root.barForeground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
          }

          Row {
            spacing: root.sp(6)

            SmallButton {
              text: root.saved.browse ? "󰉋  Open" : "󰉋  Allow and open"
              kind: "accent"
              active: !root.busy
              onClicked: root.openPath(locationCard.modelData.path)
            }
            SmallButton {
              text: "󰆏  Copy path"
              onClicked: {
                Quickshell.execDetached(["wl-copy", locationCard.modelData.path])
                root.doneText = "Copied " + locationCard.modelData.path
              }
            }
          }
        }
      }
    }

    Caption {
      width: parent.width
      visible: !root.saved.browse
      text: "The folder is root-only until you allow your user to read it."
    }

    PanelSeparator { foreground: root.barForeground }
    SectionLabel {
      icon: ""
      text: "SNAPSHOT SIZES"
      tag: root.snapData && root.snapData.quota_enabled ? "" : "NEEDS PASSWORD"
    }

    Caption {
      width: parent.width
      text: root.snapData && root.snapData.quota_enabled
        ? "Btrfs quotas are on. Each row shows the space only that snapshot holds."
        : "Sizes need btrfs quotas. They add a small, constant cost to disk writes."
    }

    SmallButton {
      visible: !(root.snapData && root.snapData.quota_enabled)
      text: "󰋊  Enable quotas"
      active: !root.busy
      onClicked: root.enableQuotas()
    }
  }

  // ===================== pieces =====================

  // A snapshot as a card: why it was made, when, and its size. Click to
  // select it; the selected card lists what its update changed and shows
  // the actions, whose confirm replaces them in place.
  component SnapshotRow: Rectangle {
    id: row
    property var snap: ({})
    readonly property bool isSelected: root.selected === root.keyOf(snap)
    readonly property bool isRenaming: root.renaming === root.keyOf(snap)
    readonly property bool isRestoring: root.busy && root.action === "restore"
      && root.actionSnap && root.keyOf(root.actionSnap) === root.keyOf(snap)

    implicitHeight: rowColumn.implicitHeight + root.sp(14)
    radius: root.sp(7)
    color: isSelected ? Util.alpha(Color.accent, 0.12) : (rowMouse.containsMouse ? root.tint(0.08) : root.tint(0.05))
    border.width: 1
    border.color: isSelected ? Util.alpha(Color.accent, 0.45) : root.tint(0.1)

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
      anchors.margins: root.sp(7)
      spacing: root.sp(8)

      Row {
        id: rowTop
        width: parent.width
        spacing: root.sp(8)

        // The origin icon in a chip, like tandem's desktop number.
        Rectangle {
          width: root.sp(28)
          height: root.sp(28)
          anchors.verticalCenter: parent.verticalCenter
          radius: root.sp(6)
          color: root.tint(0.08)
          border.width: 1
          border.color: row.isSelected ? Color.accent : root.tint(0.18)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: Model.originIcon(row.snap.origin)
            color: row.isSelected ? Color.accent : root.barForeground
            font.family: Style.font.family
            font.pixelSize: root.fontBody
          }
        }

        Column {
          width: parent.width - root.sp(28) - rowSide.width - 2 * root.sp(8)
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
            color: row.snap.pinned ? Color.accent : root.barForeground
            opacity: row.snap.pinned ? 0.9 : 0.45
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
          }
        }
      }

      // What the update behind this snapshot changed, which is what a
      // restore undoes. Long lists stop at ten lines.
      DetailList {
        visible: row.isSelected && (row.snap.changes || []).length > 0
        heading: "That update changed:"
        lines: (row.snap.changes || []).map(function(c) { return Model.changeLine(c) })
        total: (row.snap.changes || []).length
        shown: 10
      }

      // Files that differ between this snapshot and now.
      DetailList {
        visible: root.filesKey === root.keyOf(row.snap)
        heading: root.filesTotal === 0 ? "No files changed since this snapshot."
          : root.filesTotal + (root.filesTotal === 1 ? " file differs" : " files differ") + " from now:"
        lines: root.filesKey === root.keyOf(row.snap) ? root.files.map(function(f) { return Model.fileLine(f) }) : []
        total: root.filesTotal
        shown: 30
        elideMiddle: true
      }

      Text {
        visible: row.isRestoring
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "Restoring… this can take a minute."
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: root.fontSmall
        font.bold: true
      }

      Flow {
        visible: row.isSelected && !row.isRestoring && root.confirmKind === ""
        width: parent.width
        spacing: root.sp(6)

        SmallButton {
          text: "󰁯  Restore"
          kind: "accent"
          active: !root.busy
          onClicked: root.confirmKind = "restore"
        }
        SmallButton {
          text: "󰆴  Delete"
          kind: "danger"
          active: !root.busy
          onClicked: root.confirmKind = "delete"
        }
        SmallButton {
          text: row.snap.pinned ? "󰐄  Unpin" : "󰐃  Pin"
          active: !root.busy
          onClicked: root.togglePin(row.snap)
        }
        SmallButton {
          text: "󰏫  Rename"
          active: !root.busy
          onClicked: root.renaming = row.isRenaming ? "" : root.keyOf(row.snap)
        }
        SmallButton {
          text: "󰈔  Files"
          active: !root.busy
          onClicked: root.showFiles(row.snap)
        }
        SmallButton {
          text: "󰉋  Folder"
          active: !root.busy
          onClicked: root.openFolder(row.snap)
        }
      }

      Column {
        visible: row.isSelected && !row.isRestoring && root.confirmKind !== ""
        width: parent.width
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
          spacing: root.sp(8)

          SmallButton {
            text: root.confirmKind === "delete" ? "󰆴  Delete"
              : (root.confirmKind === "browse" ? "󰉋  Allow and open" : "󰁯  Restore")
            kind: root.confirmKind === "delete" ? "danger-fill" : "primary"
            onClicked: root.confirmed()
          }
          SmallButton {
            text: "Cancel"
            onClicked: root.confirmKind = ""
          }
        }
      }
    }
  }

  // A heading and up to `shown` lines, then "and N more".
  component DetailList: Column {
    id: list
    property string heading: ""
    property var lines: []
    property int total: 0
    property int shown: 10
    property bool elideMiddle: false

    width: parent ? parent.width : implicitWidth
    spacing: root.sp(2)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: list.heading
      color: root.barForeground
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: root.fontCaption
      font.bold: true
    }

    Repeater {
      model: list.lines.slice(0, list.shown)

      Text {
        required property var modelData
        width: list.width
        textFormat: Text.PlainText
        text: modelData
        color: root.barForeground
        opacity: 0.8
        font.family: Style.font.family
        font.pixelSize: root.fontCaption
        elide: list.elideMiddle ? Text.ElideMiddle : Text.ElideRight
      }
    }

    Text {
      visible: list.total > list.shown
      textFormat: Text.PlainText
      text: "and " + (list.total - list.shown) + " more"
      color: root.barForeground
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: root.fontCaption
    }
  }

  // Icon, uppercase title, and an optional tag on the right (tandem's).
  component SectionLabel: Item {
    id: section
    property string icon: ""
    property string text: ""
    property string tag: ""

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(sectionTitle.implicitHeight, sectionIcon.implicitHeight)

    Text {
      id: sectionIcon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: root.sp(20)
      textFormat: Text.PlainText
      text: section.icon
      color: root.barForeground
      opacity: 0.65
      font.family: Style.font.family
      font.pixelSize: root.fontBody
    }

    Text {
      id: sectionTitle
      anchors.left: sectionIcon.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: section.text
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: root.fontSmall
      font.bold: true
      font.letterSpacing: 1.2
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: section.tag
      color: root.barForeground
      opacity: 0.4
      font.family: Style.font.family
      font.pixelSize: root.fontCaption
      font.letterSpacing: 0.8
    }
  }

  component Caption: Text {
    color: root.barForeground
    opacity: 0.45
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: root.fontCaption
  }

  // Tinted box for pending changes, results and errors: accent, or urgent
  // when `danger`. Children stack in a padded column.
  component Banner: Rectangle {
    id: banner
    property bool danger: false
    default property alias content: bannerColumn.data

    implicitHeight: bannerColumn.implicitHeight + root.sp(16)
    radius: root.sp(7)
    color: Util.alpha(danger ? root.urgent : Color.accent, 0.12)
    border.width: 1
    border.color: Util.alpha(danger ? root.urgent : Color.accent, 0.4)

    Column {
      id: bannerColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: root.sp(8)
      spacing: root.sp(8)
    }
  }

  // Boxed text button, in tandem's shapes. kind: "plain" (outlined),
  // "accent" or "danger" (outlined in that colour), "primary" or
  // "danger-fill" (filled).
  component SmallButton: Rectangle {
    id: btn
    property string text: ""
    property string kind: "plain"
    property bool active: true
    signal clicked()

    readonly property bool filled: kind === "primary" || kind === "danger-fill"
    readonly property color hue: kind === "danger" || kind === "danger-fill" ? root.urgent : Color.accent
    readonly property bool hot: btnMouse.containsMouse && active

    implicitWidth: btnText.implicitWidth + root.sp(18)
    implicitHeight: btnText.implicitHeight + root.sp(10)
    radius: root.sp(6)
    opacity: active ? 1.0 : 0.4
    color: filled ? (hot ? Qt.lighter(hue, 1.1) : hue)
      : (hot ? Util.alpha(kind === "plain" ? Color.accent : hue, 0.18) : root.tint(0.05))
    border.width: filled ? 0 : 1
    border.color: hot || kind !== "plain" ? Util.alpha(kind === "plain" ? Color.accent : hue, hot ? 1.0 : 0.6) : root.tint(0.25)

    Text {
      id: btnText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: btn.text
      color: btn.filled ? root.onAccent : (btn.kind === "plain" ? (btn.hot ? Color.accent : root.barForeground) : btn.hue)
      font.family: Style.font.family
      font.pixelSize: root.fontSmall
      font.bold: btn.filled || btn.kind !== "plain"
    }

    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.active
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  // Boxed -/+ for the keep count; accent under the pointer, dim at the limit.
  component StepButton: Rectangle {
    id: step
    property string iconText: ""
    property string tooltipText: ""
    property bool active: true
    signal clicked()

    implicitWidth: root.sp(26)
    implicitHeight: root.sp(26)
    radius: root.sp(7)
    color: stepMouse.containsMouse && step.active ? Util.alpha(Color.accent, 0.2) : root.tint(0.06)
    border.width: 1
    border.color: stepMouse.containsMouse && step.active ? Color.accent : root.tint(0.25)
    opacity: step.active ? 1.0 : 0.4

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: step.iconText
      color: stepMouse.containsMouse && step.active ? Color.accent : root.barForeground
      font.family: Style.font.family
      font.pixelSize: root.fontSmall
    }

    MouseArea {
      id: stepMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: step.active ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: step.clicked()
    }

    PanelToolTip {
      visible: stepMouse.containsMouse
      text: step.tooltipText
      fontFamily: Style.font.family
    }
  }

  // Boxed choices in an even grid; the chosen one is outlined and tinted in
  // the accent (tandem's). choices: [{ value, label }].
  component Segmented: Grid {
    id: segmented
    property var choices: []
    property var selected
    signal picked(var value)

    spacing: root.sp(6)
    readonly property real cellWidth: (width - (columns - 1) * spacing) / columns

    Repeater {
      model: segmented.choices

      Rectangle {
        id: choice
        required property var modelData
        readonly property bool chosen: segmented.selected === modelData.value
        width: segmented.cellWidth
        implicitHeight: choiceText.implicitHeight + root.sp(12)
        radius: root.sp(7)
        color: chosen ? Util.alpha(Color.accent, 0.12) : (choiceMouse.containsMouse ? root.tint(0.09) : root.tint(0.05))
        border.width: chosen ? 2 : 1
        border.color: chosen ? Color.accent : root.tint(0.12)

        Text {
          id: choiceText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: choice.modelData.label
          color: choice.chosen ? Color.accent : root.barForeground
          font.family: Style.font.family
          font.pixelSize: root.fontSmall
          font.bold: choice.chosen
        }

        MouseArea {
          id: choiceMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: segmented.picked(choice.modelData.value)
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
