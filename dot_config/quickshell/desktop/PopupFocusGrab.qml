import QtQuick
import Quickshell.Hyprland
import "PopupFocusStack.js" as PopupFocusStack

// OnDemand lets Hyprland track the application on the current workspace;
// the grab keeps keyboard input in the popup until its window unmaps.
HyprlandFocusGrab {
    id: grab

    required property var window
    property bool ownsInput: false

    windows: [window]
    // Wait for the real window so rapid reopen cannot grab a retiring surface.
    active: ownsInput && window.backingWindowVisible
    property bool windowActive: window.contentItem.Window.active
    onWindowActiveChanged: {
        // Resume a popup uncovered by a newer popup, without taking focus
        // away from an application or an authentication dialog.
        if (ownsInput && windowActive && window.backingWindowVisible && !active)
            restoreBinding();
    }

    function restoreBinding() {
        active = Qt.binding(function() { return grab.ownsInput && grab.window.backingWindowVisible; });
    }

    Component.onCompleted: if (window.backingWindowVisible) PopupFocusStack.show(grab)
    Component.onDestruction: PopupFocusStack.hide(grab)

    property Connections windowConnection: Connections {
        target: grab.window
        function onBackingWindowVisibleChanged() {
            if (grab.window.backingWindowVisible) PopupFocusStack.show(grab);
            else PopupFocusStack.hide(grab);
        }
    }

    property Connections workspaceConnection: Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            // A newer popup or PolicyKit dialog may have replaced this grab.
            if (!grab.ownsInput || !grab.window.backingWindowVisible) return;
            // An empty workspace can clear keyboard focus even during a grab.
            // Recreate it after the switch so Escape and typing still reach us.
            grab.active = false;
            grab.restoreBinding();
        }
    }
}
