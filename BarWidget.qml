import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "SnapperUtil.js" as SG

BarWidget {
    id: root
    moduleName: "videinfra.snapper"

    // Injected by the shell: every key of this widget's shell.json entry.
    property var settings

    // Shared state: latest `snapper-helper status` document (or null while loading).
    property var snapData: null
    property string statusError: ""

    // Absolute path of the privileged helper; forwarded to the panel.
    readonly property string helperPath: {
        var u = String(Qt.resolvedUrl("bin/snapper-helper"));
        return u.replace(/^file:\/\//, "");
    }

    // ---- shell panel contract (Bar.findPanelWidget needs open/close/opened) ----
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function open() { if (panelLoader.item) panelLoader.item.open(); }
    function close() { if (panelLoader.item) panelLoader.item.close(); }
    function toggle() { if (panelLoader.item) panelLoader.item.toggle(); }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch(); }

    function injectPanel() {
        var target = panelLoader.item;
        if (!target) return;
        target.bar = root.bar;
        target.anchorItem = button;
        target.hostWidget = root;
        if ("settings" in target) target.settings = root.settings;
        if ("helperPath" in target) target.helperPath = root.helperPath;
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    onBarChanged: root.injectPanel()
    onSettingsChanged: root.injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    // ---- status polling (unprivileged: snapper ALLOW_USERS covers this user) ----
    Process {
        id: statusProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.onStatusOutput(String(text || ""))
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0 && !root.snapData) {
                root.statusError = "helper exited with code " + exitCode;
            }
        }
    }

    function onStatusOutput(text) {
        try {
            var doc = JSON.parse(text);
            if (doc && doc.ok) {
                root.snapData = doc;
                root.statusError = "";
            } else {
                root.statusError = (doc && doc.error) ? String(doc.error) : "helper error";
            }
        } catch (e) {
            root.statusError = "could not parse helper output";
        }
    }

    function refreshStatus() {
        if (statusProc.running) return;
        statusProc.command = [root.helperPath, "status"];
        statusProc.running = true;
    }

    Timer {
        interval: Math.max(60, Number(root.setting("refreshIntervalSec", 300))) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStatus()
    }

    // ---- the bar pill ----
    readonly property string pillText: {
        if (!root.snapData) return root.statusError ? "󰁯 !" : "󰁯 …";
        var snaps = root.snapData.snapshots || [];
        var showSizes = root.setting("showSizes", true) !== false;
        if (showSizes && root.snapData.quota_enabled) {
            var total = Number(root.snapData.total_exclusive_bytes || 0);
            var warnAt = Number(root.setting("warnThresholdGB", 5)) * 1000 * 1000 * 1000;
            var warn = total >= warnAt && total > 0;
            return "󰁯 " + SG.fmtBytes(total) + (warn ? " !" : "");
        }
        return "󰁯 " + snaps.length;
    }

    readonly property string pillTooltip: {
        if (!root.snapData) return root.statusError ? ("Snapshots: " + root.statusError) : "Snapshots: loading…";
        var snaps = root.snapData.snapshots || [];
        var tip = snaps.length + (snaps.length === 1 ? " snapshot" : " snapshots");
        if (root.snapData.quota_enabled) {
            tip += " · " + SG.fmtBytes(root.snapData.total_exclusive_bytes || 0) + " exclusive";
        } else {
            tip += " · quotas off, sizes unavailable";
        }
        return tip + " — click to manage";
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.pillText
        tooltipText: root.pillTooltip
        onPressed: function (buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggle();
        }
    }
}
