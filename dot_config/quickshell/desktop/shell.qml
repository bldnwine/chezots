//@ pragma IconTheme breeze-dark
import QtQuick
import Quickshell

// Combined entry point: one Quickshell process hosting the navbar and
// the locus command palette. Both share the same Theme instance, so an
// omarchy theme swap propagates atomically to bar + popups + palette.
//
// Launch with:
//   qs -n -d -c desktop
ShellRoot {
    id: root

    Theme { id: theme }

    Background {
        id: background
        theme: theme
    }

    PolkitAgent {
        id: polkitAgent
        theme: theme
    }

    Navbar {
        id: nav
        theme: theme
        onPaletteToggleRequested: locus.toggle()
    }
    Locus { id: locus; theme: theme; navbar: nav }
}
