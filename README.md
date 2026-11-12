# Soundcore

An [Omarchy](https://omarchy.org/) shell plugin that adds a bar widget for
controlling Soundcore headphones and earbuds: sound mode (ANC/Transparency/
Normal), noise-canceling sub-mode, equalizer presets, a live 8-band custom
EQ, and whatever else OpenSCQ30 can change on your model, such as touch
controls, a volume limit, or auto power off.

## Install

```
omarchy plugin add https://github.com/osmanonurcan/omarchy-soundcore.git --enable
omarchy bar move io.github.osmanonurcan.soundcore --section right
```

Then connect your headphones over Bluetooth as usual and click the headphone
icon in the bar. If [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30), which
the plugin talks to your headphones through, isn't installed yet, the panel
offers to install it; your headphones are registered with it automatically.
[How it works](#how-it-works) has the details, and how to do either by hand.

If you have the original plugin this one started from
(`io.github.s-w-3.soundcore`) installed, remove it so you don't get two
widgets:

```
omarchy plugin remove io.github.s-w-3.soundcore
```

## Usage

Click the headphone icon in the bar. The panel shows whichever Soundcore
device is currently connected over Bluetooth:

- **Sound mode** — Normal / Transparency / Noise Canceling (options vary by
  model), with the settings that belong to the active mode under it: the
  noise canceling or transparency mode, their strength when set to Manual,
  and wind noise reduction, as your model offers them
- **Equalizer preset** — dropdown of the device's built-in presets
- **My EQ profiles** — save the current EQ under a name, switch between saved
  profiles, and delete them (OpenSCQ30 keeps these on your computer)
- **Custom EQ** — live sliders per band (click its title to show them);
  dragging one applies immediately and clears the active preset

Any other sound mode or equalizer setting OpenSCQ30 exposes for your model
shows up too, as buttons, a dropdown, a switch or a slider depending on its
type.

Below those, each other group of settings your model has gets a section of
its own that expands when you click its title -- on the Liberty 4 NC, for
example:

- **Touch controls** — what a single, double, triple or long tap on each
  earbud does (or nothing), and a reset to the defaults that takes a second
  click to confirm
- **Volume limit** — cap the volume, and how often it's checked
- **Other settings** — gaming mode, surround sound, sound leak compensation,
  auto play/pause, touch lock, tones and prompts, and auto power off
- **About** — firmware versions, serial number, and how the earbuds are
  linked

If no supported device is connected, or your specific model doesn't expose
any settings in OpenSCQ30, the panel says so plainly instead of showing empty
controls. If a change can't be applied or the settings can't be read (for
example because another OpenSCQ30 client, such as its GUI, is connected to
the headphones), the panel shows the reason.

## How it works

The plugin is a thin UI over [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30),
the open-source Soundcore control library/CLI for Linux. Whatever settings
OpenSCQ30 exposes for your specific model (sound modes, equalizer, touch
controls, battery, and so on) are what the panel shows — the widget reads the
device's capabilities at runtime rather than assuming a fixed feature set, so
it degrades gracefully on models with partial support (e.g. some earbuds only
expose battery level, no sound mode/EQ control) and picks up new capabilities
automatically as OpenSCQ30 adds them.

### OpenSCQ30

The plugin needs [`openscq30-cli`](https://aur.archlinux.org/packages/openscq30-cli-bin)
on `PATH`. Omarchy plugins can't install packages when they're added, so if
it's missing, the panel offers an **Install OpenSCQ30** button instead: it
opens a terminal running the command below, where you can enter your
password. To install it yourself:

```
omarchy pkg aur add openscq30-cli-bin
```

Prefer the `-bin` package unless you specifically need a newer version —
building `openscq30-cli` from source also compiles its GUI counterpart, which
is memory-heavy and can strain machines with limited RAM.

### Registering your headphones

Your headphones are paired over Bluetooth the normal way (`bluetoothctl` or
your system Bluetooth settings), but OpenSCQ30 also needs to know which model
they are. The plugin takes care of that: when a Soundcore device connects
that OpenSCQ30 doesn't know yet, it registers it under the model whose name
its Bluetooth name matches (e.g. "soundcore Liberty 4 NC" is
`SoundcoreA3947`). If the name matches no model, or more than one, the panel
says so, and you can register it yourself:

```
openscq30-cli list-models                     # find your model id
openscq30-cli paired-devices add \
  --mac-address AA:BB:CC:DD:EE:FF \
  --model SoundcoreXXXX
```

### Connections

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

## Credits

Started as a fork of
[s-w-3/omarchy-plugin-soundcore](https://github.com/s-w-3/omarchy-plugin-soundcore).

## License

MIT — see [LICENSE](LICENSE).
