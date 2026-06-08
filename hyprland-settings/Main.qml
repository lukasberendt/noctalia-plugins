import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root
  property var pluginApi: null

  function openSettingsWindow(targetScreen) {
    if (settingsWindow) {
      settingsWindow.screen = targetScreen;
      settingsWindow.visible = true;
    }
  }

  function closeSettingsWindow() {
    if (settingsWindow) {
      settingsWindow.visible = false;
    }
  }

  SettingsWindow {
    id: settingsWindow
    pluginApi: root.pluginApi
  }
}
