// Report the focused window and all app windows to blossomos-oom-focus, which
// makes the kernel OOM killer prefer unfocused apps. The daemon is D-Bus
// activated on the first call.

function report() {
    const active = workspace.activeWindow;
    const pids = [];
    for (const w of workspace.windowList()) {
        if (w.pid > 0 && (w.normalWindow || w.dialog) && pids.indexOf(w.pid) < 0) {
            pids.push(w.pid);
        }
    }
    callDBus("org.blossomos.OomFocus", "/org/blossomos/OomFocus",
             "org.blossomos.OomFocus", "Update",
             String(active && active.pid > 0 ? active.pid : 0),
             pids.join(","));
}

workspace.windowActivated.connect(report);
workspace.windowAdded.connect(report);
workspace.windowRemoved.connect(report);
report();
