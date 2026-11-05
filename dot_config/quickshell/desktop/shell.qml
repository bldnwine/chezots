//@ pragma IconTheme breeze-dark
import QtQuick
import Quickshell
import Quickshell.Io

// Combined entry point: one Quickshell process hosting the navbar and
// the locus command palette. Both share the same Theme instance, so an
// omarchy theme swap propagates atomically to bar + popups + palette.
//
// Launch with:
//   qs -n -d -c desktop
ShellRoot {
    id: root

    ShellSettings { id: shellSettings }
    Theme { id: sharedTheme; settings: shellSettings }

    function openSettings() {
        locus.close();
        if (!settingsLoader.item) settingsLoader.setSource("SettingsWindow.qml", {theme: sharedTheme, settings: shellSettings});
        settingsLoader.item.open();
    }
    Loader { id: settingsLoader }
    IpcHandler {
        target: "settings"
        function open() { root.openSettings(); }
        function close() { if (settingsLoader.item) settingsLoader.item.requestClose(); }
        function toggle() {
            if (settingsLoader.item && settingsLoader.item.visible) settingsLoader.item.requestClose();
            else root.openSettings();
        }
    }

    Background {
        id: background
        theme: sharedTheme
    }

    PolkitAgent {
        id: polkitAgent
        theme: sharedTheme
    }

    Navbar {
        id: shellNavbar
        theme: sharedTheme
        onPaletteToggleRequested: locus.toggle()
    }
    Locus { id: locus; theme: sharedTheme; navbar: shellNavbar; settings: shellSettings; onSettingsRequested: root.openSettings() }
}
