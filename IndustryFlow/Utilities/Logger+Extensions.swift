import os

extension Logger {
    private static let subsystem = Constants.bundleIdentifier

    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    static let accessibility = Logger(subsystem: subsystem, category: "Accessibility")
    static let polishing = Logger(subsystem: subsystem, category: "Polishing")
    static let hotkey = Logger(subsystem: subsystem, category: "Hotkey")
    static let app = Logger(subsystem: subsystem, category: "App")
}
