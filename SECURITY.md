# Security notes

TekVoice puts itself between a microphone and every app that listens to it.
This is a plain statement of what it runs, what it writes and where a
reviewer should look.

## What it touches

| component | privilege | notes |
|---|---|---|
| `bin/tekvoice` | none | POSIX `sh`. Spawns `pw-dump`, `pw-cli`, `pactl`, `python3` (inline scripts, arguments passed as argv) and, on `arm`, a second instance of the user's own `pipewire` binary running PipeWire's shipped `filter-chain.conf`. |
| `BarWidget.qml` / `Panel.qml` | shell | Run only `bin/tekvoice`, through `Process` with a fixed argument array (`[cli, verb, arg]`). Nothing goes through `bar.run()` or a shell. |
| `libtekvoice.so` | none | A LADSPA plugin loaded by that filter-chain process. It reads audio in, writes audio out, and does no file or network I/O. Buffers are allocated when the plugin is instantiated. |
| first-arm build | none | If no engine is installed, `arm` runs `make` in the plugin's own directory, writing only `build/`. No download: everything compiled is in the repo, and `ladspa.h` is vendored. |
| `install.sh` | none | Optional. Copies the engine to `~/.ladspa` and symlinks the plugin directory. Never uses `sudo`. |

## What it writes

- `$XDG_RUNTIME_DIR/tekvoice/`: the generated filter-chain config, a pidfile,
  a `key=value` state file, and the filter and build logs. It is gone at logout.
- `build/` inside the plugin directory.
- With `install.sh` only: `~/.ladspa/libtekvoice.so`.

It never touches system files, PipeWire or WirePlumber configuration, or the
default input device. Arming adds a source named `TekVoice`, and apps use it
only when the user selects it. The default source was checked before arming,
while armed, after a voice change, and after disarming: it stayed the same.
The optional hotkeys are a snippet in `hypr/tekvoice.lua` that the user appends
themselves.

## Inputs, and how they are checked

- **Voice ids** come from the repository's `voices.json`. `tekvoice set <id>`
  looks the id up in that file first and exits non-zero if it is unknown,
  before anything is written. The control values go to `pw-cli` as numbers
  formatted by Python, never as text the user supplied.
- **Strength** must match `^[0-9]+$` and be 100 or less.
- **The pidfile** holds the filter's pid *and* its kernel start time
  (`/proc/<pid>/stat` field 22), recorded at `arm`. It is trusted only if the
  live process still has that start time (a reused pid gets a new one), its
  `comm` is `pipewire`, its command line is exactly `pipewire -c
  filter-chain.conf`, and its environment carries TekVoice's private
  `PIPEWIRE_CONFIG_DIR`. The user's own PipeWire daemon fails all of these.
  Otherwise the filter counts as not running, and `disarm` kills nothing.
  `disarm` opens a pidfd on the pid first, re-checks the identity, and then
  signals through the pidfd, so the pid cannot be recycled between the check
  and the kill. There is no `/tmp` fallback: without `XDG_RUNTIME_DIR` the CLI
  refuses to run. `tests/test_pidfile.sh` plants a foreign process, a foreign
  process named `pipewire`, and a stale start time, and asserts each survives
  `disarm --force`; it also asserts the real filter identity is still stopped.

## What it never does

- Elevate privileges (no `sudo`, `pkexec`, setuid or polkit).
- Use the network.
- Record, store or send audio. Audio exists only inside the filter's
  real-time buffers.
- Install packages. Missing dependencies are reported with the `pacman`
  command to run, and the user runs it.

## Tests

`make test` runs offline and needs no sound card. It covers the DSP, the
shifter, the plugin ABI, the voice table, the widget model, the pidfile rules,
and a first-arm build from a clean `git ls-files` copy. `make test-cli` needs a
running PipeWire. It asserts that the microphone is never torn down during a
voice switch, a cycle or a panic.
