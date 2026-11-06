//
//  ScriptRunner.swift
//  SpiderNotch
//
//  Runs small AppleScripts (Apple Events) to talk to Music, Spotify and web
//  browsers: "what's playing", "next track", "show this tab"...
//
//  Each script runs in Apple's /usr/bin/osascript as a separate little
//  process, with a time limit, so a busy app can never freeze SpiderNotch.
//
//  macOS asks you once per app before SpiderNotch may control it
//  ("SpiderNotch wants access to control Spotify"). SpiderNotch only asks when
//  you do something that needs it (like clicking the song to open it), never
//  just because you hovered the notch.
//

import AppKit
import CoreServices

enum ScriptError: Error {
    /// You haven't allowed SpiderNotch to control that app (System Settings → Privacy & Security → Automation).
    case notAllowed
    /// The browser's "Allow JavaScript from Apple Events" option is off.
    case javaScriptOff
    case notRunning
    case timedOut
    case failed(String)
}

/// Holds bytes read on another thread.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum AutomationPermission: Equatable {
    case granted
    case notAsked
    case denied
    case appNotRunning
    case unknown
}

enum ScriptRunner {
    /// Runs an AppleScript off the main thread. `completion` runs on the main actor.
    static func run(_ source: String, timeout: TimeInterval = 4,
                    completion: @escaping @MainActor (Result<String, ScriptError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runNow(source, timeout: timeout)
            Task { @MainActor in
                completion(result)
            }
        }
    }

    /// Runs an AppleScript and waits for it (call only from a background thread).
    static func runNow(_ source: String, timeout: TimeInterval) -> Result<String, ScriptError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        try? input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
        try? input.fileHandleForWriting.close()

        // Read the answer while the script runs (a long answer would otherwise fill
        // the pipe and make the script wait forever).
        let outputBox = DataBox()
        let errorBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.data = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.data = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return .failure(.timedOut)
        }
        let text = String(data: outputBox.data, encoding: .utf8) ?? ""
        let problem = String(data: errorBox.data, encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
            return .success(text.trimmingCharacters(in: .newlines))
        }
        return .failure(classify(problem))
    }

    private static func classify(_ message: String) -> ScriptError {
        if message.contains("-1743") || message.contains("Not authorized") {
            return .notAllowed
        }
        if message.contains("JavaScript") && (message.contains("turned off") || message.contains("Allow JavaScript")) {
            return .javaScriptOff
        }
        if message.contains("-600") || message.contains("isn’t running") || message.contains("isn't running") {
            return .notRunning
        }
        return .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Makes text safe to put inside "quotes" in an AppleScript.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Permission (System Settings → Privacy & Security → Automation)

    /// Asks macOS whether SpiderNotch may control an app, without showing any prompt.
    static func permission(for bundleID: String) -> AutomationPermission {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return .appNotRunning
        }
        return check(bundleID: bundleID, ask: false)
    }

    /// Shows macOS's "SpiderNotch wants to control …" prompt if it hasn't been answered yet.
    /// Waits for your answer, so call it from a background thread.
    static func requestPermission(for bundleID: String) -> AutomationPermission {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return .appNotRunning
        }
        return check(bundleID: bundleID, ask: true)
    }

    private static func check(bundleID: String, ask: Bool) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let address = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(address, AEEventClass(typeWildCard),
                                                           AEEventID(typeWildCard), ask)
        switch Int(status) {
        case Int(noErr):
            return .granted
        case Int(errAEEventWouldRequireUserConsent):
            return .notAsked
        case Int(errAEEventNotPermitted):
            return .denied
        case Int(procNotFound):
            return .appNotRunning
        default:
            return .unknown
        }
    }
}
