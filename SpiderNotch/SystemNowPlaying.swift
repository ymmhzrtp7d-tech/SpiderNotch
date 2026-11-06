//
//  SystemNowPlaying.swift
//  SpiderNotch
//
//  Reads macOS's system-wide "Now Playing" information (what Control Center
//  shows) through the small helper in MediaHelper/, and sends it play, pause,
//  next, previous and seek commands. This covers Music, Spotify, Safari,
//  Chrome, Edge, Brave, Firefox, Podcasts, TV, VLC, IINA and any other app
//  that tells macOS what it's playing.
//
//  Why a helper: Apple's public MediaPlayer APIs (MPNowPlayingInfoCenter,
//  MPRemoteCommandCenter) only let an app publish its *own* playback, and
//  macOS 15.4+ only answers Apple's own programs when asked what other apps
//  play. So the helper runs inside Apple's /usr/bin/perl (see now-playing.pl).
//  If a future macOS closes that door, SpiderNotch keeps working with its
//  direct Music, Spotify and browser integrations instead.
//

import AppKit

/// One reading of the system Now Playing information.
struct SystemNowPlayingInfo {
    var bundleID: String?
    var parentBundleID: String?
    var title: String
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var rate: Double
    var timestamp: Date
    var isPlaying: Bool
    var artwork: NSImage?
    var artworkHash: String
    var uid: String?

    /// The app that's playing (for websites, the browser rather than its helper process).
    var appBundleID: String? {
        if let parent = parentBundleID, !parent.isEmpty {
            return parent
        }
        return bundleID
    }
}

@MainActor
final class SystemNowPlaying {
    enum Status: Equatable {
        case starting
        case working
        case unavailable(String)
    }

    enum Command: String {
        case toggle, play, pause, next, previous
    }

    private(set) var status = Status.starting
    private(set) var info: SystemNowPlayingInfo?
    /// True once the helper has reported real media at least once (proof it works on this Mac).
    private(set) var hasSeenMedia = false
    var onChange: (@MainActor () -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var artworkCache: (hash: String, image: NSImage)?
    private var quickFailures = 0
    private var startedAt = Date.distantPast
    private var stopped = false

    // MARK: - Starting the helper

    func start() {
        stopped = false
        launch()
    }

    func stop() {
        stopped = true
        if let input = input {
            try? input.write(contentsOf: Data("quit\n".utf8))
            try? input.close()
        }
        process?.terminate()
        process = nil
        input = nil
    }

    private func launch() {
        guard !stopped else { return }
        guard let files = prepareHelperFiles() else {
            setStatus(.unavailable("The Now Playing helper isn't included in this copy of SpiderNotch."))
            return
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
            setStatus(.unavailable("This version of macOS doesn't include /usr/bin/perl."))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [files.script.path, files.library.path]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                self?.received(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData // keep the pipe from filling up
        }
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in
                self?.helperExited(code: code)
            }
        }

        do {
            try process.run()
        } catch {
            setStatus(.unavailable("The Now Playing helper couldn't start: \(error.localizedDescription)"))
            return
        }
        self.process = process
        input = stdinPipe.fileHandleForWriting
        startedAt = Date()
    }

    /// Copies the helper out of the app into Application Support before running it.
    /// (A downloaded app's files carry a "quarantine" tag, which can stop
    /// another program from loading them. Our own copy has no such tag.)
    private func prepareHelperFiles() -> (script: URL, library: URL)? {
        let bundle = Bundle.main
        let bundledLibrary = bundle.privateFrameworksURL?.appendingPathComponent("SpiderNotchMedia.dylib")
        guard let library = bundledLibrary, FileManager.default.fileExists(atPath: library.path),
              let script = bundle.url(forResource: "now-playing", withExtension: "pl")
        else { return nil }

        let folder = AppInfo.supportFolder.appendingPathComponent("Helper", isDirectory: true)
        let copiedScript = folder.appendingPathComponent("now-playing.pl")
        let copiedLibrary = folder.appendingPathComponent("SpiderNotchMedia.dylib")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (from, to) in [(script, copiedScript), (library, copiedLibrary)] {
                let data = try Data(contentsOf: from)
                let existing = try? Data(contentsOf: to)
                if existing != data {
                    try? FileManager.default.removeItem(at: to)
                    try data.write(to: to, options: .atomic)
                }
            }
            return (copiedScript, copiedLibrary)
        } catch {
            return (script, library)
        }
    }

    private func helperExited(code: Int32) {
        process = nil
        input = nil
        guard !stopped else { return }
        let ranFor = Date().timeIntervalSince(startedAt)
        if code == 3 {
            setStatus(.unavailable("macOS didn't allow reading Now Playing on this version."))
            return
        }
        if ranFor < 5 {
            quickFailures += 1
        } else {
            quickFailures = 0
        }
        if quickFailures >= 4 {
            setStatus(.unavailable("The Now Playing helper keeps stopping on this Mac."))
            return
        }
        // Try again in a moment (a little longer each time).
        let delay = UInt64(min(30, 2 * (quickFailures + 1))) * 1_000_000_000
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            self?.launch()
        }
    }

    // MARK: - Reading what it says

    private func received(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: line)
        }
        if buffer.count > 8_000_000 {
            buffer.removeAll() // something went wrong; start fresh
        }
    }

    private func handle(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String
        else { return }
        switch type {
        case "ready":
            if status != .working {
                setStatus(.working)
            }
        case "error":
            let message = object["message"] as? String ?? "unknown problem"
            setStatus(.unavailable(message))
        case "info":
            if let dictionary = object["info"] as? [String: Any] {
                info = parse(dictionary)
                hasSeenMedia = true
            } else {
                info = nil
            }
            onChange?()
        default:
            break
        }
    }

    private func parse(_ dictionary: [String: Any]) -> SystemNowPlayingInfo {
        func string(_ key: String) -> String? {
            let value = dictionary[key] as? String
            return (value?.isEmpty ?? true) ? nil : value
        }
        func number(_ key: String) -> Double? {
            (dictionary[key] as? NSNumber)?.doubleValue
        }

        let hash = string("artworkHash") ?? "0"
        var artwork: NSImage?
        if let encoded = string("artwork"), let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            artwork = image
            artworkCache = (hash, image)
        } else if let cached = artworkCache, cached.hash == hash, hash != "0" {
            artwork = cached.image
        }

        let rate = number("rate") ?? 0
        let isPlaying = (dictionary["playing"] as? Bool) ?? (rate > 0)
        let timestamp = number("timestamp").map { Date(timeIntervalSince1970: $0) } ?? Date()
        return SystemNowPlayingInfo(bundleID: string("bundleID"),
                                    parentBundleID: string("parentBundleID"),
                                    title: string("title") ?? "",
                                    artist: string("artist"),
                                    album: string("album"),
                                    duration: number("duration"),
                                    elapsed: number("elapsed"),
                                    rate: isPlaying ? max(rate, 1) : 0,
                                    timestamp: timestamp,
                                    isPlaying: isPlaying,
                                    artwork: artwork,
                                    artworkHash: hash,
                                    uid: string("uid") ?? dictionary["uid"].map { "\($0)" })
    }

    private func setStatus(_ newStatus: Status) {
        status = newStatus
        onChange?()
    }

    // MARK: - Commands

    var canSendCommands: Bool {
        process != nil && input != nil
    }

    func send(_ command: Command) {
        write(command.rawValue)
    }

    func seek(to seconds: Double) {
        write("seek \(max(seconds, 0))")
    }

    func refresh() {
        write("refresh")
    }

    private func write(_ line: String) {
        guard let input = input else { return }
        do {
            try input.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            // The helper is gone; it restarts by itself.
        }
    }
}
