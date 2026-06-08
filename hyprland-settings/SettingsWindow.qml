import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Widgets

PanelWindow {
  id: root

  property var pluginApi: null

  // Overlay properties to fill screen and show centered dialog
  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true
  visible: false
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  WlrLayershell.namespace: "hyprland-settings-overlay"
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  // Static configuration tabs list
  property var configTabs: [
    { name: "Monitors", file: "monitors.conf", icon: "device-desktop" },
    { name: "Startup", file: "startup.conf", icon: "rocket" },
    { name: "Environment", file: "env.conf", icon: "braces" },
    { name: "Input", file: "input.conf", icon: "keyboard" },
    { name: "Keybinds", file: "keybinds.conf", icon: "keyboard-hide" },
    { name: "Design", file: "design.conf", icon: "palette" },
    { name: "Window Rules", file: "windowrules.conf", icon: "app-window" }
  ]
  property string activeTabName: "monitors.conf"

  // Helper read-only property to get the active tab object
  readonly property var activeTab: {
    for (var i = 0; i < configTabs.length; i++) {
      if (configTabs[i].file === activeTabName) {
        return configTabs[i];
      }
    }
    return null;
  }

  // Editor states
  property string editorText: ""

  readonly property real shadowPadding: Style.shadowBlurMax + Style.marginL
  readonly property string configDir: (Quickshell.env("HOME") || "") + "/.config/hypr/conf"

  onVisibleChanged: {
    if (visible) {
      dialogContent.forceActiveFocus();
      initConfigProc.running = true;
    }
  }

  Component.onCompleted: {
    initConfigProc.running = true;
  }

  // Process to check if config directory exists, create it, and instantiate config files
  Process {
    id: initConfigProc
    command: [
      "sh", "-c",
      "mkdir -p '" + root.configDir + "' && " +
      "for f in monitors.conf startup.conf env.conf input.conf keybinds.conf design.conf windowrules.conf; do " +
      "  [ -f '" + root.configDir + "/'$f ] || touch '" + root.configDir + "/'$f; " +
      "done"
    ]
    running: false

    onExited: (exitCode, exitStatus) => {
      if (activeFileView.path !== "") {
        activeFileView.reload();
      }
    }
  }

  // FileView to read/write the active configuration file
  FileView {
    id: activeFileView
    path: root.activeTabName ? root.configDir + "/" + root.activeTabName : ""
    watchChanges: false
    printErrors: false

    onLoaded: {
      root.editorText = activeFileView.text();
    }
  }

  // Click outside to close
  MouseArea {
    anchors.fill: parent
    onClicked: root.visible = false
  }

  Item {
    id: dialogContainer
    anchors.centerIn: parent
    width: 850 * Style.uiScaleRatio + shadowPadding * 2
    height: 600 * Style.uiScaleRatio + shadowPadding * 2

    // Prevent clicks inside the dialog from triggering click-outside-to-close
    MouseArea {
      anchors.fill: parent
      onClicked: mouse => mouse.accepted = true
    }

    // Shadow effect (behind customBackground)
    NDropShadow {
      anchors.fill: customBackground
      source: customBackground
      autoPaddingEnabled: true
      z: -1
    }

    Rectangle {
      id: customBackground
      anchors.fill: parent
      anchors.margins: root.shadowPadding
      radius: Style.radiusL
      color: Qt.alpha(Color.mSurface, 0.95)
      border.color: Color.mOutline
      border.width: Style.borderS

      RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Sidebar (List of Config files)
        Rectangle {
          Layout.preferredWidth: 240 * Style.uiScaleRatio
          Layout.fillHeight: true
          color: Qt.alpha(Color.mSurfaceVariant, 0.4)
          topLeftRadius: Style.radiusL
          bottomLeftRadius: Style.radiusL
          topRightRadius: 0
          bottomRightRadius: 0

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            // Header Section
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NIcon {
                icon: "settings"
                color: Color.mPrimary
                pointSize: Style.fontSizeXL * 1.2
              }

              ColumnLayout {
                spacing: 0
                NText {
                  text: "Hyprland"
                  font.weight: Font.Bold
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurface
                }
                NText {
                  text: "Settings"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }
              }
            }

            NDivider {
              Layout.fillWidth: true
              Layout.topMargin: Style.marginS
              Layout.bottomMargin: Style.marginS
            }

            // Navigation Menu (Dynamic Tabs)
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              Layout.fillHeight: true

              Repeater {
                model: root.configTabs

                delegate: Rectangle {
                  id: navItem
                  Layout.fillWidth: true
                  Layout.preferredHeight: 44 * Style.uiScaleRatio
                  radius: Style.radiusM

                  readonly property bool active: root.activeTabName === modelData.file
                  readonly property bool hovered: mouseNavArea.containsMouse

                  color: active ? Qt.alpha(Color.mPrimary, 0.12) : (hovered ? Qt.alpha(Color.mOnSurface, 0.05) : "transparent")

                  Behavior on color {
                    ColorAnimation { duration: Style.animationFast }
                  }

                  // Vertical selection pill indicator
                  Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.marginXS
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4 * Style.uiScaleRatio
                    height: 20 * Style.uiScaleRatio
                    radius: Style.radiusS
                    color: Color.mPrimary
                    visible: navItem.active
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.marginL
                    anchors.rightMargin: Style.marginM
                    spacing: Style.marginM

                    NIcon {
                      icon: modelData.icon
                      color: navItem.active ? Color.mPrimary : Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeM
                    }

                    NText {
                      text: modelData.name
                      color: navItem.active ? Color.mPrimary : Color.mOnSurface
                      font.weight: navItem.active ? Font.DemiBold : Font.Normal
                      pointSize: Style.fontSizeM
                    }

                    Item { Layout.fillWidth: true }
                  }

                  MouseArea {
                    id: mouseNavArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activeTabName = modelData.file
                  }
                }
              }

              Item { Layout.fillHeight: true } // Spacer
            }
          }
        }

        // Vertical divider
        NDivider {
          vertical: true
          Layout.fillHeight: true
        }

        // Right Content Area (File Editor)
        Item {
          id: dialogContent
          Layout.fillWidth: true
          Layout.fillHeight: true
          focus: true

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.visible = false;
              event.accepted = true;
            }
          }

          NIconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Style.marginM
            anchors.rightMargin: Style.marginM
            icon: "x"
            baseSize: 28
            z: 10
            onClicked: root.visible = false
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: 0

            // Content Header
            RowLayout {
              Layout.fillWidth: true
              Layout.rightMargin: 40 * Style.uiScaleRatio
              spacing: Style.marginM
              Layout.bottomMargin: Style.marginM

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                NText {
                  text: root.activeTab ? root.activeTab.name : "Configuration File"
                  font.weight: Font.Bold
                  pointSize: Style.fontSizeXL
                  color: Color.mOnSurface
                }

                NText {
                  text: "~/.config/hypr/conf/" + (root.activeTabName ? root.activeTabName : "")
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  font.family: (Settings.data && Settings.data.ui && Settings.data.ui.fontFixed) || "monospace"
                }
              }
            }

            NDivider {
              Layout.fillWidth: true
              Layout.bottomMargin: Style.marginM
            }

            // Editor Area
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Loader {
                id: editorLoader
                anchors.fill: parent
                source: {
                  if (root.activeTabName === "env.conf") return "EnvEditor.qml";
                  if (root.activeTabName === "startup.conf") return "StartupEditor.qml";
                  if (root.activeTabName === "monitors.conf") return "MonitorsEditor.qml";
                  return "";
                }
              }

              Binding {
                target: editorLoader.item
                property: "textContent"
                value: root.editorText
                when: editorLoader.status === Loader.Ready
              }

              Connections {
                target: editorLoader.item
                ignoreUnknownSignals: true
                function onSaved(newText) {
                  root.editorText = newText;
                  activeFileView.setText(newText);
                }
              }

              // Fallback raw text viewer
              Rectangle {
                anchors.fill: parent
                visible: editorLoader.source === ""
                color: Color.mSurfaceVariant
                radius: Style.radiusM
                border.color: Color.mOutline
                border.width: Style.borderS

                ScrollView {
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  clip: true

                  TextArea {
                    id: editorArea
                    text: root.editorText
                    placeholderText: "File is empty"
                    placeholderTextColor: Color.mOnSurfaceVariant
                    wrapMode: TextEdit.NoWrap
                    readOnly: true
                    color: Color.mOnSurface
                    font.family: (Settings.data && Settings.data.ui && Settings.data.ui.fontFixed) || "monospace"
                    font.pointSize: Style.fontSizeM
                    background: null
                    selectByMouse: true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
