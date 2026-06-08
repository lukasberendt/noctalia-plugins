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

  property var items: []
  property var envItems: []

  onTextContentChanged: {
    var newSerialized = serializeText(root.items);
    if (textContent !== newSerialized) {
      var parsed = parseText(textContent);
      root.items = parsed;
      root.envItems = parsed.filter(item => item.type === "env");
    }
  }

  function parseText(text) {
    var lines = text.split("\n");
    var parsed = [];
    for (var i = 0; i < lines.length; i++) {
      var lineText = lines[i];
      var lineTrimmed = lineText.trim();
      
      var match = lineTrimmed.match(/^\s*(#\s*)?(env|envd)\s*=\s*([^,]+)\s*,\s*(.*)$/);
      if (match) {
        var isCommented = match[1] !== undefined && match[1].trim() === "#";
        var keyword = match[2];
        var key = match[3].trim();
        var fullVal = match[4].trim();

        var inlineComment = "";
        var value = fullVal;
        var inlineMatch = fullVal.match(/^(.*?)\s+#\s*(.*)$/);
        if (inlineMatch) {
          value = inlineMatch[1].trim();
          inlineComment = " # " + inlineMatch[2].trim();
        }

        parsed.push({
          type: "env",
          enabled: !isCommented,
          keyword: keyword,
          key: key,
          value: value,
          inlineComment: inlineComment
        });
      } else if (lineTrimmed.startsWith("#")) {
        parsed.push({ type: "comment", text: lineText });
      } else if (lineTrimmed === "") {
        parsed.push({ type: "empty", text: "" });
      } else {
        parsed.push({ type: "raw", text: lineText });
      }
    }
    return parsed;
  }

  function serializeText(itemsList) {
    var lines = [];
    for (var i = 0; i < itemsList.length; i++) {
      var item = itemsList[i];
      if (item.type === "env") {
        var prefix = item.enabled ? "" : "# ";
        var keyword = item.keyword || "env";
        var lineContent = prefix + keyword + " = " + item.key + ", " + item.value + (item.inlineComment || "");
        lines.push(lineContent);
      } else {
        lines.push(item.text);
      }
    }
    return lines.join("\n");
  }

  function save() {
    var newText = serializeText(root.items);
    root.saved(newText);
  }

  function deleteItem(index) {
    var itemToDelete = root.envItems[index];
    
    var newItems = [];
    for (var i = 0; i < root.items.length; i++) {
      if (root.items[i] !== itemToDelete) {
        newItems.push(root.items[i]);
      }
    }
    root.items = newItems;

    var newEnvs = [];
    for (var j = 0; j < root.envItems.length; j++) {
      if (root.envItems[j] !== itemToDelete) {
        newEnvs.push(root.envItems[j]);
      }
    }
    root.envItems = newEnvs;

    save();
  }

  function addItem() {
    var newItem = { type: "env", enabled: true, keyword: "env", key: "", value: "", inlineComment: "" };
    
    var newItems = [...root.items];
    newItems.push(newItem);
    root.items = newItems;

    var newEnvs = [...root.envItems];
    newEnvs.push(newItem);
    root.envItems = newEnvs;

    save();
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginM

    // Toolbar / Header
    RowLayout {
      Layout.fillWidth: true
      NText {
        text: "Environment Variables"
        font.weight: Font.DemiBold
        pointSize: Style.fontSizeM
        color: Color.mOnSurface
      }
      Item { Layout.fillWidth: true }
      NButton {
        text: "Add Variable"
        icon: "plus"
        onClicked: root.addItem()
      }
    }

    NDivider { Layout.fillWidth: true }

    // Scrollable editor list
    ScrollView {
      id: envScrollView
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true

      visible: root.envItems.length > 0

      ColumnLayout {
        width: envScrollView.width - Style.marginL
        spacing: Style.marginS

        // Table Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM
          
          NText {
            text: "Active"
            font.weight: Font.DemiBold
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            Layout.preferredWidth: 44 * Style.uiScaleRatio
            horizontalAlignment: Text.AlignHCenter
          }
          NText {
            text: "Type"
            font.weight: Font.DemiBold
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            Layout.preferredWidth: 70 * Style.uiScaleRatio
            horizontalAlignment: Text.AlignHCenter
          }
          NText {
            text: "Variable Name"
            font.weight: Font.DemiBold
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            Layout.preferredWidth: (envScrollView.width - Style.marginL - 114 * Style.uiScaleRatio) * 0.4
          }
          NText {
            text: "Value"
            font.weight: Font.DemiBold
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
          }
          Item { Layout.preferredWidth: 32 } // Spacer for delete button
        }

        Repeater {
          model: root.envItems

          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NToggle {
              checked: modelData.enabled
              Layout.preferredWidth: 44 * Style.uiScaleRatio
              onToggled: function (isChecked) {
                if (modelData.enabled !== isChecked) {
                  modelData.enabled = isChecked;
                  root.save();
                }
              }
            }

            NButton {
              text: modelData.keyword || "env"
              Layout.preferredWidth: 70 * Style.uiScaleRatio
              onClicked: {
                modelData.keyword = (modelData.keyword === "envd") ? "env" : "envd";
                root.save();
              }
            }

            NTextInput {
              text: modelData.key
              placeholderText: "e.g. QT_QPA_PLATFORM"
              Layout.preferredWidth: (envScrollView.width - Style.marginL - 114 * Style.uiScaleRatio) * 0.4
              onEditingFinished: {
                if (modelData.key !== text) {
                  modelData.key = text;
                  root.save();
                }
              }
            }

            NTextInput {
              text: modelData.value
              placeholderText: "e.g. wayland"
              Layout.fillWidth: true
              onEditingFinished: {
                if (modelData.value !== text) {
                  modelData.value = text;
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
    }

    // Empty state
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.envItems.length === 0
      spacing: Style.marginM
      Layout.alignment: Qt.AlignCenter

      NText {
        text: "No environment variables defined yet."
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
