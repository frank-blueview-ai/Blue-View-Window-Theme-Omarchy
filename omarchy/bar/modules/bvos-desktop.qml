import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "bvos-desktop"
  ipcTarget: "bvos-desktop-panel"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  property bool desktopEnabled: false
  property bool desktopAppAvailable: false
  property bool linesEnabled: false
  property int timeoutSeconds: 150
  property string message: ""
  property var actionQueue: []
  property string location: "Automatic"
  property string skyTime: "live"
  property string clockFormat: "12"
  property string panelTheme: "light"
  property int glassOpacity: 95
  property int appOpacity: 100
  property int barOpacity: 0
  property string barColor: "theme"
  property string appCorners: "square"
  function glassColor(value) {
    var c = Qt.darker(value, 1.0)
    return Qt.rgba(c.r, c.g, c.b, root.glassOpacity / 100)
  }
  readonly property bool darkPanel: panelTheme === "dark"
  readonly property color cardColor: darkPanel ? "#141a16" : "#f6f5f1"
  readonly property color surfaceColor: darkPanel ? "#232d25" : "#efede6"
  readonly property color textColor: darkPanel ? "#e6e8df" : "#1f242c"
  readonly property color secondaryColor: darkPanel ? "#dde1d5" : "#3c434e"
  readonly property color accentColor: darkPanel ? "#9fc57e" : "#3e7222"
  readonly property color lineColor: darkPanel ? "#4d5f4a" : "#b9b8ae"
  readonly property string home: Quickshell.env("HOME")

  function refresh() { desktopStatus.running = true; linesStatus.running = true; appearanceStatus.running = true; barStatus.running = true; config.reload(); displayConfig.reload(); locationConfig.reload() }
  onOpenedChanged: if (opened) refresh()
  Process {
    id: barStatus
    command: ["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/bar-appearance.py", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var state = JSON.parse(text); root.barOpacity = state.opacity; root.barColor = state.color }
        catch (e) { root.message = "Could not read taskbar settings" }
      }
    }
  }
  Process {
    id: appearanceStatus
    command: ["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/window-appearance.py", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var status = JSON.parse(text); root.appOpacity = status.opacity; root.appCorners = status.corners }
        catch (e) { root.message = "Could not read window appearance" }
      }
    }
  }
  Process {
    command: ["test", "-x", root.home + "/.local/bin/bvos-desktop"]
    running: true
    onExited: function(code) { root.desktopAppAvailable = code === 0 }
  }
  Process {
    id: desktopStatus
    command: ["omarchy-shell", "bvos-screensaver", "desktop", "status"]
    stdout: StdioCollector { onStreamFinished: root.desktopEnabled = text.trim() === "on" }
  }
  Process {
    id: linesStatus
    command: ["omarchy-shell", "bvos-screensaver", "lines", "status"]
    stdout: StdioCollector { onStreamFinished: root.linesEnabled = text.trim() === "on" }
  }
  Process {
    id: action
    onExited: function(code) {
      root.message = code === 0 ? "" : "Could not apply setting"
      if (root.actionQueue.length) Qt.callLater(root.startNextAction)
      else root.refresh()
    }
  }
  function startNextAction() {
    if (action.running || !root.actionQueue.length) return
    var queue = root.actionQueue.slice()
    var args = queue.shift()
    root.actionQueue = queue
    action.command = args
    action.running = true
  }
  function run(args) {
    root.actionQueue = root.actionQueue.concat([args])
    root.startNextAction()
  }
  FileView {
    id: config
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { var data = JSON.parse(text()); root.timeoutSeconds = Number(data.idle.screensaver) || 150 }
      catch (e) { root.message = "Could not read idle settings" }
    }
  }
  FileView {
    id: locationConfig
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.location = JSON.parse(text()).name || "Automatic" } catch (e) { root.location = "Automatic" } }
    onLoadFailed: root.location = "Automatic"
  }
  FileView {
    id: displayConfig
    path: root.home + "/.local/state/bvos/display.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { var data = JSON.parse(text()); root.skyTime = data.skyTime || "live"; root.clockFormat = data.clockFormat || "12"; root.panelTheme = data.panelTheme === "dark" ? "dark" : "light"; root.glassOpacity = Math.max(10, Math.min(100, Number(data.opacity) || 95)) }
      catch (e) { root.message = "Could not read display settings" }
    }
  }
  component BrandButton: Rectangle {
    id: control
    property string text: ""
    property string tooltipText: ""
    property bool selected: false
    property bool bordered: false
    property bool focusable: false
    signal clicked()
    implicitWidth: label.implicitWidth + Style.space(20)
    implicitHeight: Style.space(32)
    radius: Style.space(8)
    gradient: Gradient {
      GradientStop { position: 0; color: control.selected ? (root.darkPanel ? "#4b6540" : "#e0edda") : (root.darkPanel ? "#29362b" : "#ffffff") }
      GradientStop { position: 1; color: control.selected ? (root.darkPanel ? "#354a30" : "#cbdcc5") : (root.darkPanel ? "#1d2920" : "#eeeee8") }
    }
    border.color: selected ? root.accentColor : (bordered ? root.lineColor : (root.darkPanel ? "#455747" : "#d9ded5"))
    border.width: 1
    activeFocusOnTab: focusable
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()
    Text {
      id: label
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - Style.space(12))
      text: control.text
      textFormat: Text.PlainText
      color: root.textColor
      font.family: "Sans Serif"
      font.pixelSize: Style.font.body
      font.bold: control.selected
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: control.clicked() }
    PanelToolTip { visible: mouse.containsMouse && control.tooltipText !== ""; text: control.tooltipText }
  }
  component BrandToggle: Rectangle {
    id: control
    property string label: ""
    property string description: ""
    property bool checked: false
    property string tooltipText: ""
    signal clicked()
    implicitHeight: Style.space(58)
    radius: Style.space(10)
    gradient: Gradient {
      GradientStop { position: 0; color: root.darkPanel ? "#29372b" : "#ffffff" }
      GradientStop { position: 1; color: root.darkPanel ? "#1c281f" : "#e9eee7" }
    }
    border.color: root.lineColor
    border.width: 1
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    Column {
      anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(75); spacing: Style.space(3)
      Text { textFormat: Text.PlainText; text: control.label; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body; font.bold: true }
      Text { textFormat: Text.PlainText; text: control.description; color: root.secondaryColor; font.family: "Sans Serif"; font.pixelSize: Style.font.caption; width: parent.width; elide: Text.ElideRight }
    }
    Rectangle {
      width: Style.space(38); height: Style.space(22); radius: height / 2
      anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
      color: control.checked ? root.accentColor : (root.darkPanel ? "#526052" : "#a5afa1")
      Rectangle { width: parent.height - 4; height: width; radius: width / 2; x: control.checked ? parent.width - width - 2 : 2; anchors.verticalCenter: parent.verticalCenter; color: "#ffffff" }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: control.clicked() }
    PanelToolTip { visible: mouse.containsMouse && control.tooltipText !== ""; text: control.tooltipText }
  }
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Blue View settings"
    hasVisualContent: true
    fixedWidth: Style.space(27)
    fixedHeight: Style.space(26)
    Image {
      anchors.centerIn: parent
      width: Style.space(24); height: Style.space(20)
      source: "file://" + root.home + "/.config/omarchy/bar/assets/blueview-ovals.svg"
      fillMode: Image.PreserveAspectFit
      smooth: true
      scale: button.pressScale
    }
    onPressed: function(b) { if (b === Qt.LeftButton) root.toggle() }
  }
  Window {
    id: panel
    title: "Blue View"
    visible: root.opened
    width: Style.space(390)
    height: Math.min(column.implicitHeight + Style.space(24), Screen.desktopAvailableHeight - Style.space(64))
    minimumWidth: Style.space(340)
    minimumHeight: Style.space(360)
    color: "transparent"
    onClosing: root.close()
    PanelKeyCatcher {
      anchors.fill: parent
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: root.glassColor(root.darkPanel ? "#253127" : "#ffffff") }
          GradientStop { position: 0.40; color: root.glassColor(root.cardColor) }
          GradientStop { position: 1; color: root.glassColor(root.darkPanel ? "#101813" : "#eaece6") }
        }
        radius: Style.space(12)
        border.color: root.lineColor
        border.width: 1
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
      Column {
        id: column
        width: parent.width
        spacing: Style.space(9)
        Row {
          width: parent.width
          spacing: Style.space(12)
          Image {
            width: Style.space(56)
            height: Style.space(56)
            source: "file://" + root.home + "/.config/omarchy/bar/assets/blueview-glass-polished.svg"
            fillMode: Image.PreserveAspectFit
            smooth: true
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Text {
              textFormat: Text.PlainText
              text: "Blue View"
              color: root.textColor
              font.family: "Sans Serif"
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: "Desktop & screensaver"
              color: root.textColor
              opacity: 0.85
              font.family: "Sans Serif"
              font.pixelSize: Style.font.caption
            }
          }
          BrandButton {
            anchors.verticalCenter: parent.verticalCenter
            text: root.darkPanel ? "☀ Light" : "☾ Dark"
            tooltipText: "Switch the Blue View panel appearance"
            focusable: true
            onClicked: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/set-display.py", "panelTheme", root.darkPanel ? "light" : "dark"])
          }
        }
        Text {
          width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
          text: "A living sky that follows the sun, moon, stars, and local weather throughout the day."
          color: root.secondaryColor; font.family: "Sans Serif"; font.pixelSize: Style.font.caption
        }
        BrandButton {
          width: parent.width; text: "Location: " + root.location; bordered: true; focusable: true
          tooltipText: "Choose the location used for BlueView sky and weather"
          onClicked: { root.close(); Quickshell.execDetached(["omarchy-shell", "omarchy.weather", "edit"]) }
        }
        Text { textFormat: Text.PlainText; width: parent.width; wrapMode: Text.WordWrap; text: "Location is shared with Omarchy Weather."; color: root.textColor; font.pixelSize: Style.font.caption }
        BrandToggle {
          id: desktopToggle
          width: parent.width
          tooltipText: "Turn the animated desktop sky on or off"
          label: "Live desktop"
          description: "Show the animated sky on the desktop"
          checked: root.desktopEnabled
          onClicked: root.run(["omarchy-shell", "bvos-screensaver", "desktop", root.desktopEnabled ? "off" : "on"])
        }
        BrandToggle {
          id: linesToggle
          width: parent.width
          tooltipText: "Show or hide lines between stars"
          label: "Constellation lines"
          description: "Draw lines between stars"
          checked: root.linesEnabled
          onClicked: root.run(["omarchy-shell", "bvos-screensaver", "lines", root.linesEnabled ? "off" : "on"])
        }
        Row {
          width: parent.width
          Text { textFormat: Text.PlainText; text: "Blue View opacity"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body }
          Item { width: Math.max(0, parent.width - opacityLabel.width - opacityValue.width); height: 1; Text { id: opacityLabel; visible: false; text: "Blue View opacity"; font.family: "Sans Serif"; font.pixelSize: Style.font.body } }
          Text { id: opacityValue; textFormat: Text.PlainText; text: root.glassOpacity + "%"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body }
        }
        Controls.Slider {
          id: opacitySlider
          width: parent.width
          implicitHeight: Style.space(28)
          height: implicitHeight
          from: 10; to: 100; stepSize: 5
          value: root.glassOpacity
          onMoved: { root.glassOpacity = Math.round(value / 5) * 5; saveOpacity.restart() }
          Timer {
            id: saveOpacity
            interval: 500
            onTriggered: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/set-display.py", "opacity", String(root.glassOpacity)])
          }
          Accessible.name: "Window opacity"
          background: Rectangle {
            x: opacitySlider.leftPadding; y: opacitySlider.topPadding + opacitySlider.availableHeight / 2 - height / 2
            width: opacitySlider.availableWidth; height: Style.space(6); radius: height / 2
            color: root.darkPanel ? "#526052" : "#cad4c5"
            Rectangle { width: opacitySlider.visualPosition * parent.width; height: parent.height; radius: height / 2; color: root.accentColor }
          }
          handle: Rectangle {
            x: opacitySlider.leftPadding + opacitySlider.visualPosition * (opacitySlider.availableWidth - width)
            y: opacitySlider.topPadding + opacitySlider.availableHeight / 2 - height / 2
            width: Style.space(20); height: width; radius: width / 2
            color: root.darkPanel ? "#e6e8df" : "#ffffff"; border.color: root.accentColor; border.width: 2
          }
        }
        Rectangle { width: parent.width; height: 1; color: root.lineColor }
        Text { textFormat: Text.PlainText; text: "Application windows"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body; font.bold: true }
        Text { textFormat: Text.PlainText; width: parent.width; wrapMode: Text.WordWrap; text: "Choose corners and transparency for desktop windows. Some apps may use their own window rules."; color: root.secondaryColor; font.family: "Sans Serif"; font.pixelSize: Style.font.caption }
        Row {
          spacing: Style.space(6)
          BrandButton {
            text: "Square"; selected: root.appCorners === "square"; focusable: true
            tooltipText: "Use square corners on application windows"
            onClicked: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/window-appearance.py", "corners", "square"])
          }
          BrandButton {
            text: "Rounded"; selected: root.appCorners === "rounded"; focusable: true
            tooltipText: "Use rounded corners on application windows"
            onClicked: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/window-appearance.py", "corners", "rounded"])
          }
        }
        Row {
          width: parent.width
          Text { id: appOpacityLabel; textFormat: Text.PlainText; text: "Application opacity"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body }
          Item { width: Math.max(0, parent.width - appOpacityLabel.width - appOpacityValue.width); height: 1 }
          Text { id: appOpacityValue; textFormat: Text.PlainText; text: root.appOpacity + "%"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body }
        }
        Controls.Slider {
          id: appOpacitySlider
          width: parent.width; implicitHeight: Style.space(28); height: implicitHeight
          from: 10; to: 100; stepSize: 5; value: root.appOpacity
          Accessible.name: "Application window opacity"
          onMoved: { root.appOpacity = Math.round(value / 5) * 5; saveAppOpacity.restart() }
          Timer {
            id: saveAppOpacity; interval: 500
            onTriggered: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/window-appearance.py", "opacity", String(root.appOpacity)])
          }
          background: Rectangle {
            x: appOpacitySlider.leftPadding; y: appOpacitySlider.topPadding + appOpacitySlider.availableHeight / 2 - height / 2
            width: appOpacitySlider.availableWidth; height: Style.space(6); radius: height / 2
            color: root.darkPanel ? "#526052" : "#cad4c5"
            Rectangle { width: appOpacitySlider.visualPosition * parent.width; height: parent.height; radius: height / 2; color: root.accentColor }
          }
          handle: Rectangle {
            x: appOpacitySlider.leftPadding + appOpacitySlider.visualPosition * (appOpacitySlider.availableWidth - width)
            y: appOpacitySlider.topPadding + appOpacitySlider.availableHeight / 2 - height / 2
            width: Style.space(20); height: width; radius: width / 2
            color: root.darkPanel ? "#e6e8df" : "#ffffff"; border.color: root.accentColor; border.width: 2
          }
        }
        Rectangle { width: parent.width; height: 1; color: root.lineColor }
        Text { textFormat: Text.PlainText; text: "Taskbar"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body; font.bold: true }
        Row {
          width: parent.width
          Text { id: barOpacityLabel; textFormat: Text.PlainText; text: "Background opacity"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body }
          Item { width: Math.max(0, parent.width - barOpacityLabel.width - barOpacityValue.width); height: 1 }
          Text { id: barOpacityValue; textFormat: Text.PlainText; text: root.barOpacity + "%"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body }
        }
        Controls.Slider {
          id: barOpacitySlider
          width: parent.width; implicitHeight: Style.space(28); height: implicitHeight
          from: 0; to: 100; stepSize: 5; value: root.barOpacity
          Accessible.name: "Taskbar background opacity"
          onMoved: { root.barOpacity = Math.round(value / 5) * 5; saveBarOpacity.restart() }
          Timer {
            id: saveBarOpacity; interval: 500
            onTriggered: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/bar-appearance.py", "opacity", String(root.barOpacity)])
          }
          background: Rectangle {
            x: barOpacitySlider.leftPadding; y: barOpacitySlider.topPadding + barOpacitySlider.availableHeight / 2 - height / 2
            width: barOpacitySlider.availableWidth; height: Style.space(6); radius: height / 2
            color: root.darkPanel ? "#526052" : "#cad4c5"
            Rectangle { width: barOpacitySlider.visualPosition * parent.width; height: parent.height; radius: height / 2; color: root.accentColor }
          }
          handle: Rectangle {
            x: barOpacitySlider.leftPadding + barOpacitySlider.visualPosition * (barOpacitySlider.availableWidth - width)
            y: barOpacitySlider.topPadding + barOpacitySlider.availableHeight / 2 - height / 2
            width: Style.space(20); height: width; radius: width / 2
            color: root.darkPanel ? "#e6e8df" : "#ffffff"; border.color: root.accentColor; border.width: 2
          }
        }
        Text { textFormat: Text.PlainText; text: "Icon and text color"; color: root.textColor; font.family: "Sans Serif"; font.pixelSize: Style.font.body }
        Row {
          spacing: Style.space(4)
          Repeater {
            model: [ {label:"Theme", value:"theme"}, {label:"Bright", value:"bright"}, {label:"Blue", value:"blue"}, {label:"Green", value:"green"} ]
            BrandButton {
              required property var modelData
              text: modelData.label; selected: root.barColor === modelData.value; focusable: true
              tooltipText: "Use " + modelData.label.toLowerCase() + " for taskbar text and monochrome icons"
              onClicked: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/bar-appearance.py", "color", modelData.value])
            }
          }
        }
        Rectangle { width: parent.width; height: 1; color: root.lineColor }
        Text { textFormat: Text.PlainText; text: "Sky time"; color: root.textColor; font.pixelSize: Style.font.body }
        Row {
          spacing: Style.space(4)
          Repeater {
            model: [ {label: "Live", value: "live"}, {label: "Noon", value: "day"}, {label: "6 PM", value: "sunset"}, {label: "11 PM", value: "night"} ]
            BrandButton {
              required property var modelData
              text: modelData.label; selected: root.skyTime === modelData.value; focusable: true
              tooltipText: modelData.value === "live" ? "Follow the current time" : "Show the sky at " + modelData.label
              onClicked: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/set-display.py", "skyTime", modelData.value])
            }
          }
        }
        Text { textFormat: Text.PlainText; text: "Clock format"; color: root.textColor; font.pixelSize: Style.font.body }
        Row {
          spacing: Style.space(4)
          Repeater {
            model: [ {label: "12-hour", value: "12"}, {label: "24-hour", value: "24"} ]
            BrandButton {
              required property var modelData
              text: modelData.label; selected: root.clockFormat === modelData.value; focusable: true
              tooltipText: "Use a " + modelData.label + " screensaver clock"
              onClicked: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/set-display.py", "clockFormat", modelData.value])
            }
          }
        }
        Text { textFormat: Text.PlainText; text: "Screensaver starts after " + (root.timeoutSeconds / 60) + " minutes"; color: root.textColor; font.pixelSize: Style.font.body }
        Row {
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: [ {label: "1 min", value: 60}, {label: "2½ min", value: 150}, {label: "5 min", value: 300}, {label: "10 min", value: 600} ]
            BrandButton {
              required property var modelData
              text: modelData.label
              tooltipText: "Start the screensaver after " + modelData.label + " of inactivity"
              selected: root.timeoutSeconds === modelData.value
              focusable: true
              onClicked: root.run(["python3", root.home + "/.config/omarchy/plugins/bvos.screensaver/set-timeout.py", String(modelData.value)])
            }
          }
        }
        BrandButton {
          width: parent.width; text: "Preview screensaver"; bordered: true; focusable: true
          tooltipText: "Show the screensaver now; move the mouse or press a key to exit"
          onClicked: { root.close(); root.run(["omarchy-shell", "bvos-screensaver", "show"]) }
        }
        BrandButton {
          width: parent.width; text: "Open BlueView Desktop"; bordered: true; focusable: true
          visible: root.desktopAppAvailable
          tooltipText: "Open the BlueView Desktop application"
          onClicked: { root.close(); Quickshell.execDetached([root.home + "/.local/bin/bvos-desktop"]) }
        }
        Text { textFormat: Text.PlainText; visible: root.message !== ""; text: root.message; color: root.textColor; font.pixelSize: Style.font.caption }
        Rectangle { width: parent.width; height: 1; color: root.lineColor }
        Text {
          textFormat: Text.PlainText; text: "Powered by BvOS Intelligence"
          color: root.accentColor; font.family: "Sans Serif"; font.pixelSize: Style.font.caption; font.underline: true
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally("https://bvos.blueview.ai/") }
        }
        Text { textFormat: Text.PlainText; text: "Naturally Yours"; color: root.secondaryColor; font.family: "Sans Serif"; font.italic: true; font.pixelSize: Style.font.caption }
        Text {
          width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; textFormat: Text.PlainText
          text: "© " + new Date().getFullYear() + " The Blue View Group Corporation"
          color: root.secondaryColor; font.family: "Sans Serif"; font.pixelSize: Style.font.caption
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.space(12)
          BrandButton { text: "bvos.blueview.ai"; tooltipText: "Visit Blue View OS"; onClicked: Qt.openUrlExternally("https://bvos.blueview.ai/") }
          BrandButton { text: "blueview.ai"; tooltipText: "Visit The Blue View Group"; onClicked: Qt.openUrlExternally("https://blueview.ai/") }
        }
      }
      }
    }
  }
}
