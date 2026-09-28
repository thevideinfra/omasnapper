import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "SnapperUtil.js" as SG

Panel {
    id: root
    moduleName: "videinfra.snapper"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property var settings
    property string helperPath: ""

    property var snapData: null
    property string statusError: ""
    property bool busy: false

    // ---- panel contract (called by the bar widget) ----
    readonly property bool popoutSwitchClosing: false
    function open() { root.controller.show(); }
    function close() { root.controller.hide(); }
    function toggle() { if (root.opened) root.close(); else root.open(); }
    function closeForPopoutSwitch() { root.close(); }
    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction);
        return false;
    }

    onOpenedChanged: {
        if (root.opened) root.refreshStatus();
    }

    // ---- helpers ----
    function notify(title, body) {
        Util.execArgv(["omarchy-notification-send", "-g", "󰁯",
                       "--app-name", root.moduleName, title, body]);
    }

    function runHelper(args, onDone) {
        var proc = helperProcComponent.createObject(root, {
            "onDone": onDone || function (doc) {}
        });
        proc.command = ["pkexec", root.helperPath].concat(args);
        proc.running = true;
    }

    Component {
        id: helperProcComponent
        Process {
            property var onDone
            stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: {
                    var doc = null;
                    try { doc = JSON.parse(String(text || "")); } catch (e) { doc = null; }
                    parent.onDone(doc);
                }
            }
            onExited: function (exitCode, exitStatus) {
                if (exitCode !== 0) parent.onDone(null);
                root.busy = false;
                root.refreshStatus();
                parent.destroy();
            }
        }
    }

    function refreshStatus() {
        root.busy = true;
        root.runHelper(["status"], function (doc) {
            root.busy = false;
            if (doc && doc.ok) {
                root.snapData = doc;
                root.statusError = "";
            } else {
                root.statusError = (doc && doc.error) ? String(doc.error) : "helper failed";
            }
        });
    }

    function createSnapshot() {
        var d = new Date();
        var pad = function (n) { return (n < 10 ? "0" : "") + n; };
        var desc = "manual " + d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
                 + " " + pad(d.getHours()) + ":" + pad(d.getMinutes());
        root.busy = true;
        root.runHelper(["create", desc], function (doc) {
            if (doc && doc.ok) root.notify("Snapshot created", desc);
            else root.notify("Snapshot failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        });
    }

    function deleteSnapshot(num) {
        root.busy = true;
        root.runHelper(["delete", String(num)], function (doc) {
            if (doc && doc.ok) root.notify("Snapshot deleted", "Snapshot #" + num);
            else root.notify("Delete failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        });
    }

    function runCleanup() {
        root.busy = true;
        root.runHelper(["cleanup"], function (doc) {
            if (doc && doc.ok) root.notify("Cleanup done", "Number-based retention applied.");
            else root.notify("Cleanup failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        });
    }

    function enableQuotas() {
        root.busy = true;
        root.runHelper(["quota-enable"], function (doc) {
            if (doc && doc.ok) root.notify("Quotas enabled", "Per-snapshot sizes are now available.");
            else root.notify("Quota enable failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        });
    }

    function restoreInTerminal() {
        // Whole-system restore is interactive by design: hand off to
        // Omarchy's own limine-snapper-restore in a terminal.
        Util.execArgv(["foot", "--title", "Snapshot restore", "sh", "-c",
            "sudo limine-snapper-restore; echo; printf '%s' 'Press Enter to close...'; read _"]);
        root.close();
    }

    // ---- popup surface ----
    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(440))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function (d) { root.switchPanel(d); }

            Column {
                id: content
                width: parent.width
                spacing: Style.space(8)

                PanelSectionHeader { text: "Snapshots" }

                // Summary line
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font: Style.font.bodySmall
                    color: Util.alpha(Color.foreground, 0.75)
                    text: root.summaryText
                }

                // Quota warning
                Column {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.snapData && !root.snapData.quota_enabled
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font: Style.font.bodySmall
                        color: Color.urgent
                        text: "Btrfs quotas are off, so per-snapshot sizes are unavailable."
                    }
                    Button {
                        text: "Enable quotas"
                        enabled: !root.busy
                        onClicked: root.enableQuotas()
                    }
                }

                // Actions
                Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Button {
                        text: "Snapshot now"
                        enabled: !root.busy
                        onClicked: root.createSnapshot()
                    }
                    Button {
                        text: "Clean up"
                        enabled: !root.busy
                        onClicked: root.runCleanup()
                    }
                    Button {
                        text: "Refresh"
                        enabled: !root.busy
                        onClicked: root.refreshStatus()
                    }
                }

                PanelSeparator {}

                // Loading / error / empty states
                Text {
                    width: parent.width
                    visible: !root.snapData && !root.statusError
                    textFormat: Text.PlainText
                    font: Style.font.body
                    color: Util.alpha(Color.foreground, 0.6)
                    text: "Loading snapshots…"
                }
                Column {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: !!root.statusError
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font: Style.font.body
                        color: Color.urgent
                        text: "Could not read snapshots: " + root.statusError
                    }
                    Button {
                        text: "Retry"
                        onClicked: root.refreshStatus()
                    }
                }
                Text {
                    width: parent.width
                    visible: root.snapData && (root.snapData.snapshots || []).length === 0 && !root.statusError
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font: Style.font.body
                    color: Util.alpha(Color.foreground, 0.6)
                    text: "No snapshots yet. Take one before your next risky change."
                }

                // Snapshot list
                ListView {
                    id: snapList
                    width: parent.width
                    height: Math.max(64, Math.min((root.snapData ? (root.snapData.snapshots || []).length : 0), 8) * 64)
                    visible: root.snapData && (root.snapData.snapshots || []).length > 0
                    clip: true
                    model: root.snapData ? (root.snapData.snapshots || []) : []
                    delegate: Rectangle {
                        id: row
                        width: snapList.width
                        height: 64
                        color: "transparent"
                        property bool delConfirm: false
                        property bool resConfirm: false

                        Timer {
                            id: confirmTimer
                            interval: 4000
                            onTriggered: { row.delConfirm = false; row.resConfirm = false; }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Style.space(4)
                            anchors.rightMargin: Style.space(4)
                            spacing: Style.space(8)

                            Text {
                                width: Style.space(44)
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                font: Style.font.body
                                color: Color.accent
                                text: "#" + modelData.number
                            }

                            Column {
                                width: parent.width - Style.space(44) - sizeText.width - delBtn.width - resBtn.width - 4 * Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    font: Style.font.body
                                    color: Color.foreground
                                    text: modelData.description || "(no description)"
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    font: Style.font.caption
                                    color: Util.alpha(Color.foreground, 0.55)
                                    text: SG.typeLabel(modelData.type) + " · " + modelData.date + " · " + modelData.config
                                           + (modelData.cleanup ? " · cleanup: " + modelData.cleanup : "")
                                }
                            }

                            Text {
                                id: sizeText
                                width: Style.space(64)
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                font: Style.font.bodySmall
                                color: Util.alpha(Color.foreground, 0.75)
                                text: (root.snapData && root.snapData.quota_enabled && root.snapData.sizes
                                       && root.snapData.sizes[String(modelData.number)] !== undefined)
                                      ? SG.fmtBytes(root.snapData.sizes[String(modelData.number)]) : "—"
                            }

                            Button {
                                id: resBtn
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.resConfirm ? "Reboot?" : "Restore"
                                onClicked: {
                                    if (!row.resConfirm) {
                                        row.delConfirm = false;
                                        row.resConfirm = true;
                                        confirmTimer.restart();
                                    } else {
                                        row.resConfirm = false;
                                        root.restoreInTerminal();
                                    }
                                }
                            }

                            Button {
                                id: delBtn
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.delConfirm ? "Sure?" : "Delete"
                                enabled: !root.busy
                                onClicked: {
                                    var needConfirm = root.setting("confirmDelete", true) !== false;
                                    if (needConfirm && !row.delConfirm) {
                                        row.resConfirm = false;
                                        row.delConfirm = true;
                                        confirmTimer.restart();
                                    } else {
                                        row.delConfirm = false;
                                        root.deleteSnapshot(modelData.number);
                                    }
                                }
                            }
                        }
                    }
                }

                PanelSeparator {}

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font: Style.font.caption
                    color: Util.alpha(Color.foreground, 0.5)
                    text: "Snapshots appear as entries in the Limine boot menu (limine-snapper-sync). "
                        + "Restore reboots into Omarchy's restore tool; /home is preserved. "
                        + "Snapshots live on this disk — they are an undo button, not a backup."
                }
            }
        }
    }

    readonly property string summaryText: {
        if (!root.snapData) return root.statusError ? "" : "Loading…";
        var snaps = root.snapData.snapshots || [];
        var s = snaps.length + (snaps.length === 1 ? " snapshot" : " snapshots");
        if (root.snapData.quota_enabled) {
            s += " · " + SG.fmtBytes(root.snapData.total_exclusive_bytes || 0) + " exclusive";
        }
        if (root.snapData.fs) {
            var pct = Math.round(100 * root.snapData.fs.used / Math.max(1, root.snapData.fs.total));
            s += " · disk " + pct + "% used";
        }
        return s;
    }
}
