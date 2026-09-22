import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "VoiceModel.js" as VoiceModel

// Bar entry for TekVoice: a microphone glyph that shows, at a glance, whether
// you are currently disguised — and the panel that picks the voice.
//
// The widget owns the status polling rather than the panel, because the
// hotkeys and the glyph have to be correct whether or not the panel has ever
// been opened. The panel is created lazily; the widget is mounted all session.
BarWidget {
  id: root
  moduleName: "tiertek.tekvoice"

  readonly property string cli: Quickshell.env("HOME") + "/.config/omarchy/plugins/tiertek.tekvoice/bin/tekvoice"

  // ---------------------------------------------------------------- state

  property var status: VoiceModel.parseStatus("")
  property var voices: []

  readonly property bool armed: root.status.armed === true
  // `live` is the distinction that matters in the bar: armed only means the
  // device exists, live means a disguised voice is actually going out.
  readonly property bool live: root.status.live === true
  readonly property string voiceId: root.status.voice || ""
  readonly property string voiceName: VoiceModel.describe(root.voices, root.voiceId)
  readonly property string voiceColor: VoiceModel.tint(root.voices, root.voiceId) || ""

  // The voice table is data, so the widget never hard-codes a roster.
  FileView {
    id: voicesFile
    path: Quickshell.env("HOME") + "/.config/omarchy/plugins/tiertek.tekvoice/voices.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var doc = JSON.parse(voicesFile.text())
        root.voices = doc && doc.voices ? doc.voices : []
      } catch (e) {
        root.voices = []
      }
    }
  }

  // Polling, not events: PipeWire has no cheap "my filter-chain changed"
  // signal, and two seconds is well inside the time it takes a person to
  // notice. The widget also refreshes immediately after any action it takes.
  Process {
    id: statusProc
    command: [root.cli, "status"]
    stdout: StdioCollector {
      onStreamFinished: root.status = VoiceModel.parseStatus(this.text)
    }
  }

  function refresh() { if (!statusProc.running) statusProc.running = true }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---------------------------------------------------------------- actions

  // Every action goes through the CLI rather than talking to PipeWire here.
  // One implementation, one set of guarantees — the hotkeys, the panel and the
  // bar all get the same atomic single-write voice change.
  Process { id: actionProc; onExited: root.refresh() }

  function run(args) {
    if (actionProc.running) return
    actionProc.command = [root.cli].concat(args)
    actionProc.running = true
  }

  function arm()            { root.run(["arm"]) }
  function disarm()         { root.run(["disarm"]) }
  function setVoice(id)     { root.run(["set", id]) }
  function strength(n)      { root.run(["strength", String(n)]) }
  function panic()          { root.run(["panic"]) }
  function next()           { root.run(["next"]) }
  function prev()           { root.run(["prev"]) }

  // Arming and choosing in one gesture: clicking a voice while disarmed should
  // just work rather than making the user find the arm switch first.
  function pick(id) {
    if (!root.armed) root.run(["arm"])
    root.run(["set", id])
  }

  function open()   { if (panelLoader.item) panelLoader.item.open() }
  function close()  { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  // ---------------------------------------------------------------- panel

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // The keybind path — see hypr/tekvoice.lua.
  IpcHandler {
    target: "tiertek.tekvoice"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function panic(): void { root.panic() }
    function next(): void { root.next() }
    function prev(): void { root.prev() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    // U+F130 Nerd Font "microphone" when live, U+F131 "microphone-slash"
    // when your real voice is going out. The glyph alone answers the only
    // question that matters in a hurry: am I disguised right now?
    icon: root.live ? "" : ""

    // Tinted with the active voice's own colour while live, so a glance
    // distinguishes Quackers from Deep Six without opening anything.
    colorOverride: root.live ? root.voiceColor : ""

    // Dimmed, not hidden, when disarmed. A control surface that vanishes when
    // idle reads as a broken install.
    opacity: root.live ? 1.0 : 0.55

    tooltipText: root.live
      ? ("TekVoice: " + root.voiceName + (root.status.consumers > 0
          ? " — " + root.status.consumers + " app(s) listening" : ""))
      : (root.armed ? "TekVoice armed — your real voice is passing through"
                    : "TekVoice off")

    onClicked: root.toggle()
    // Middle click is panic. It is the one action worth being able to hit
    // without aiming, and it works whether or not the panel is open.
    onMiddleClicked: root.panic()
  }
}
