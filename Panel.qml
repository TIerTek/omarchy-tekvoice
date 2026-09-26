import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "VoiceModel.js" as VoiceModel

// The voice picker.
//
// The panel is a view: it holds no state beyond the keyboard cursor. Every
// action is delegated to the host widget, which delegates to the CLI, so the
// panel, the bar glyph and the hotkeys can never disagree about what is on air.
Panel {
  id: root
  moduleName: "tiertek.tekvoice"
  // The bar widget owns the IPC target: it is mounted for the whole session,
  // while this panel is created lazily and must not race it for the name.
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var barIdentity: hostWidget || root
  readonly property var voices: hostWidget ? hostWidget.voices : []
  readonly property string activeId: hostWidget ? hostWidget.voiceId : ""
  readonly property bool armed: hostWidget ? hostWidget.armed : false
  readonly property bool live: hostWidget ? hostWidget.live : false
  readonly property int strength: hostWidget ? hostWidget.status.strength : 100
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  readonly property int columns: 3
  readonly property int cellWidth: Style.space(150)
  readonly property int cellHeight: Style.space(64)

  // ---------------------------------------------------------------- cursor

  property bool cursorActive: false
  property int cursorIndex: 0

  function moveCursor(delta) {
    if (root.voices.length === 0) return
    var next = root.cursorIndex + delta
    root.cursorIndex = next < 0 ? 0
      : next > root.voices.length - 1 ? root.voices.length - 1 : next
  }

  function activateCursor() {
    if (root.voices.length === 0) return
    root.pick(root.voices[root.cursorIndex])
  }

  function pick(voice) {
    if (!voice || !root.hostWidget) return
    root.hostWidget.pick(voice.id)
    root.close()
  }

  // Typing 1-9 picks a voice outright, which is faster than arrowing to it.
  function activateNumber(t) {
    var n = parseInt(t, 10)
    if (isNaN(n) || n < 1 || n > root.voices.length) return
    root.pick(root.voices[n - 1])
  }

  onOpenedChanged: {
    if (!root.opened) { root.cursorActive = false; return }
    var index = 0
    for (var i = 0; i < root.voices.length; i++)
      if (root.voices[i].id === root.activeId) { index = i; break }
    root.cursorIndex = index
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keys
    // contentWidth is the card's OUTER width: padding and border come out of
    // it. KeyboardPanel exposes only the vertical inset; padding and border
    // are the same on every side, so it doubles as the horizontal one.
    contentWidth: panel.fittedContentWidth(
      root.columns * root.cellWidth + (root.columns - 1) * Style.space(8)
      + panel.verticalContentInset)
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.moveCursor(dx)
        else if (dy !== 0) root.moveCursor(dy * root.columns)
      }
      onActivateRequested: root.activateCursor()
      onReturnRequested: root.activateCursor()
      onTextKey: function(t) { root.activateNumber(t) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // States the truth plainly rather than making the user infer it from a
        // toggle position: "armed" and "actually disguised" are different.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.live ? "On air · " + VoiceModel.describe(root.voices, root.activeId)
              : (root.armed ? "Armed · your real voice is going out"
                            : "TekVoice is off")
          color: root.live ? Color.accent : Color.foreground
          opacity: root.live ? 1.0 : 0.6
          font.family: root.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        // The CLI's last error, e.g. a missing build dependency on first arm.
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: root.hostWidget ? root.hostWidget.lastError : ""
          color: Color.urgent
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.armed
            ?"Pick “TekVoice” as your microphone in Zoom, Discord, Meet or OBS. Press 1–9."
            : "Choose a voice to arm TekVoice and add its microphone."
          color: Color.foreground
          opacity: 0.45
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Grid {
          columns: root.columns
          spacing: Style.space(8)

          Repeater {
            model: root.voices

            delegate: Rectangle {
              required property var modelData
              required property int index

              width: root.cellWidth
              height: root.cellHeight
              radius: Style.space(6)

              readonly property bool isActive: root.live && modelData.id === root.activeId
              readonly property bool isCursor: root.cursorActive && index === root.cursorIndex

              color: isActive ? Qt.rgba(Qt.color(modelData.color).r,
                                        Qt.color(modelData.color).g,
                                        Qt.color(modelData.color).b, 0.20)
                              : Qt.rgba(Color.foreground.r, Color.foreground.g,
                                        Color.foreground.b, 0.06)
              border.width: isActive || isCursor ? 2 : 1
              border.color: isActive ? modelData.color
                          : isCursor ? Color.accent
                          : Qt.rgba(Color.foreground.r, Color.foreground.g,
                                    Color.foreground.b, 0.12)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: modelData.icon + "  " + (index + 1)
                  color: Color.foreground
                  opacity: 0.8
                  font.family: root.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: Color.foreground
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.blurb
                  color: Color.foreground
                  opacity: 0.45
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: root.pick(modelData)
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        // Strength pulls every voice back toward the user's real voice.
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: "Strength"
            color: Color.foreground
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }

          PanelSlider {
            id: strengthSlider
            bar: root.bar
            width: parent.width - Style.space(110)
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            value: root.strength
            // Applied on release, not on every drag tick: each change is a
            // PipeWire write, and dragging would otherwise fire dozens.
            onDraggingChanged: {
              if (!dragging && root.hostWidget)
                root.hostWidget.strength(Math.round(strengthSlider.liveValue))
            }
          }

          Text {
            textFormat: Text.PlainText
            text: Math.round(strengthSlider.liveValue) + "%"
            color: Color.foreground
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: root.armed ? "Disarm" : "Arm"
            bordered: true
            onClicked: {
              if (!root.hostWidget) return
              if (root.armed) root.hostWidget.disarm()
              else root.hostWidget.arm()
            }
          }

          // Panic never unloads the device — it sets the wet mix to zero, so
          // the far end hears your real voice within a buffer and their
          // microphone never disappears mid-call.
          Button {
            text: "Panic"
            bordered: true
            active: root.live
            onClicked: if (root.hostWidget) root.hostWidget.panic()
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Super+Alt+V panel · Super+Alt+Shift+V next · Super+Alt+X panic"
          color: Color.foreground
          opacity: 0.35
          font.family: root.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
