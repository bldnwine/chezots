import QtQuick
import "Data.js" as Data

// Surfaces the navbar's popup widgets (weather/display/calendar under
// Toggle) as palette rows. Since the
// merge into a single shell they're always registered, so the list is
// static; no IPC probe needed.
Item {
    id: navbarApps

    readonly property var candidates: [
        { target: "weather",     title: "Weather",     icon: "󰖐", category: "Toggle",
          keywords: "weather forecast temperature rain sun wind cloud wttr" },
        { target: "display",     title: "Display",     icon: "󰍹", category: "Toggle",
          keywords: "display brightness warmth gamma night light monitor screen panel" },
        { target: "calendar",    title: "Calendar",    icon: "󰃭", category: "Toggle",
          keywords: "calendar date month day year week schedule planner today" },
        { target: "system",      title: "System",      icon: "󰍛", category: "Toggle",
          keywords: "system cpu memory mem load pressure btop process monitor" },
        { target: "bar",         title: "Toggle Bar Visibility", icon: "󰍜", category: "Toggle", verb: "toggle",
          keywords: "bar visibility show hide navbar variant style toggle hidden clear unobscured unobstruct" }
    ]

    readonly property var items: Data.annotate(candidates.map(c => ({
        title: c.title,
        icon: c.icon,
        category: c.category,
        keywords: c.keywords,
        exec: "qs -c desktop ipc call " + c.target + " " + (c.verb || "open")
    })))

    // Kept for callers that still nudge a refresh — now a no-op.
    function probe() {}
}
