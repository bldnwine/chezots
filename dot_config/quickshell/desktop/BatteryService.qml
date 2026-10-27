import QtQuick
import Quickshell.Services.UPower

Item {
    id: service
    visible: false
    // Injectable for lifecycle tests; the display device aggregates laptop batteries.
    property var device: UPower.displayDevice
    readonly property bool ready: device !== null && device.ready
    readonly property bool present: device !== null && device.ready && device.isPresent && device.isLaptopBattery
    readonly property real percentage: device !== null && present ? Math.max(0, Math.min(100, Math.round(device.percentage * 100))) : 0
    readonly property real watts: device !== null && present && isFinite(device.changeRate) ? Math.abs(device.changeRate) : 0
    readonly property string state: {
        if (!device || !device.ready) return "Unknown";
        if (!present) return "AC";
        switch (device.state) {
        case UPowerDeviceState.Charging: return "Charging";
        case UPowerDeviceState.Discharging: return "Discharging";
        case UPowerDeviceState.FullyCharged: return "Full";
        case UPowerDeviceState.PendingCharge: return "Not charging";
        case UPowerDeviceState.PendingDischarge: return "Not charging";
        case UPowerDeviceState.Empty: return "Empty";
        default: return "Unknown";
        }
    }
}
