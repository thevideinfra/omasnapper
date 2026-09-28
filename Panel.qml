import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget and panel for videinfra.snapper, styled after dotsync,
// omaudiopanel and tandem: an accent header with a gear, compact sections,
// and a settings view whose choices save as soon as they are picked. The
// snapper work itself is done by bin/snapper-helper.
Panel {
  id: root
  moduleName: "videinfra.snapper"
  ipcTarget: "videinfra.snapper"

  readonly property string helperBin: decodeURIComponent(
    String(Qt.resolvedUrl("bin/snapper-helper")).replace(/^file:\/\//, ""))

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
  property bool settingsOpen: false

  function sp(px) {
    return Style.space(px * densityScale)
  }

  function setSetting(key, value) {
    Quickshell.execDetached(["omarchy", "bar", "set", "videinfra.snapper", key, JSON.stringify(value), "--json"])
  }

  // ---- Snapshots ----
  // Latest `snapper-helper status` document, or null until the first read.
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
  // Which confirm is up in place of the row actions: "restore", "delete" or none.
  property string confirmKind: ""
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
    }
  }

  function close() {
    if (confirmKind !== "") { confirmKind = ""; return }
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
    tooltipText: "Snapper · system snapshots"
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
                text: "Snapper"
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

    Caption {
      width: parent.width
      text: "Restore rolls back the system, not your home folder. The current system is saved as a safety copy first."
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
            textFormat: Text.PlainText
            text: row.snap.title || ""
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: root.fontBody
            font.bold: row.isSelected
            elide: Text.ElideRight
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
            text: Model.shortDate(row.snap.date)
            color: root.barForeground
            opacity: 0.75
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: "#" + row.snap.number
              + (row.snap.size !== null && row.snap.size !== undefined ? " · " + Model.fmtBytes(row.snap.size) : "")
            color: root.barForeground
            opacity: 0.45
            font.family: Style.font.family
            font.pixelSize: root.fontCaption
          }
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

        Row {
          id: actionRow
          visible: !row.isRestoring && root.confirmKind === ""
          x: root.sp(30)
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
              : "Roll the system back to #" + row.snap.number + "? Your password is needed, then a reboot."
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: root.fontSmall
          }

          Row {
            spacing: root.sp(16)

            ActionLink {
              text: root.confirmKind === "delete" ? "󰆴  Delete" : "󰁯  Restore"
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
}
