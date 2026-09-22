import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Ui
import qs.Commons
import "VoiceModel.js" as VoiceModel

// The voice picker. A grid of tiles, a strength slider, an arm switch and a
// panic button.
//
// The panel is a view: it holds no state of its own beyond what is open. Every
// action is delegated to the host widget, which delegates to the CLI, so the
// panel and the hotkeys can never disagree about what is on air.
WidgetPanel {
  id: panel

  property var hostWidget: null
  readonly property var voices: hostWidget ? hostWidget.voices : []
  readonly property string activeId: hostWidget ? hostWidget.voiceId : ""
  readonly property bool armed: hostWidget ? hostWidget.armed : false
  readonly property bool live: hostWidget ? hostWidget.live : false

  contentItem: ColumnLayout {
    spacing: Style.marginM

    // ------------------------------------------------------------ header

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      StyledText {
        text: "TekVoice"
        font.pointSize: Style.fontSizeL
        font.bold: true
        Layout.fillWidth: true
      }

      // States the truth plainly rather than making the user infer it from a
      // toggle position: "armed" and "actually disguised" are different things.
      StyledText {
        text: panel.live ? "on air"
                         : (panel.armed ? "real voice" : "off")
        color: panel.live ? Style.accent : Style.textMuted
        font.pointSize: Style.fontSizeS
      }
    }

    StyledText {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      font.pointSize: Style.fontSizeS
      color: Style.textMuted
      text: panel.armed
        ? "Select “TekVoice” as your microphone in Zoom, Discord, Meet or OBS."
        : "Arm TekVoice to add a “TekVoice” microphone your apps can select."
    }

    // ------------------------------------------------------------ voices

    GridLayout {
      Layout.fillWidth: true
      columns: 3
      rowSpacing: Style.marginS
      columnSpacing: Style.marginS

      Repeater {
        model: panel.voices

        delegate: Rectangle {
          required property var modelData

          Layout.fillWidth: true
          Layout.preferredHeight: 74
          radius: Style.radiusS

          readonly property bool active: panel.live && modelData.id === panel.activeId

          color: active ? Qt.alpha(modelData.color, 0.22) : Style.surfaceAlt
          border.width: active ? 2 : 1
          border.color: active ? modelData.color : Style.border

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: 2

            StyledText {
              text: modelData.icon
              font.pointSize: Style.fontSizeL
            }
            StyledText {
              text: modelData.name
              font.bold: true
              font.pointSize: Style.fontSizeS
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: if (panel.hostWidget) panel.hostWidget.pick(modelData.id)
            ToolTip.visible: containsMouse
            ToolTip.text: modelData.blurb
            ToolTip.delay: 400
          }
        }
      }
    }

    // ------------------------------------------------------------ strength

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      StyledText {
        text: "Strength"
        font.pointSize: Style.fontSizeS
        color: Style.textMuted
      }

      StyledSlider {
        id: strengthSlider
        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 5
        value: panel.hostWidget ? panel.hostWidget.status.strength : 100
        // Only on release: each change is a PipeWire write, and dragging would
        // otherwise fire dozens of them.
        onPressedChanged: if (!pressed && panel.hostWidget)
          panel.hostWidget.strength(Math.round(value))
      }

      StyledText {
        text: Math.round(strengthSlider.value) + "%"
        font.pointSize: Style.fontSizeS
        color: Style.textMuted
      }
    }

    // ------------------------------------------------------------ actions

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      StyledButton {
        text: panel.armed ? "Disarm" : "Arm"
        Layout.fillWidth: true
        onClicked: {
          if (!panel.hostWidget) return
          if (panel.armed) panel.hostWidget.disarm()
          else panel.hostWidget.arm()
        }
      }

      // Panic never unloads the device — it sets the wet mix to zero, so the
      // far end hears your real voice within a buffer and their microphone
      // never disappears mid-call.
      StyledButton {
        text: "Panic"
        Layout.fillWidth: true
        enabled: panel.live
        highlighted: true
        onClicked: if (panel.hostWidget) panel.hostWidget.panic()
      }
    }

    StyledText {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      font.pointSize: Style.fontSizeS
      color: Style.textMuted
      text: "Super+Alt+V panel · Super+Alt+Shift+V next voice · Super+Alt+X panic"
    }
  }
}
