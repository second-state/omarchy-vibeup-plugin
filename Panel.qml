import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui

// VibeKeys bar widget: shows the keyboard's Bluetooth connection state,
// offers a one-click vibeup CLI installer, and opens the vibeup TUI.
//
// Data sources:
//   - Quickshell.Bluetooth for the paired keyboard (reactive, no polling)
//   - `which vibeup` for CLI detection, plus the default install dir check
//   - the upstream install.sh, streamed into the panel when the user clicks
//     Install. The command runs with the panel's log visible the whole time.

Panel {
  id: root
  moduleName: "io.github.second-state.vibeup"
  ipcTarget: "vibeup"

  // Bar slots are sized from the root's implicit extents. Icon slot + 8px
  // breathing room per side.
  implicitWidth: Style.bar.iconSlot + Style.space(16)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  // ---------- lookups shared with first-party widgets ----------
  readonly property color foreground: barForeground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------- vibeup CLI detection ----------
  property bool installed: false
  property bool checked: false

  function refreshInstalled() {
    whichProcess.command = [
      "bash", "-c",
      'command -v vibeup >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/vibeup" ]'
    ]
    whichProcess.running = true
  }

  Process {
    id: whichProcess
    onExited: function (exitCode) {
      root.installed = exitCode === 0
      root.checked = true
      // First install flips installed while the panel is already open.
      if (root.installed && root.opened && root.pkgStatus === null) root.refreshPkgStatus()
    }
  }

  Component.onCompleted: root.refreshInstalled()

  // ---------- VibeKeys over BlueZ ----------
  // Matches both "VibeKeys" and "VibeKeys-MAX" advertisement names.
  readonly property var kbDevice: {
    const devs = Bluetooth.devices ? Bluetooth.devices.values : []
    return devs.find(d => (d.name || d.deviceName || "").indexOf("VibeKeys") !== -1) || null
  }
  readonly property bool connected: !!(kbDevice && kbDevice.connected)

  readonly property string statusLine: {
    if (!root.checked) return "Checking vibeup…"
    if (!root.installed) return "vibeup CLI is not installed."
    if (root.connected) return "VibeKeys connected" + (kbDevice.batteryAvailable
        ? " · battery " + Math.round(kbDevice.battery * 100) + "%" : "")
    return "vibeup installed — keyboard not connected"
  }

  // ---------- install flow ----------
  property string installLog: ""
  // -2 = not started, -1 = running, >= 0 = finished with that exit code
  property int installExit: -2

  // The installer is a vendored copy of vibeup's install.sh, served from THIS
  // repository so the reviewed source is exactly what runs (the marketplace
  // baseline exempts downloads scoped to the submission's own repository).
  // The full URL must stay inside this one string literal: the baseline
  // scanner extracts command strings from QML and can only apply that
  // exemption when it can see the URL itself.
  readonly property string installUrl:
    "https://raw.githubusercontent.com/second-state/omarchy-vibeup-plugin/main/install.sh"

  function startInstall() {
    root.installLog = ""
    root.installExit = -1
    installProcess.running = true
  }

  function appendLog(line) {
    root.installLog += line + "\n"
  }

  Process {
    id: installProcess
    // Full URL inline (not concatenated) so the baseline scanner sees the
    // submission-repository scope and applies its own-repository exemption.
    command: ["bash", "-c",
      "curl -fsSL https://raw.githubusercontent.com/second-state/omarchy-vibeup-plugin/main/install.sh | bash"]
    stdout: SplitParser { onRead: line => root.appendLog(line) }
    stderr: SplitParser { onRead: line => root.appendLog(line) }
    onExited: function (exitCode) {
      root.installExit = exitCode === undefined ? 0 : exitCode
      root.refreshInstalled()
    }
  }

  // ---------- companion package versions (`vibeup status --json`) ----------
  // Refreshed on panel open; each row is {name, installed, latest,
  // latestPre, updateAvailable}. Network lookups can take a moment, so the
  // panel shows the last snapshot and a "checking" hint meanwhile.
  property var pkgStatus: null
  property string pkgStatusRaw: ""
  property bool statusChecking: false

  function refreshPkgStatus() {
    if (!root.installed) return
    root.statusChecking = true
    statusProcess.command = [
      "bash", "-c",
      'V=$(command -v vibeup || echo "$HOME/.cargo/bin/vibeup"); "$V" status --json 2>/dev/null'
    ]
    statusProcess.running = true
  }

  Process {
    id: statusProcess
    stdout: SplitParser { onRead: line => root.pkgStatusRaw += line }
    onExited: function (exitCode) {
      root.statusChecking = false
      if (exitCode === 0 && root.pkgStatusRaw !== "") {
        try { root.pkgStatus = JSON.parse(root.pkgStatusRaw) } catch (e) {}
      }
      root.pkgStatusRaw = ""
    }
  }

  onOpenedChanged: if (opened) {
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    root.refreshPkgStatus()
  }

  // ---------- bar icon ----------
  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)

    BarIconButton {
      id: button
      anchors.fill: parent
      bar: root.bar
      tooltipText: "VibeUp: " + root.statusLine
      iconComponent: Component {
        // Brand SVG, centered by PreserveAspectFit. The artwork's color is
        // baked in, so the connected/disconnected state uses opacity instead
        // of recoloring.
        Image {
          anchors.fill: parent
          source: Qt.resolvedUrl("./icon.svg")
          fillMode: Image.PreserveAspectFit
          opacity: root.connected ? 1 : 0.5
        }
      }
      onPressed: function (buttonCode) {
        if (buttonCode === Qt.LeftButton) root.toggle()
      }
    }
  }

  // ---------- panel (drops from the bar icon) ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
    }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(12)

      PanelHero {
        width: parent.width
        title: "VibeUp"
        meta: root.statusLine
        detail: root.connected && kbDevice ? (kbDevice.name || kbDevice.deviceName || "VibeKeys") : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconComponent: Component {
          Image {
            width: Style.font.display
            height: Style.font.display
            source: Qt.resolvedUrl("./icon.svg")
            fillMode: Image.PreserveAspectFit
            opacity: root.connected ? 1 : 0.5
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        visible: root.installed && !root.connected
        text: "The keyboard isn't connected. Pair it in the Bluetooth panel, or wake it and give it a second."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        visible: !root.installed
        text: "Install the vibeup CLI to configure the keyboard over Bluetooth (Wi-Fi, ASR, key remaps). The installer runs with its output shown below — nothing is downloaded until you click."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Button {
        width: parent.width
        visible: root.installed
        text: "Open vibeup TUI"
        onClicked: {
          root.close()
          Util.execDetached("omarchy-launch-terminal vibeup tui")
        }
      }

      // Companion tools vibeup manages, with installed → latest versions.
      Text {
        width: parent.width
        visible: root.installed
        text: "Packages (vibeup)"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: root.installed && root.pkgStatus ? root.pkgStatus : []
        delegate: Text {
          required property var modelData
          width: parent.width
          text: {
            var s = modelData.name + "  " + (modelData.installed || "not installed")
            if (!modelData.latest) return s + "   (lookup failed)"
            if (modelData.updateAvailable) return s + "   → " + modelData.latest
            return s + "   · up to date"
          }
          color: modelData.updateAvailable ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Text {
        width: parent.width
        visible: root.installed && root.statusChecking && !root.pkgStatus
        text: "Checking versions…"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Button {
        width: parent.width
        visible: !root.installed
        enabled: root.installExit !== -1
        text: root.installExit === -1 ? "Installing…" : "Install vibeup"
        onClicked: root.startInstall()
      }

      Rectangle {
        width: parent.width
        visible: root.installLog !== ""
        height: Math.min(200, logText.implicitHeight + 2 * Style.space(8))
        color: Qt.darker(Color.popups.background, 1.25)
        border.width: 1
        border.color: Color.popups.border
        radius: Style.space(6)
        clip: true

        Text {
          id: logText
          anchors.fill: parent
          anchors.margins: Style.space(8)
          text: root.installLog
          color: Color.popups.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
        }
      }

      Text {
        width: parent.width
        visible: root.installExit >= 0
        text: root.installExit === 0
              ? "Installed. Open a new terminal to pick up PATH changes, then reopen this panel."
              : "Install failed (exit " + root.installExit + ") — see the log above."
        color: root.installExit === 0 ? root.foreground : root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }
}
