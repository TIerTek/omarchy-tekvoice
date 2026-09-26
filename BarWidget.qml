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
    printErrors: false
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
  //
  // Commands run one at a time through a queue (see VoiceModel.enqueue for why
  // a plain "skip if running" guard lost the first of two same-tick commands).
  // The CLI's own error is kept and shown, so a failed arm is not silent.
  property var queue: []
  property bool busy: false
  property var lastExit: null
  property string lastError: ""

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr }
    onExited: function(exitCode) { root.lastExit = exitCode }
    // Pumped from `running`, not `exited`: a command that fails to start
    // never emits exited, and would otherwise wedge the queue for good.
    onRunningChanged: if (!running && root.busy) root.finished()
  }

  function finished() {
    var code = root.lastExit
    if (code === 0) root.lastError = ""
    else if (code === null) root.lastError = "could not run " + root.cli
    else root.lastError = VoiceModel.errorText(actionErr.text)
    root.queue = VoiceModel.afterExit(root.queue, code)
    root.busy = false
    root.refresh()
    root.pump()
  }

  function pump() {
    if (root.busy || root.queue.length === 0) return
    root.busy = true
    root.lastExit = null
    actionProc.command = root.queue[0]
    root.queue = root.queue.slice(1)
    actionProc.running = true
  }

  function run(args) {
    root.queue = VoiceModel.enqueue(root.queue, [root.cli].concat(args))
    root.pump()
  }

  function arm()            { root.run(["arm"]) }
  function disarm()         { root.run(["disarm"]) }
  function setVoice(id)     { root.run(["set", id]) }
  function strength(n)      { root.run(["strength", String(n)]) }
  function panic()          { root.run(["panic"]) }
  function next()           { root.run(["next"]) }
  function prev()           { root.run(["prev"]) }
  function cycleVoice(dir)  { if (dir < 0) root.prev(); else root.next() }

  // Arming and choosing in one gesture: clicking a voice while disarmed should
  // just work rather than making the user find the arm switch first. Arm is
  // queued unconditionally: `status` is polled, so `armed` can be two seconds
  // stale, and arming an armed TekVoice is a cheap no-op.
  function pick(id) {
    root.run(["arm"])
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

    // U+F130 Nerd Font "microphone", U+F131 "microphone-slash". The glyph
    // alone answers the only question that matters in a hurry: am I disguised
    // right now? Verify any replacement by actually rendering it — a sibling
    // plugin shipped a glyph that turned out to be a weather icon.
    text: root.live ? "\uF130 " + root.voiceName : "\uF131"

    active: root.live
    dimmed: !root.armed

    tooltipText: {
      if (root.lastError) return "TekVoice · " + root.lastError
      if (root.busy) return "TekVoice · working…"
      if (!root.armed) return "TekVoice off"
      if (!root.live) return "TekVoice armed \u00b7 your real voice is passing through"
      var t = "TekVoice \u00b7 " + root.voiceName
      if (root.status.consumers > 0)
        t += " \u00b7 " + root.status.consumers + " app(s) listening"
      return t
    }

    onPressed: function(mouseButton) {
      // Middle is panic. It is the one action worth being able to hit without
      // aiming, and it works whether or not the panel is open.
      if (mouseButton === Qt.MiddleButton) root.panic()
      else if (mouseButton === Qt.RightButton) root.next()
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.cycleVoice(delta > 0 ? -1 : 1) }
  }
}
