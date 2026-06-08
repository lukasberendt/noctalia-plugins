import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  // Injected properties
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  icon: "settings"
  tooltipText: "Hyprland Settings"
  tooltipDirection: BarService.getTooltipDirection(screen?.name)
  baseSize: Style.getCapsuleHeightForScreen(screen?.name)
  applyUiScale: false

  // Make it a perfect circle
  customRadius: baseSize / 2

  colorBg: Style.capsuleColor
  colorFg: Color.mPrimary
  colorBgHover: Color.mHover
  colorFgHover: Color.mOnHover
  colorBorder: "transparent"
  colorBorderHover: "transparent"

  onClicked: {
    if (pluginApi && pluginApi.mainInstance) {
      pluginApi.mainInstance.openSettingsWindow(root.screen);
    } else {
      Logger.w("hyprland-settings", "Cannot open settings: pluginApi or mainInstance is null");
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": "Plugin Settings",
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: function (action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);
      if (action === "settings") {
        BarService.openPluginSettings(root.screen, pluginApi.manifest);
      }
    }
  }

  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }

  Component.onCompleted: {
    Logger.i("hyprland-settings", "Settings launcher widget loaded");
  }
}
