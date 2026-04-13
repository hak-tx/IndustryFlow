import Foundation

struct TranscriptionSession: Identifiable {
    let id: UUID
    let startedAt: Date
    var rawTranscript: String
    var polishedText: String?
    var profile: IndustryProfile
    var status: Status

    enum Status: Equatable {
        case recording
        case processing
        case completed
        case failed(String)
    }

    init(profile: IndustryProfile) {
        self.id = UUID()
        self.startedAt = Date()
        self.rawTranscript = ""
        self.polishedText = nil
        self.profile = profile
        self.status = .recording
    }
}
