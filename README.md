# Soundcore

An [Omarchy](https://omarchy.org/) shell plugin that adds a bar widget for
controlling Soundcore headphones and earbuds: sound mode (ANC/Transparency/
Normal), noise-canceling sub-mode, equalizer presets, and a live 8-band
custom EQ.

It's a thin UI over [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30), the
open-source Soundcore control library/CLI for Linux. Whatever settings
OpenSCQ30 exposes for your specific model (sound modes, equalizer, battery)
are what the panel shows — the widget reads the device's capabilities at
runtime rather than assuming a fixed feature set, so it degrades gracefully
on models with partial support (e.g. some earbuds only expose battery level,
no sound mode/EQ control) and picks up new capabilities automatically as
OpenSCQ30 adds them.

## Requirements

- [`openscq30-cli`](https://aur.archlinux.org/packages/openscq30-cli) (or
  `openscq30-cli-bin`) installed and on `PATH`. On Arch/Omarchy:
  ```
  omarchy pkg aur add openscq30-cli-bin
  ```
  Prefer the `-bin` package unless you specifically need a newer version —
  building `openscq30-cli` from source also compiles its GUI counterpart,
  which is memory-heavy and can strain machines with limited RAM.
- Your headphones paired over Bluetooth (`bluetoothctl` or your system
  Bluetooth settings) — normal OS-level pairing, separate from OpenSCQ30.
- Your device registered with OpenSCQ30 itself:
  ```
  openscq30-cli list-models                     # find your model id
  openscq30-cli paired-devices add \
    --mac-address AA:BB:CC:DD:EE:FF \
    --model SoundcoreXXXX
  ```

## Install

```
omarchy plugin add https://github.com/s-w-3/omarchy-plugin-soundcore.git --enable
omarchy bar move io.github.s-w-3.soundcore --section right
```

## Usage

Click the headphone icon in the bar. The panel shows whichever
OpenSCQ30-paired device is currently connected over Bluetooth:

- **Sound mode** — Normal / Transparency / Noise Canceling (options vary by
  model), with the settings that belong to the active mode under it: the
  noise canceling or transparency mode, their strength when set to Manual,
  and wind noise reduction, as your model offers them
- **Equalizer preset** — dropdown of the device's built-in presets
- **My EQ profiles** — save the current EQ under a name, switch between saved
  profiles, and delete them (OpenSCQ30 keeps these on your computer)
- **Custom EQ** — live sliders per band; dragging one applies immediately
  and clears the active preset

Any other sound mode or equalizer setting OpenSCQ30 exposes for your model
shows up too, as buttons, a dropdown, a switch or a slider depending on its
type.

If no supported device is connected, or your specific model doesn't expose
sound mode/EQ settings in OpenSCQ30, the panel says so plainly instead of
showing empty controls. If a change can't be applied or the settings can't be
read (for example because another OpenSCQ30 client, such as its GUI, is
connected to the headphones), the panel shows the reason.

OpenSCQ30 allows one connection to a device at a time, so the plugin only
connects to your headphones while the panel is open: to read their settings
when it opens and every 12 seconds after, and to apply your changes. While it
is closed, the bar icon just checks every 12 seconds whether they're connected
over Bluetooth.

## Development

The tests need `node`, `jq` and `flock` and use a fake `openscq30-cli`, so no
headphones are required:

```
node --test tests/
tests/scripts.test.sh
```

## License

MIT — see [LICENSE](LICENSE).
