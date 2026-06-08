import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

  property string textContent: ""
  signal saved(string newText)

  property var parsedLines: []
  property var connectedMonitors: []
  property var monitorStates: ({})
  property string selectedMonitorName: ""

  readonly property int enabledMonitorCount: {
    var count = 0;
    for (var i = 0; i < connectedMonitors.length; i++) {
      var state = monitorStates[connectedMonitors[i].name];
      if (state && state.enabled) count++;
    }
    return count;
  }

  readonly property var selectedMonitor: {
    for (var i = 0; i < connectedMonitors.length; i++) {
      if (connectedMonitors[i].name === selectedMonitorName) {
        return connectedMonitors[i];
      }
    }
    return null;
  }
  
  readonly property var selectedState: selectedMonitor ? monitorStates[selectedMonitor.name] : null

  // Canvas dimensions
  property real canvasWidth: 500 * Style.uiScaleRatio
  property real canvasHeight: 200 * Style.uiScaleRatio
  property real scenePadding: 24 * Style.uiScaleRatio

  // Bounds of all enabled displays on the virtual coordinate space
  readonly property var sceneBounds: {
    var list = [];
    for (var i = 0; i < root.connectedMonitors.length; i++) {
      var m = root.connectedMonitors[i];
      var state = root.monitorStates[m.name];
      if (state && state.enabled) {
        var size = parseResolution(state.resolution, m);
        list.push({
          x: state.x,
          y: state.y,
          width: size.width,
          height: size.height
        });
      }
    }
    
    if (list.length === 0) {
      return { minX: 0, minY: 0, maxX: 1920, maxY: 1080, width: 1920, height: 1080 };
    }
    
    var minX = list[0].x;
    var minY = list[0].y;
    var maxX = list[0].x + list[0].width;
    var maxY = list[0].y + list[0].height;
    
    for (var j = 1; j < list.length; j++) {
      minX = Math.min(minX, list[j].x);
      minY = Math.min(minY, list[j].y);
      maxX = Math.max(maxX, list[j].x + list[j].width);
      maxY = Math.max(maxY, list[j].y + list[j].height);
    }
    
    return {
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
      width: Math.max(1, maxX - minX),
      height: Math.max(1, maxY - minY)
    };
  }

  readonly property real sceneScale: {
    var availW = root.canvasWidth - (root.scenePadding * 2);
    var availH = root.canvasHeight - (root.scenePadding * 2);
    if (availW <= 0 || availH <= 0) return 0.1;
    return Math.min(availW / root.sceneBounds.width, availH / root.sceneBounds.height);
  }

  onTextContentChanged: {
    var newSerialized = serializeConfig();
    if (textContent !== newSerialized) {
      parseConfig(textContent);
    }
  }

  Component.onCompleted: {
    queryMonitorsProc.running = true;
  }

  Process {
    id: queryMonitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      id: queryStdout
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        try {
          var parsed = JSON.parse(queryStdout.text.trim());
          root.connectedMonitors = parsed;
          if (root.selectedMonitorName === "" && parsed.length > 0) {
            root.selectedMonitorName = parsed[0].name;
          }
          root.parseConfig(root.textContent);
        } catch(e) {
          Logger.e("hyprland-settings", "Error parsing hyprctl monitors output: " + e);
        }
      }
    }
  }

  function isMonitorConnected(name) {
    for (var i = 0; i < root.connectedMonitors.length; i++) {
      var m = root.connectedMonitors[i];
      if (m.name === name) return true;
      var descName = "desc:" + m.description;
      if (descName === name) return true;
      if (name.startsWith("desc:") && m.description.includes(name.substring(5).trim())) return true;
    }
    return false;
  }

  function getConnectedMonitorName(name) {
    for (var i = 0; i < root.connectedMonitors.length; i++) {
      var m = root.connectedMonitors[i];
      if (m.name === name) return m.name;
      var descName = "desc:" + m.description;
      if (descName === name) return m.name;
      if (name.startsWith("desc:") && m.description.includes(name.substring(5).trim())) return m.name;
    }
    return name;
  }

  function parsePosition(posStr) {
    var match = posStr.match(/^(-?\d+)x(-?\d+)$/);
    if (match) {
      return { x: parseInt(match[1]), y: parseInt(match[2]) };
    }
    return { x: 0, y: 0 };
  }

  function parseResolution(resStr, monitor) {
    var match = (resStr || "").match(/^(\d+)x(\d+)/);
    if (match) {
      return { width: parseInt(match[1]), height: parseInt(match[2]) };
    }
    return { width: monitor ? monitor.width : 1920, height: monitor ? monitor.height : 1080 };
  }

  function parseConfig(text) {
    var lines = text.split("\n");
    var parsed = [];
    var states = {};
    
    for (var i = 0; i < lines.length; i++) {
      var lineText = lines[i];
      var lineTrimmed = lineText.trim();
      
      var match = lineTrimmed.match(/^\s*(#\s*)?monitor\s*=\s*([^,]+)\s*,\s*(.*)$/);
      if (match) {
        var isCommented = match[1] !== undefined && match[1].trim() === "#";
        var name = match[2].trim();
        var argsText = match[3].trim();
        
        if (isMonitorConnected(name)) {
          var args = argsText.split(",").map(x => x.trim());
          var res = args[0] || "preferred";
          var pos = args[1] || "auto";
          var scale = args[2] || "1";
          
          var disabled = (res === "disable" || res === "disabled");
          var mirror = "";
          for (var k = 3; k < args.length; k++) {
            if (args[k] === "mirror" && args[k+1]) {
              mirror = args[k+1];
              break;
            }
          }
          
          var parsedPos = parsePosition(pos);
          var exactName = getConnectedMonitorName(name);
          
          states[exactName] = {
            enabled: !disabled && !isCommented,
            resolution: disabled ? "preferred" : res,
            x: parsedPos.x,
            y: parsedPos.y,
            scale: scale,
            mirror: mirror,
            existsInConfig: true,
            originalNameInConfig: name
          };
          
          parsed.push({ type: "monitor", name: exactName });
        } else {
          parsed.push({ type: "raw", text: lineText });
        }
      } else {
        var type = "raw";
        if (lineTrimmed === "") {
          type = "empty";
        } else if (lineTrimmed.startsWith("#")) {
          type = "comment";
        }
        parsed.push({ type: type, text: lineText });
      }
    }
    
    for (var j = 0; j < root.connectedMonitors.length; j++) {
      var m = root.connectedMonitors[j];
      if (!states[m.name]) {
        states[m.name] = {
          enabled: !m.disabled,
          resolution: m.width + "x" + m.height + "@" + m.refreshRate.toFixed(3),
          x: m.x,
          y: m.y,
          scale: String(m.scale),
          mirror: m.mirrorOf !== "none" ? m.mirrorOf : "",
          existsInConfig: false,
          originalNameInConfig: m.name
        };
      }
    }
    
    root.parsedLines = parsed;
    root.monitorStates = states;
  }

  function serializeConfig() {
    var lines = [];
    var writtenNames = {};
    
    for (var i = 0; i < root.parsedLines.length; i++) {
      var item = root.parsedLines[i];
      if (item.type === "monitor") {
        var name = item.name;
        var state = root.monitorStates[name];
        if (state) {
          var configName = state.originalNameInConfig || name;
          lines.push(serializeMonitorRule(configName, state));
          writtenNames[name] = true;
        }
      } else {
        lines.push(item.text);
      }
    }
    
    for (var j = 0; j < root.connectedMonitors.length; j++) {
      var m = root.connectedMonitors[j];
      if (!writtenNames[m.name]) {
        var state = root.monitorStates[m.name];
        if (state) {
          lines.push(serializeMonitorRule(m.name, state));
        }
      }
    }
    
    return lines.join("\n");
  }

  function serializeMonitorRule(name, state) {
    if (!state.enabled) {
      return "monitor = " + name + ", disable";
    }
    var res = state.resolution || "preferred";
    var pos = state.x + "x" + state.y;
    var scale = state.scale || "1";
    var rule = "monitor = " + name + ", " + res + ", " + pos + ", " + scale;
    if (state.mirror) {
      rule += ", mirror, " + state.mirror;
    }
    return rule;
  }

  function save() {
    var newText = serializeConfig();
    root.saved(newText);
  }

  function snapOutput(monitorName, newX, newY, width, height) {
    var snapX = newX;
    var snapY = newY;
    var threshold = 80;
    
    for (var i = 0; i < root.connectedMonitors.length; i++) {
      var m = root.connectedMonitors[i];
      if (m.name === monitorName) continue;
      
      var state = root.monitorStates[m.name];
      if (!state || !state.enabled) continue;
      
      var size = parseResolution(state.resolution, m);
      var bx = state.x;
      var by = state.y;
      var bw = size.width;
      var bh = size.height;
      
      if (Math.abs(newX - (bx + bw)) < threshold) {
        snapX = bx + bw;
      } else if (Math.abs((newX + width) - bx) < threshold) {
        snapX = bx - width;
      }
      
      if (Math.abs(newY - (by + bh)) < threshold) {
        snapY = by + bh;
      } else if (Math.abs((newY + height) - by) < threshold) {
        snapY = by - height;
      }
      
      if (Math.abs(newY - by) < threshold) {
        snapY = by;
      } else if (Math.abs((newY + height) - (by + bh)) < threshold) {
        snapY = by + bh - height;
      }
      
      if (Math.abs(newX - bx) < threshold) {
        snapX = bx;
      } else if (Math.abs((newX + width) - (bx + bw)) < threshold) {
        snapX = bx + bw - width;
      }
    }
    
    return { x: Math.round(snapX), y: Math.round(snapY) };
  }

  function getResolutionModel(monitor) {
    if (!monitor || !monitor.availableModes) return [];
    var model = [];
    model.push({ key: "preferred", name: "Preferred Mode" });
    model.push({ key: "highres", name: "Highest Resolution" });
    model.push({ key: "highrr", name: "Highest Refresh Rate" });
    for (var i = 0; i < monitor.availableModes.length; i++) {
      var mode = monitor.availableModes[i];
      var cleanKey = mode.replace("Hz", "");
      model.push({ key: cleanKey, name: mode });
    }
    return model;
  }

  function getScaleModel(currentScale) {
    var base = [
      { key: "1.0", name: "100% (1.0)" },
      { key: "1.25", name: "125% (1.25)" },
      { key: "1.5", name: "150% (1.5)" },
      { key: "1.75", name: "175% (1.75)" },
      { key: "2.0", name: "200% (2.0)" }
    ];
    var found = false;
    for (var i = 0; i < base.length; i++) {
      if (parseFloat(base[i].key) === parseFloat(currentScale)) {
        found = true;
        break;
      }
    }
    if (!found && currentScale) {
      base.push({ key: String(currentScale), name: "Custom (" + currentScale + ")" });
    }
    return base;
  }

  function getMirrorModel(monitorName) {
    var model = [];
    model.push({ key: "", name: "Don't Mirror" });
    for (var i = 0; i < root.connectedMonitors.length; i++) {
      var name = root.connectedMonitors[i].name;
      if (name !== monitorName) {
        model.push({ key: name, name: name });
      }
    }
    return model;
  }

  ScrollView {
    anchors.fill: parent
    clip: true

    ColumnLayout {
      width: parent.width - 16 * Style.uiScaleRatio
      spacing: Style.marginL

      // Visual Canvas Container
      Rectangle {
        id: canvasContainer
        Layout.fillWidth: true
        Layout.preferredHeight: root.canvasHeight
        color: Qt.alpha(Color.mSurfaceVariant, 0.3)
        radius: Style.radiusL
        border.color: Color.mOutline
        border.width: Style.borderS
        clip: true

        onWidthChanged: root.canvasWidth = width
        onHeightChanged: root.canvasHeight = height

        // Grid Canvas
        Canvas {
          anchors.fill: parent
          anchors.margins: Style.borderS
          onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Qt.alpha(Color.mOutline, 0.1);
            ctx.lineWidth = 1;

            var step = 20 * Style.uiScaleRatio;
            for (var x = step; x < width; x += step) {
              ctx.beginPath();
              ctx.moveTo(x, 0);
              ctx.lineTo(x, height);
              ctx.stroke();
            }
            for (var y = step; y < height; y += step) {
              ctx.beginPath();
              ctx.moveTo(0, y);
              ctx.lineTo(width, y);
              ctx.stroke();
            }
          }
        }

        // Display Tiles on Canvas
        Repeater {
          model: root.connectedMonitors

          delegate: Item {
            id: monitorTile

            readonly property var mState: root.monitorStates[modelData.name]
            readonly property bool isEnabled: mState ? mState.enabled : false
            visible: isEnabled

            // Mapping properties
            x: mState ? root.scenePadding + (mState.x - root.sceneBounds.minX) * root.sceneScale : 0
            y: mState ? root.scenePadding + (mState.y - root.sceneBounds.minY) * root.sceneScale : 0
            width: mState ? parseResolution(mState.resolution, modelData).width * root.sceneScale : 100
            height: mState ? parseResolution(mState.resolution, modelData).height * root.sceneScale : 100

            property real pressMouseX: 0
            property real pressMouseY: 0
            property real pressX: 0
            property real pressY: 0

            NBox {
              anchors.fill: parent
              border.color: root.selectedMonitorName === modelData.name ? Color.mPrimary : Color.mOutline
              border.width: root.selectedMonitorName === modelData.name ? 2 : 1
              color: root.selectedMonitorName === modelData.name ? Qt.alpha(Color.mPrimary, 0.08) : Color.mSurface

              ColumnLayout {
                anchors.centerIn: parent
                spacing: Style.marginXS

                NText {
                  text: (index + 1) + ": " + modelData.name
                  font.weight: Font.DemiBold
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurface
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: mState ? parseResolution(mState.resolution, modelData).width + "x" + parseResolution(mState.resolution, modelData).height : ""
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
              
              onPressed: mouse => {
                root.selectedMonitorName = modelData.name;
                monitorTile.pressMouseX = mouse.x;
                monitorTile.pressMouseY = mouse.y;
                monitorTile.pressX = mState ? mState.x : 0;
                monitorTile.pressY = mState ? mState.y : 0;
              }

              onPositionChanged: mouse => {
                if (mState && (mouse.buttons & Qt.LeftButton) && root.enabledMonitorCount > 1) {
                  var deltaX = (mouse.x - monitorTile.pressMouseX) / root.sceneScale;
                  var deltaY = (mouse.y - monitorTile.pressMouseY) / root.sceneScale;
                  var newX = monitorTile.pressX + deltaX;
                  var newY = monitorTile.pressY + deltaY;
                  
                  var size = parseResolution(mState.resolution, modelData);
                  var snapped = snapOutput(modelData.name, newX, newY, size.width, size.height);
                  
                  mState.x = snapped.x;
                  mState.y = snapped.y;
                }
              }

              onReleased: {
                if (root.enabledMonitorCount > 1) {
                  root.save();
                }
              }
            }
          }
        }

        // Empty State
        NText {
          anchors.centerIn: parent
          visible: root.connectedMonitors.length === 0
          text: "Scanning for connected displays..."
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
        }
      }

      // Settings and Controls Section (Visible if a monitor is selected)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        visible: root.selectedMonitor !== null

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          NText {
            text: root.selectedMonitor ? "Monitor Settings: " + root.selectedMonitor.name : ""
            font.weight: Font.DemiBold
            pointSize: Style.fontSizeM
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          // Enable / Disable Display Toggle
          RowLayout {
            spacing: Style.marginM
            
            NText {
              text: "Enable Display"
              color: Color.mOnSurface
            }

            NToggle {
              checked: root.selectedState ? root.selectedState.enabled : false
              enabled: !checked || root.enabledMonitorCount > 1
              onToggled: function (isChecked) {
                if (root.selectedState && root.selectedState.enabled !== isChecked) {
                  root.selectedState.enabled = isChecked;
                  root.save();
                }
              }
            }
          }
        }

        NDivider { Layout.fillWidth: true }

        // Resolution & Scale in a two-column row
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginL
          visible: root.selectedState ? root.selectedState.enabled : false

          // Resolution
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            NText {
              text: "Resolution & Refresh Rate"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
            }

            NComboBox {
              Layout.fillWidth: true
              model: root.getResolutionModel(root.selectedMonitor)
              currentKey: root.selectedState ? root.selectedState.resolution : "preferred"
              onSelected: key => {
                if (root.selectedState && root.selectedState.resolution !== key) {
                  root.selectedState.resolution = key;
                  root.save();
                }
              }
            }
          }

          // Scale
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS

            NText {
              text: "Display Scale"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
            }

            NComboBox {
              Layout.fillWidth: true
              model: root.getScaleModel(root.selectedState ? root.selectedState.scale : "1.0")
              currentKey: root.selectedState ? root.selectedState.scale : "1.0"
              onSelected: key => {
                if (root.selectedState && root.selectedState.scale !== key) {
                  root.selectedState.scale = key;
                  root.save();
                }
              }
            }
          }
        }

        // Mirror Settings (Only visible if more than 1 connected monitor)
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginM
          visible: root.connectedMonitors.length > 1 && root.selectedState && root.selectedState.enabled

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              text: "Mirror Another Display"
              Layout.fillWidth: true
              color: Color.mOnSurface
            }

            NToggle {
              checked: root.selectedState ? root.selectedState.mirror !== "" : false
              onToggled: function (isChecked) {
                if (root.selectedState) {
                  if (!isChecked) {
                    root.selectedState.mirror = "";
                    root.save();
                  } else {
                    var model = root.getMirrorModel(root.selectedMonitorName);
                    if (model.length > 1) {
                      root.selectedState.mirror = model[1].key;
                      root.save();
                    }
                  }
                }
              }
            }
          }

          NComboBox {
            Layout.fillWidth: true
            visible: root.selectedState ? root.selectedState.mirror !== "" : false
            model: root.getMirrorModel(root.selectedMonitorName)
            currentKey: root.selectedState ? root.selectedState.mirror : ""
            onSelected: key => {
              if (root.selectedState && root.selectedState.mirror !== key) {
                root.selectedState.mirror = key;
                root.save();
              }
            }
          }
        }

        // Hardware Properties Section at the bottom
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginM
          Layout.topMargin: Style.marginM

          NText {
            text: "Hardware Properties"
            font.weight: Font.DemiBold
            pointSize: Style.fontSizeM
            color: Color.mOnSurface
          }

          NDivider { Layout.fillWidth: true }

          GridLayout {
            columns: 2
            columnSpacing: Style.marginL
            rowSpacing: Style.marginS
            Layout.fillWidth: true

            NText {
              text: "Model: " + (root.selectedMonitor ? root.selectedMonitor.make + " " + root.selectedMonitor.model : "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              Layout.fillWidth: true
            }

            NText {
              text: "Output Port: " + (root.selectedMonitor ? root.selectedMonitor.name : "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              Layout.fillWidth: true
            }

            NText {
              text: "Dimensions: " + (root.selectedMonitor ? root.selectedMonitor.physicalWidth + "x" + root.selectedMonitor.physicalHeight + " mm" : "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              Layout.fillWidth: true
            }

            NText {
              text: "Refresh Rate: " + (root.selectedMonitor ? root.selectedMonitor.refreshRate.toFixed(2) + " Hz" : "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              Layout.fillWidth: true
            }

            NText {
              text: "VRR: " + (root.selectedMonitor ? (root.selectedMonitor.vrr ? "Enabled" : "Disabled") : "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              Layout.fillWidth: true
            }

            NText {
              text: "Position in Layout: " + (root.selectedState ? root.selectedState.x + ", " + root.selectedState.y : "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              Layout.fillWidth: true
            }
          }
        }
      }
    }
  }
}
