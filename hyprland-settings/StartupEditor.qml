import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property string textContent: ""
  signal saved(string newText)

  ListModel {
    id: startupModel
  }

  property var headerLines: []
  property var footerLines: []

  onTextContentChanged: {
    var newSerialized = serializeText();
    if (textContent !== newSerialized) {
      var parsed = parseText(textContent);
      startupModel.clear();
      for (var j = 0; j < parsed.length; j++) {
        startupModel.append(parsed[j]);
      }
    }
  }

  function parseText(text) {
    var lines = text.split("\n");
    var parsed = [];
    var currentPreceding = [];
    var firstExecFound = false;

    for (var i = 0; i < lines.length; i++) {
      var lineText = lines[i];
      var lineTrimmed = lineText.trim();
      
      var match = lineTrimmed.match(/^\s*(#\s*)?exec-once\s*=\s*(.*)$/);
      if (match) {
        var isCommented = match[1] !== undefined && match[1].trim() === "#";
        var fullVal = match[2].trim();

        var inlineComment = "";
        var command = fullVal;
        var inlineMatch = fullVal.match(/^(.*?)\s+#\s*(.*)$/);
        if (inlineMatch) {
          command = inlineMatch[1].trim();
          inlineComment = " # " + inlineMatch[2].trim();
        }

        if (!firstExecFound) {
          firstExecFound = true;
          var lastEmptyIdx = -1;
          for (var k = 0; k < currentPreceding.length; k++) {
            if (currentPreceding[k].type === "empty") {
              lastEmptyIdx = k;
            }
          }
          if (lastEmptyIdx !== -1) {
            root.headerLines = currentPreceding.slice(0, lastEmptyIdx + 1);
            currentPreceding = currentPreceding.slice(lastEmptyIdx + 1);
          } else {
            root.headerLines = [];
          }
        }

        parsed.push({
          enabled: !isCommented,
          command: command,
          inlineComment: inlineComment,
          precedingLines: currentPreceding
        });
        currentPreceding = [];
      } else {
        var type = "raw";
        if (lineTrimmed === "") {
          type = "empty";
        } else if (lineTrimmed.startsWith("#")) {
          type = "comment";
        }
        currentPreceding.push({ type: type, text: lineText });
      }
    }

    if (!firstExecFound) {
      root.headerLines = currentPreceding;
      root.footerLines = [];
    } else {
      root.footerLines = currentPreceding;
    }

    return parsed;
  }

  function serializeText() {
    var lines = [];
    
    for (var h = 0; h < root.headerLines.length; h++) {
      lines.push(root.headerLines[h].text);
    }

    for (var i = 0; i < startupModel.count; i++) {
      var item = startupModel.get(i);
      
      var preceding = item.precedingLines;
      if (preceding) {
        var count = preceding.count !== undefined ? preceding.count : preceding.length;
        for (var j = 0; j < count; j++) {
          var pLine = preceding.get !== undefined ? preceding.get(j) : preceding[j];
          lines.push(pLine.text);
        }
      }

      var prefix = item.enabled ? "exec-once = " : "# exec-once = ";
      var lineContent = prefix + item.command + (item.inlineComment || "");
      lines.push(lineContent);
    }

    for (var f = 0; f < root.footerLines.length; f++) {
      lines.push(root.footerLines[f].text);
    }

    return lines.join("\n");
  }

  function save() {
    var newText = serializeText();
    root.saved(newText);
  }

  function deleteItem(index) {
    startupModel.remove(index);
    save();
  }

  function addItem() {
    startupModel.append({ enabled: true, command: "", inlineComment: "", precedingLines: [] });
    save();
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginM

    // Toolbar / Header
    RowLayout {
      Layout.fillWidth: true
      NText {
        text: "Startup Programs"
        font.weight: Font.DemiBold
        pointSize: Style.fontSizeM
        color: Color.mOnSurface
      }
      Item { Layout.fillWidth: true }
      NButton {
        text: "Add Program"
        icon: "plus"
        onClicked: root.addItem()
      }
    }

    NDivider { Layout.fillWidth: true }

    // Scrollable editor list
    ListView {
      id: startupListView
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.marginS
      model: startupModel
      boundsBehavior: Flickable.StopAtBounds

      visible: startupModel.count > 0

      delegate: Rectangle {
        width: startupListView.width - Style.marginL
        height: 44 * Style.uiScaleRatio
        color: "transparent"

        RowLayout {
          anchors.fill: parent
          spacing: Style.marginM

          // Drag Handle
          MouseArea {
            id: dragArea
            Layout.preferredWidth: 32
            Layout.fillHeight: true
            cursorShape: Qt.SizeAllCursor

            NIcon {
              anchors.centerIn: parent
              icon: "menu" // drag handle icon
              color: dragArea.pressed ? Color.mPrimary : Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
            }

            property real dragStartGlobalY: 0
            
            onPressed: mouse => {
              var globalPos = mapToItem(startupListView, mouse.x, mouse.y);
              dragStartGlobalY = globalPos.y;
              startupListView.interactive = false;
            }

            onPositionChanged: mouse => {
              var globalPos = mapToItem(startupListView, mouse.x, mouse.y);
              var deltaY = globalPos.y - dragStartGlobalY;
              var threshold = 44 * Style.uiScaleRatio;
              if (deltaY < -threshold && index > 0) {
                startupModel.move(index, index - 1, 1);
                dragStartGlobalY -= threshold;
              } else if (deltaY > threshold && index < startupModel.count - 1) {
                startupModel.move(index, index + 1, 1);
                dragStartGlobalY += threshold;
              }
            }

            onReleased: {
              startupListView.interactive = true;
              root.save();
            }
          }

          NToggle {
            checked: model.enabled
            onToggled: function (isChecked) {
              if (model.enabled !== isChecked) {
                model.enabled = isChecked;
                root.save();
              }
            }
          }

          NTextInput {
            text: model.command
            placeholderText: "e.g. waybar"
            Layout.fillWidth: true
            onEditingFinished: {
              if (model.command !== text) {
                model.command = text;
                root.save();
              }
            }
          }

          NIconButton {
            icon: "trash"
            colorFg: Color.mError
            onClicked: root.deleteItem(index)
          }
        }
      }
    }

    // Empty state
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: startupModel.count === 0
      spacing: Style.marginM
      Layout.alignment: Qt.AlignCenter

      NText {
        text: "No startup programs defined yet."
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignHCenter
      }

      NButton {
        text: "Create One"
        icon: "plus"
        Layout.alignment: Qt.AlignHCenter
        onClicked: root.addItem()
      }
    }
  }
}
