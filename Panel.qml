import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "SnapperUtil.js" as SG

Panel {
    id: root
    moduleName: "videinfra.snapper"
    ipcTarget: "videinfra.snapper"

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

    function runHelper(args, onDone, asRoot) {
        var proc = helperProcComponent.createObject(root, {
            "onDone": onDone || function (doc) {}
        });
        proc.command = (asRoot ? ["pkexec", root.helperPath] : [root.helperPath]).concat(args);
        proc.running = true;
    }

    // Mutations refresh both the panel and the bar pill when they finish.
    function runAction(args, onDone, asRoot) {
        root.busy = true;
        root.runHelper(args, function (doc) {
            root.busy = false;
            onDone(doc);
            root.refreshStatus();
            if (root.hostWidget && typeof root.hostWidget.refreshStatus === "function")
                root.hostWidget.refreshStatus();
        }, asRoot);
    }

    Component {
        id: helperProcComponent
        Process {
            property var onDone
            id: helperProc
            stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: {
                    var doc = null;
                    try { doc = JSON.parse(String(text || "")); } catch (e) { doc = null; }
                    helperProc.onDone(doc);
                }
            }
            onExited: function (exitCode, exitStatus) {
                // stdout carries {"ok": false, ...} on failure, so onDone
                // already ran from the collector; only clean up here.
                helperProc.destroy();
            }
        }
    }

    function refreshStatus() {
        root.runHelper(["status"], function (doc) {
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
        root.runAction(["create", desc], function (doc) {
            if (doc && doc.ok) root.notify("Snapshot created", desc);
            else root.notify("Snapshot failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        });
    }

    function deleteSnapshot(config, num) {
        root.runAction(["delete", String(config), String(num)], function (doc) {
            if (doc && doc.ok) root.notify("Snapshot deleted", "Snapshot #" + num);
            else root.notify("Delete failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        });
    }

    function runCleanup() {
        root.runAction(["cleanup"], function (doc) {
            if (doc && doc.ok) root.notify("Cleanup done", "Number-based retention applied.");
            else root.notify("Cleanup failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        });
    }

    function enableQuotas() {
        root.runAction(["quota-enable"], function (doc) {
            if (doc && doc.ok) root.notify("Quotas enabled", "Per-snapshot sizes are now available.");
            else root.notify("Quota enable failed", (doc && doc.error) ? String(doc.error) : "helper failed");
        }, true);
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
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
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
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
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
                        text: "Restore…"
                        tooltipText: "Opens Omarchy's snapshot restore tool in a terminal"
                        onClicked: root.restoreInTerminal()
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
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
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
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
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
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
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

                        Timer {
                            id: confirmTimer
                            interval: 4000
                            onTriggered: row.delConfirm = false
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
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                                color: Color.accent
                                text: "#" + modelData.number
                            }

                            Column {
                                width: parent.width - Style.space(44) - sizeText.width - delBtn.width - 3 * Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.body
                                    color: Color.foreground
                                    text: modelData.description || "(no description)"
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
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
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                                color: Util.alpha(Color.foreground, 0.75)
                                text: modelData.size !== null && modelData.size !== undefined
                                      ? SG.fmtBytes(modelData.size) : "—"
                            }

                            Button {
                                id: delBtn
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.delConfirm ? "Sure?" : "Delete"
                                enabled: !root.busy
                                onClicked: {
                                    var needConfirm = root.setting("confirmDelete", true) !== false;
                                    if (needConfirm && !row.delConfirm) {
                                                                                row.delConfirm = true;
                                        confirmTimer.restart();
                                    } else {
                                        row.delConfirm = false;
                                        root.deleteSnapshot(modelData.config, modelData.number);
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
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Util.alpha(Color.foreground, 0.5)
                    text: "Snapshots appear as entries in the Limine boot menu (limine-snapper-sync). "
                        + "Restore… runs Omarchy's restore tool in a terminal; /home is preserved. "
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
