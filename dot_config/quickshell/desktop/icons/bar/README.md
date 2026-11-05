# Bar icon sources

- Files ending in `-symbolic.svg` are unmodified Adwaita symbolic icons by the
  [GNOME Project](https://www.gnome.org/), copied from the locally installed
  Adwaita icon theme. Upstream source: [GNOME/adwaita-icon-theme](https://gitlab.gnome.org/GNOME/adwaita-icon-theme).
  The upstream [license notice](LICENSE-Adwaita.txt) offers either LGPL 3 or
  CC BY-SA 3.0; the complete [LGPL 3](LICENSE-LGPL-3.0.txt) and its referenced
  [GPL 3](LICENSE-GPL-3.0.txt) are included here. The installed theme supplies
  `battery-level-100-charged-symbolic.svg` instead of a separate
  `battery-level-100-charging-symbolic.svg`.
- `audio-headphones-breeze.svg` and `network-wired-breeze.svg` are unmodified
  22px headphones and wired-network icons from
  [KDE Breeze Icons](https://invent.kde.org/frameworks/breeze-icons), copied from
  the installed `breeze/devices/22/audio-headphones.svg` and
  `breeze/status/22/network-wired-activated.svg`. Copyright © 2014
  Uri Herrera and others; LGPL 3 or later. Its upstream notice and license are
  included in [LICENSE-Breeze.txt](LICENSE-Breeze.txt).
- `audio-headphones-breeze-medium.svg` is a local adaptation of the Breeze
  headphones icon above, with a 0.35-unit outline added to its filled path for
  slightly heavier strokes. The same Breeze license applies.
- `network-wired-thin.svg` is a local adaptation of Adwaita’s filled three-node
  wired-network design, with 1.25-unit connectors and smaller filled nodes on a
  16px viewBox. The Adwaita attribution and license above apply.
- The remaining SVGs are [Google Material Symbols](https://github.com/google/material-design-icons/tree/master/symbols/web),
  Rounded, 20 px, default weight 400 and grade 0. They are distributed under
  the [Apache License 2.0](LICENSE-Material-Symbols.txt). Each file comes from
  `symbols/web/<name>/materialsymbolsrounded/<name>_20px.svg` in that repository.
