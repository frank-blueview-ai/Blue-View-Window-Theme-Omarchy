import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io

QtObject {
  id: root
  property var shell: null
  property string address: ""
  property string targetPid: ""
  property string appName: ""
  property int opacity: 100
  property bool remembered: false
  property string errorText: ""
  property bool resetting: false
  property var pending: []
  property bool dark: false
  readonly property color textColor: dark ? "#e6e8df" : "#1f242c"
  readonly property color secondaryColor: dark ? "#dde1d5" : "#3c434e"
  readonly property color accentColor: dark ? "#9fc57e" : "#3e7222"
  readonly property color borderColor: dark ? "#4d5f4a" : "#b9b8ae"
  property FileView displaySettings: FileView {
    path: Quickshell.env("HOME") + "/.local/state/bvos/display.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.dark = JSON.parse(text()).panelTheme === "dark" } catch (e) {} }
  }
  readonly property string helper: Quickshell.env("HOME") + "/.config/omarchy/plugins/bvos.window-opacity/control.py"

  function execute(args) {
    if (runner.running) { pending = args; return }
    runner.command = ["python3", helper].concat(args)
    runner.running = true
  }
  property Process runner: Process {
    id: runner
    stderr: StdioCollector { id: errors }
    onExited: function(code) {
      if (code !== 0) root.errorText = "Unable to update this window. It may have closed."
      else { root.errorText = ""; if (root.resetting) window.visible = false }
      root.resetting = false
      if (root.pending.length) { var next = root.pending; root.pending = []; root.execute(next) }
    }
  }
  property Timer debounce: Timer {
    interval: 250
    onTriggered: root.execute(["set", root.address, root.targetPid, String(root.opacity), root.remembered ? "yes" : "no"])
  }
  property IpcHandler ipc: IpcHandler {
    target: "bvos-window-opacity"
    function show(address: string, pid: string, app: string, value: string, remember: string): string {
      if (root.address !== address && (runner.running || debounce.running)) return "busy"
      root.address = address; root.targetPid = pid; root.appName = app
      root.opacity = Math.max(10, Math.min(100, Math.round(Number(value) / 5) * 5))
      root.remembered = remember === "yes"; root.errorText = ""
      window.visible = true
      window.requestActivate()
      return "ok"
    }
  }
  property Window window: Window {
    id: window
    title: "Window opacity"
    width: 370; height: root.errorText ? 315 : 290
    minimumWidth: 320; minimumHeight: 220
    color: "transparent"
    visible: false
    Rectangle {
      anchors.fill: parent; radius: 12; border.color: root.borderColor; border.width: 1
      gradient: Gradient {
        GradientStop { position: 0; color: root.dark ? "#253127" : "#ffffff" }
        GradientStop { position: 0.45; color: root.dark ? "#141a16" : "#f6f5f1" }
        GradientStop { position: 1; color: root.dark ? "#101813" : "#eaece6" }
      }
    }
    Column {
      anchors.fill: parent; anchors.margins: 18; spacing: 12
      Row {
        spacing: 10
        Image { width: 40; height: 40; fillMode: Image.PreserveAspectFit; source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/bar/assets/blueview-glass-polished.svg" }
        Column {
          anchors.verticalCenter: parent.verticalCenter; spacing: 3
          Text { text: "Window opacity"; textFormat: Text.PlainText; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: 17; font.bold: true }
          Text { text: "Blue View"; textFormat: Text.PlainText; color: root.secondaryColor; font.family: "Sans Serif"; font.pixelSize: 11 }
        }
      }
      Text { text: root.appName; textFormat: Text.PlainText; color: root.secondaryColor; font.family: "Sans Serif"; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight }
      Row {
        width: parent.width
        Text { text: "Opacity"; textFormat: Text.PlainText; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: 13 }
        Item { width: parent.width - 85; height: 1 }
        Text { text: root.opacity + "%"; textFormat: Text.PlainText; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: 13 }
      }
      Controls.Slider {
        id: slider
        width: parent.width; height: 28; from: 10; to: 100; stepSize: 5; value: root.opacity
        Accessible.name: "Window opacity"
        onMoved: { root.opacity = Math.round(value / 5) * 5; debounce.restart() }
        background: Rectangle {
          x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - height / 2
          width: slider.availableWidth; height: 6; radius: 3; color: root.dark ? "#526052" : "#cbd6c7"
          Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 3; color: root.accentColor }
        }
        handle: Rectangle {
          x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
          y: slider.topPadding + slider.availableHeight / 2 - height / 2
          width: 20; height: 20; radius: 10; color: "white"; border.color: root.accentColor; border.width: 2
        }
      }
      Controls.CheckBox {
        id: rememberBox
        width: parent.width; height: 38
        text: root.appName === "org.quickshell" ? "Shared shell window (current window only)" : "Remember for this application"
        checked: root.remembered
        enabled: root.appName !== "org.quickshell" && !runner.running
        onClicked: { debounce.stop(); root.remembered = checked; root.execute(["remember", root.address, root.targetPid, String(root.opacity), checked ? "yes" : "no"]) }
        indicator: Rectangle {
          x: 8; y: (rememberBox.height - height) / 2; width: 19; height: 19; radius: 5
          color: rememberBox.checked ? root.accentColor : (root.dark ? "#232d25" : "#ffffff")
          border.color: root.accentColor; border.width: 1
          Text { anchors.centerIn: parent; text: rememberBox.checked ? "✓" : ""; color: root.dark ? "#14200f" : "#ffffff"; font.bold: true; font.pixelSize: 14 }
        }
        contentItem: Text {
          leftPadding: 36; verticalAlignment: Text.AlignVCenter; text: rememberBox.text; textFormat: Text.PlainText
          color: root.textColor; opacity: rememberBox.enabled ? 1 : 0.7; font.family: "Sans Serif"; font.pixelSize: 13; elide: Text.ElideRight
        }
        background: Rectangle { radius: 8; color: root.dark ? "#232d25" : "#edf2eb"; border.color: root.borderColor }
      }
      Row {
        width: parent.width; spacing: 10
        Controls.Button {
          id: resetButton
          width: parent.width * 0.62; height: 36; text: "Reset to desktop default"; enabled: !runner.running
          onClicked: { debounce.stop(); root.resetting = true; root.execute(["reset", root.address, root.targetPid]) }
          contentItem: Text { text: resetButton.text; textFormat: Text.PlainText; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
          background: Rectangle { radius: 8; border.color: root.borderColor; gradient: Gradient { GradientStop { position: 0; color: root.dark ? "#29372b" : "#ffffff" } GradientStop { position: 1; color: root.dark ? "#1c281f" : "#e9eee7" } } }
        }
        Controls.Button {
          id: doneButton
          width: parent.width - resetButton.width - 10; height: 36; text: "Done"
          onClicked: { if (debounce.running) { debounce.stop(); root.execute(["set", root.address, root.targetPid, String(root.opacity), root.remembered ? "yes" : "no"]) } window.visible = false }
          contentItem: Text { text: doneButton.text; textFormat: Text.PlainText; color: root.dark ? "#14200f" : "#ffffff"; font.family: "Sans Serif"; font.bold: true; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
          background: Rectangle { radius: 8; color: root.accentColor; border.color: root.accentColor }
        }
      }
      Text { visible: root.errorText !== ""; text: root.errorText; textFormat: Text.PlainText; color: "#a02626"; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap }
    }
  }
}
