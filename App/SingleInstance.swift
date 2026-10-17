// SingleInstance.swift — one Keystone per user (design spec E.8).
//
// The event tap is session-scoped, so two running copies would each transform
// every keystroke — producing doubled/garbled output. We take an exclusive
// advisory lock (flock) on a per-user file for the process's lifetime; a second
// instance that can't get the lock knows another copy is already running and
// bows out. This is what prevents "two `swift run` copies fighting over keys".

import Foundation

enum SingleInstance {
    // Held open for the whole process lifetime so the flock persists; the OS
    // releases it automatically when the process exits (even on crash).
    private nonisolated(unsafe) static var lockFD: Int32 = -1

    /// Returns true if this is the only instance (lock acquired). Returns false
    /// if another Keystone already holds the lock.
    @discardableResult
    static func acquire() -> Bool {
        tryAcquire()
    }

    /// Env var `AppModel.relaunch()` sets on the child it spawns. An env var
    /// rather than a launch argument: AppKit parses `-key value` arguments as
    /// UserDefaults overrides. Not inherited by apps started via LaunchServices.
    static let relaunchMarkerKey = "KEYSTONE_RELAUNCHED"

    /// True when this process was spawned by `AppModel.relaunch()`.
    static var launchedByRelaunch: Bool {
        ProcessInfo.processInfo.environment[relaunchMarkerKey] != nil
    }

    /// Like `acquire()`, but keeps retrying for up to `duration` seconds. For
    /// a relaunched child: the parent may not have exited (released its flock)
    /// yet. A genuine second copy must NOT get this grace, so only call it
    /// when `launchedByRelaunch`.
    static func acquire(retryingFor duration: TimeInterval, every interval: TimeInterval = 0.1) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while !tryAcquire() {
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: interval)
        }
        return true
    }

    private static func tryAcquire() -> Bool {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return true   // can't resolve a home dir → fail open, don't block startup
        }
        let dir = base.appendingPathComponent("com.tanta.keystone", isDirectory: true)
        // Best-effort: if this fails, the open() below fails and we fail open.
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockPath = dir.appendingPathComponent("instance.lock").path

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }              // couldn't open → fail open
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false                                // another instance holds it
        }
        lockFD = fd                                     // keep the fd (and the lock) alive
        return true
    }
}
