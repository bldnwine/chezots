.pragma library

// Sentinel values for the search/state drills.
const fileCategory = "Files";
const favCategory = "Favourites";
const histCategory = "History";
const procCategory = "Processes";
const themeCategory = "Themes";

// fd already respects .gitignore, the global ignore file, and skips
// hidden files by default. These excludes catch build dirs that
// aren't always gitignored.
const fdExcludes = [
    "node_modules", "target", "dist", "build", ".cache",
    ".venv", "__pycache__", ".tox", ".next", ".nuxt"
];

const imageExts = [
    "png", "jpg", "jpeg", "webp", "gif", "bmp", "ico", "avif", "svg"
];

const textExts = [
    "md", "txt", "qml", "lua", "toml", "sh", "bash", "zsh", "fish",
    "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "json", "jsonc",
    "yaml", "yml", "rs", "go", "c", "h", "cpp", "hpp", "cc", "hh",
    "html", "css", "scss", "conf", "ini", "cfg", "log", "csv", "xml",
    "rb", "java", "kt", "swift", "php", "sql", "vim", "el", "tex",
    "gitignore", "gitconfig", "dockerfile", "makefile", "env"
];

const fileIcons = {
    "png": "󰋩", "jpg": "󰋩", "jpeg": "󰋩", "webp": "󰋩", "gif": "󰋩",
    "bmp": "󰋩", "ico": "󰋩", "avif": "󰋩", "svg": "󰜡", "tiff": "󰋩",
    "mp4": "󰕧", "mkv": "󰕧", "webm": "󰕧", "mov": "󰕧", "avi": "󰕧",
    "m4v": "󰕧", "flv": "󰕧",
    "mp3": "󰝚", "flac": "󰝚", "ogg": "󰝚", "wav": "󰝚", "m4a": "󰝚",
    "opus": "󰝚", "aac": "󰝚",
    "pdf": "󰈦", "epub": "󰂺", "djvu": "󰈦",
    "doc": "󰈬", "docx": "󰈬", "odt": "󰈬", "rtf": "󰈬",
    "xls": "󰈛", "xlsx": "󰈛", "ods": "󰈛",
    "ppt": "󰈧", "pptx": "󰈧", "odp": "󰈧",
    "zip": "󰗄", "tar": "󰗄", "gz": "󰗄", "xz": "󰗄", "bz2": "󰗄",
    "7z": "󰗄", "rar": "󰗄", "zst": "󰗄",
    "md": "󰍔", "txt": "󰈙", "log": "󰦪", "csv": "󰈛",
    "json": "󰘦", "jsonc": "󰘦", "yaml": "󰈙", "yml": "󰈙",
    "toml": "󰈙", "xml": "󰗀", "ini": "󰒓", "cfg": "󰒓",
    "conf": "󰒓", "env": "󰒓",
    "sh": "󱆃", "bash": "󱆃", "zsh": "󱆃", "fish": "󰈺",
    "lua": "󰢱", "vim": "",
    "html": "󰌝", "css": "󰌜", "scss": "󰌜", "sass": "󰌜",
    "py": "󰌠", "js": "󰌞", "mjs": "󰌞", "cjs": "󰌞",
    "ts": "󰛦", "tsx": "󰜈", "jsx": "󰜈",
    "rs": "󱘗", "go": "󰟓", "java": "󰬷", "kt": "󱈙",
    "swift": "󰛥", "rb": "󰴭", "php": "󰌟",
    "c": "󰙱", "h": "󰙱", "cpp": "󰙲", "hpp": "󰙲", "cc": "󰙲", "hh": "󰙲",
    "qml": "󰢫", "sql": "󰆼", "el": "", "tex": "",
    // Dotless filenames: fileExt() returns the whole lowercased name.
    "gitignore": "", "gitconfig": "",
    "dockerfile": "󰡨", "makefile": "󰣪"
};

// Synthetic rows at root level. Activating one sets the categoryFilter
// instead of executing a command. `target` matches against item.category;
// "App" is the bucket all .desktop entries land in. fileCategory
// routes to the fd file-search drill.
const categoryNav = [
    { title: "Quick",   icon: "󱎫", category: "Browse", isCategory: true, target: "Quick",       keywords: "quick settings panel tray toggle popup display weather calendar aether screenshots videos brightness volume mute" },
    { title: "Apps",    icon: "󰀻", category: "Browse", isCategory: true, target: "App",         keywords: "apps applications launcher programs software desktop" },
    { title: "Files",   icon: "󰉋", category: "Browse", isCategory: true, target: fileCategory,  keywords: "files file search find folder browse path open image picture document text fd" },
    { title: "Favourites", icon: "󰓎", category: "Browse", isCategory: true, target: favCategory,  keywords: "favourites favorites favs starred pinned bookmarks marked" },
    { title: "History", icon: "󰋚", category: "Browse", isCategory: true, target: histCategory,    keywords: "history recent recents log past activity used opened" },
    { title: "Style",   icon: "󰏘", category: "Browse", isCategory: true, target: "Style",       keywords: "style theme appearance look font background corners waybar screensaver" },
    { title: "System",  icon: "󰐥", category: "Browse", isCategory: true, target: "System",      keywords: "system lock suspend hibernate logout restart reboot shutdown power" },
    { title: "Toggle",  icon: "󰨚", category: "Browse", isCategory: true, target: "Toggle",      keywords: "toggle screensaver nightlight idle notifications bar layout gaps scaling sudo touchpad" },
    { title: "Trigger", icon: "󰚥", category: "Browse", isCategory: true, target: "Trigger",     keywords: "trigger reminder transcode capture share toggle hardware" },
    { title: "Capture", icon: "󰄀", category: "Browse", isCategory: true, target: "Capture",     keywords: "capture screenshot screenrecord ocr text extraction color picker" },
    { title: "Share",   icon: "󰒖", category: "Browse", isCategory: true, target: "Share",       keywords: "share clipboard file folder receive localsend send transfer" },
    { title: "Learn",   icon: "󰂺", category: "Browse", isCategory: true, target: "Learn",       keywords: "learn docs manual help keybindings wiki cheatsheet" },
    { title: "Processes", icon: "󰍛", category: "Browse", isCategory: true, target: procCategory,  keywords: "processes process kill task manager ps top htop activity cpu memory" },
    { title: "Themes",    icon: "󰸌", category: "Browse", isCategory: true, target: themeCategory, keywords: "themes theme palette color swatch switcher dark light apply" }
];

// Every leaf action omarchy-menu can dispatch is flattened here with a
// synonym list so search hits non-obvious terms. `exec` is the bash run
// verbatim; `tui` (when set) is the wrapper command name that prefixes
// exec so the launch lands in a real terminal.
const omarchyItems = [
    // ----- Quick -----
    // Mirrors the standalone QuickSettings sheet's targets: popup togglers
    // and one-shot device toggles. Reached as a drill-down (Quick) or by
    // typing the action name; Alt+Space binds straight into this category.
    { title: "Display",          icon: "󰍹", category: "Quick", keywords: "display monitor brightness warmth gamma night light blue temperature dim screen",       exec: "qs -c desktop ipc call display toggle" },
    { title: "Weather",          icon: "󰖐", category: "Quick", keywords: "weather forecast temperature wttr rain sun wind humidity uv sunrise sunset outdoor",    exec: "qs -c desktop ipc call weather toggle" },
    { title: "Calendar",         icon: "󰃭", category: "Quick", keywords: "calendar date month day today schedule planner agenda holidays",                       exec: "qs -c desktop ipc call calendar toggle" },
    { title: "Aether Themes",    icon: "󰏘", category: "Quick", keywords: "aether theme blueprint palette swatch picker wallpaper generate",                      exec: "qs -c desktop ipc call aether toggle" },
    { title: "Screenshots",      icon: "󰄀", category: "Quick", keywords: "screenshots shots browse pictures captures images recent gallery",                      exec: "qs -c desktop ipc call screenshots toggle" },
    { title: "Videos",           icon: "󰟞", category: "Quick", keywords: "videos films clips recordings recent browse gallery library",                          exec: "qs -c desktop ipc call videos toggle" },
    { title: "Mute Audio",       icon: "󰝟", category: "Quick", keywords: "mute audio unmute silence toggle volume sound speaker pamixer quick",                  exec: "pamixer -t" },
    { title: "Reset Display",    icon: "󰜉", category: "Quick", keywords: "reset display brightness warmth gamma default daylight identity full restore",          exec: "qs -c desktop ipc call display reset" },
    { title: "Blank Screen",     icon: "󰹐", category: "Quick", keywords: "blank screen off dpms suspend display monitor sleep dark",                              exec: "qs -c desktop ipc call display blank" },
    { title: "Refresh Weather",  icon: "󰜉", category: "Quick", keywords: "weather refresh reload update wttr fetch",                                              exec: "qs -c desktop ipc call weather refresh" },
    { title: "Audio Mixer",      icon: "󰕾", category: "Quick", keywords: "audio mixer pavucontrol pipewire pulse volume sink source device level",                exec: "omarchy-launch-audio" },
    { title: "Wi-Fi Picker",     icon: "󰖩", category: "Quick", keywords: "wifi wireless network connect picker chooser ssid signal nmcli",                       exec: "omarchy-launch-wifi" },
    { title: "Bluetooth Picker", icon: "󰂯", category: "Quick", keywords: "bluetooth bt pair connect device picker headset speaker keyboard mouse",                exec: "omarchy-launch-bluetooth" },
    { title: "System Monitor",   icon: "󰍛", category: "Quick", keywords: "cpu memory process monitor btop top htop performance load activity",                   exec: "omarchy-launch-or-focus-tui btop" },
    { title: "Power Menu",       icon: "󰐥", category: "Quick", keywords: "power menu battery suspend hibernate logout restart reboot shutdown lock",              exec: "omarchy-menu power" },

    // ----- Style -----
    { title: "Aether Menu",      icon: "󰸌", category: "Style",   keywords: "aether theme blueprint palette swatch picker wallpaper generate full menu launcher",                  exec: "qs -c desktop ipc call aether toggle" },
    { title: "Round Corners",    icon: "󰘇", category: "Style",   keywords: "corners radius round soft rounded border edge shape navbar cloud popup",                              exec: "qs -c desktop ipc call corners round" },
    { title: "Sharp Corners",    icon: "󰝣", category: "Style",   keywords: "corners radius sharp square hard flat border edge shape navbar slab popup",                            exec: "qs -c desktop ipc call corners sharp" },

    // ----- System -----
    { title: "Lock Screen",         icon: "󰌾", category: "System", keywords: "lock screen security hyprlock password",                                            exec: "loginctl lock-session" },
    { title: "Force Screensaver",   icon: "󱄄", category: "System", keywords: "screensaver force start show idle",                                              exec: "omarchy-launch-screensaver force" },
    { title: "Suspend",             icon: "󰒲", category: "System", keywords: "suspend sleep power down ram s3",                                                 exec: "systemctl suspend" },
    { title: "Hibernate",           icon: "󰤁", category: "System", keywords: "hibernate disk power down s4 swap",                                               exec: "systemctl hibernate" },
    { title: "Logout",              icon: "󰍃", category: "System", keywords: "logout signout exit session end",                                                  exec: "uwsm stop" },
    { title: "Restart Computer",    icon: "󰜉", category: "System", keywords: "restart reboot reset power cycle",                                                exec: "systemctl reboot" },
    { title: "Shutdown",            icon: "󰐥", category: "System", keywords: "shutdown poweroff off halt turn off",                                              exec: "systemctl poweroff" },

    // ----- Toggle -----
    { title: "Toggle Screensaver",  icon: "󱄄", category: "Toggle", keywords: "toggle screensaver enable disable on off",                                        exec: "omarchy-toggle-screensaver" },
    { title: "Toggle Nightlight",   icon: "󰔎", category: "Toggle", keywords: "toggle nightlight blue light filter warm color temperature hyprsunset",            exec: "omarchy-toggle-nightlight" },
    { title: "Toggle Idle Lock",    icon: "󱫖", category: "Toggle", keywords: "toggle idle lock auto away timeout",                                                exec: "omarchy-toggle-idle" },
    { title: "Toggle Notifications",icon: "󰂛", category: "Toggle", keywords: "toggle notifications silence mute mako dnd",                                       exec: "omarchy-toggle-notification-silencing" },
    { title: "Toggle Top Bar",      icon: "󰍜", category: "Toggle", keywords: "toggle waybar top bar show hide visibility",                                       exec: "omarchy-toggle-waybar" },
    { title: "Toggle Workspace Layout", icon: "󱂬", category: "Toggle", keywords: "toggle workspace layout dwindle master tile hyprland",                          exec: "omarchy-hyprland-workspace-layout-toggle" },
    { title: "Toggle Window Gaps",  icon: "󱂩", category: "Toggle", keywords: "toggle gaps window spacing hyprland margin",                                       exec: "omarchy-hyprland-window-gaps-toggle" },
    { title: "Toggle 1-Window Ratio",icon: "󰋃", category: "Toggle", keywords: "toggle aspect ratio single window square",                                          exec: "omarchy-hyprland-window-single-square-aspect-toggle" },
    { title: "Toggle Monitor Scaling", icon: "󰍹", category: "Toggle", keywords: "toggle monitor scaling cycle resolution hidpi",                                  exec: "omarchy-hyprland-monitor-scaling-cycle" },
    { title: "Toggle Direct Boot",  icon: "󰓅", category: "Toggle", keywords: "toggle direct boot autologin no password",                                          exec: "omarchy-config-direct-boot", tui: "omarchy-launch-floating-terminal-with-presentation" },
    { title: "Toggle Passwordless Sudo", icon: "󰟵", category: "Toggle", keywords: "passwordless sudo nopasswd root admin security",                               exec: "omarchy-sudo-passwordless",  tui: "omarchy-launch-floating-terminal-with-presentation" },
    { title: "Toggle Suspend",      icon: "󰒲", category: "Toggle", keywords: "toggle suspend disable enable sleep power",                                        exec: "omarchy-toggle-suspend" },
    { title: "Toggle Touchpad",     icon: "󰟸", category: "Toggle", keywords: "toggle touchpad trackpad enable disable",                                          exec: "omarchy-toggle-touchpad" },
    { title: "Toggle Touchscreen",  icon: "󰆽", category: "Toggle", keywords: "toggle touchscreen enable disable",                                                exec: "omarchy-toggle-touchscreen" },

    // ----- Capture -----
    { title: "Screenshot",          icon: "󰄀", category: "Capture", keywords: "screenshot screen capture image png shot snip print",                              exec: "omarchy-capture-screenshot" },
    { title: "Screen Record",       icon: "󰑊", category: "Capture", keywords: "screen record video capture mp4 gif",                                              exec: "omarchy-capture-screenrecording" },
    { title: "Text Extraction (OCR)",icon: "󰴑", category: "Capture", keywords: "ocr text extract recognize image scan copy",                                       exec: "omarchy-capture-text-extraction" },
    { title: "Color Picker",        icon: "󰃉", category: "Capture", keywords: "color picker hex rgb hyprpicker dropper sample eyedropper",                        exec: "bash -c 'pkill hyprpicker || hyprpicker -a'" },
    { title: "Notes",               icon: "󰍔", category: "Capture", keywords: "notes note markdown scratchpad journal nvim neovim editor write text omni-notes",  exec: "bash -c 'mkdir -p \"$HOME/Documents/omni-notes\" && cd \"$HOME/Documents/omni-notes\" && nvim .'", tui: "omarchy-launch-tui" },

    // ----- Share -----
    { title: "Share Clipboard",     icon: "󰅎", category: "Share",   keywords: "share clipboard localsend send transfer",                                          exec: "omarchy-menu-share clipboard" },
    { title: "Share File",          icon: "󰈤", category: "Share",   keywords: "share file send transfer localsend",                                                exec: "omarchy-menu-share file",   tui: "omarchy-launch-tui" },
    { title: "Share Folder",        icon: "󰉒", category: "Share",   keywords: "share folder directory send transfer localsend",                                    exec: "omarchy-menu-share folder", tui: "omarchy-launch-tui" },
    { title: "Receive (LocalSend)", icon: "󰥦", category: "Share",   keywords: "receive localsend share airdrop transfer",                                          exec: "uwsm-app -- localsend" },

    // ----- Trigger -----
    { title: "Set Reminder",        icon: "󰔛", category: "Trigger", keywords: "reminder alarm timer notify wake notification",                                    exec: "omarchy-menu reminder-set" },
    { title: "Show Reminders",      icon: "󰔛", category: "Trigger", keywords: "reminders show list pending",                                                       exec: "omarchy-reminder show" },
    { title: "Clear Reminders",     icon: "󰔛", category: "Trigger", keywords: "reminders clear delete remove all",                                                 exec: "omarchy-reminder clear" },
    { title: "Transcode Media",     icon: "󰧸", category: "Trigger", keywords: "transcode media video audio convert compress mp4 mp3",                              exec: "omarchy-transcode" },

    // ----- Learn -----
    { title: "Keybindings",         icon: "󰌌", category: "Learn", keywords: "keybindings shortcuts hotkeys cheatsheet reference help",                              exec: "omarchy-menu-keybindings" },
    { title: "Tmux Keybindings",    icon: "󱂬", category: "Learn", keywords: "tmux keybindings shortcuts reference",                                                 exec: "omarchy-menu-tmux-keybindings" },
    { title: "Omarchy Manual",      icon: "󰂺", category: "Learn", keywords: "omarchy manual docs documentation help learn",                                         exec: "omarchy-launch-webapp 'https://learn.omacom.io/2/the-omarchy-manual'" },
    { title: "Hyprland Wiki",       icon: "󱁉", category: "Learn", keywords: "hyprland wiki docs documentation help",                                                exec: "omarchy-launch-webapp 'https://wiki.hypr.land/'" },
    { title: "Arch Wiki",           icon: "󰣇", category: "Learn", keywords: "arch wiki docs documentation help linux",                                              exec: "omarchy-launch-webapp 'https://wiki.archlinux.org/title/Main_page'" },
    { title: "Neovim Keymaps",      icon: "󰕷", category: "Learn", keywords: "neovim nvim keymaps shortcuts lazyvim reference",                                      exec: "omarchy-launch-webapp 'https://www.lazyvim.org/keymaps'" },
    { title: "Bash Cheatsheet",     icon: "󱆃", category: "Learn", keywords: "bash shell cheatsheet reference scripting",                                            exec: "omarchy-launch-webapp 'https://devhints.io/bash'" }
];

// Pre-lowercases `title`/`keywords`/`category` onto `_t`/`_k`/`_c` so the
// per-keystroke scoring loop doesn't re-lowercase the same strings on
// every character.
function annotate(items) {
    const out = new Array(items.length);
    for (let i = 0; i < items.length; i++) {
        const it = items[i];
        out[i] = Object.assign({}, it, {
            _t: (it.title || "").toLowerCase(),
            _k: (it.keywords || "").toLowerCase(),
            _c: (it.category || "").toLowerCase()
        });
    }
    return out;
}

function basename(p) {
    const s = p.lastIndexOf("/");
    return s >= 0 ? p.substring(s + 1) : p;
}
function dirname(p) {
    const s = p.lastIndexOf("/");
    return s >= 0 ? p.substring(0, s) : "";
}
function tildify(p, homeDir) {
    return (homeDir && p.indexOf(homeDir) === 0)
        ? "~" + p.substring(homeDir.length)
        : p;
}
function fileExt(path) {
    const name = basename(path);
    const dot = name.lastIndexOf(".");
    if (dot <= 0) return name.toLowerCase(); // dotless name (Makefile)
    return name.substring(dot + 1).toLowerCase();
}
function fileIcon(path) {
    return fileIcons[fileExt(path)] || "";
}
function openUrl(url) {
    return "xdg-open " + JSON.stringify(url);
}
function formatStars(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "m";
    if (n >= 1000)    return (n / 1000).toFixed(1) + "k";
    return "" + n;
}

// Stable identity per item — path wins (files, repos, PRs), exec next
// (apps, omarchy actions), title+category last (synthetic rows).
function itemKey(item) {
    if (!item) return "";
    return item.path || item.exec || (item.title + "|" + item.category);
}
