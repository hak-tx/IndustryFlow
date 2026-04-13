import Foundation

/// The writing format/context — HOW the dictated text should be formatted,
/// independent of the industry. A lawyer writing an email is different from
/// a lawyer writing a contract. A programmer writing a PR description is
/// different from a programmer writing documentation.
struct WritingFormat: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let promptFragment: String

    static let general = WritingFormat(
        id: "general",
        name: "General",
        icon: "doc.text",
        promptFragment: "Format as clean, professional prose."
    )

    static let email = WritingFormat(
        id: "email",
        name: "Email",
        icon: "envelope",
        promptFragment: """
        Format as a professional email. Include appropriate greeting and sign-off \
        if the speaker indicated them. Use clear paragraphs. Keep the tone appropriate \
        to the context — formal for external, conversational for internal.
        """
    )

    static let socialMedia = WritingFormat(
        id: "social_media",
        name: "Social Media",
        icon: "bubble.left.and.bubble.right",
        promptFragment: """
        Format as a social media post. Keep it concise and engaging. Use short \
        paragraphs or line breaks for readability. Add relevant hashtags only if \
        the speaker mentioned them. Match the platform tone — professional for \
        LinkedIn, casual for Twitter/X.
        """
    )

    static let notes = WritingFormat(
        id: "notes",
        name: "Notes",
        icon: "note.text",
        promptFragment: """
        Format as structured notes. Use bullet points or numbered lists where \
        appropriate. Group related ideas together. Use headers if the content \
        covers multiple topics. Keep it scannable and organized.
        """
    )

    static let documentation = WritingFormat(
        id: "documentation",
        name: "Documentation",
        icon: "book",
        promptFragment: """
        Format as technical or professional documentation. Use clear section \
        structure. Be precise and unambiguous. Use consistent terminology. \
        Include relevant details the speaker mentioned.
        """
    )

    static let chat = WritingFormat(
        id: "chat",
        name: "Chat / Message",
        icon: "message",
        promptFragment: """
        Format as a chat message or instant message. Keep it natural and \
        conversational. Use short sentences. No formal greeting or sign-off \
        unless the speaker included them. Match casual professional tone.
        """
    )

    static let letter = WritingFormat(
        id: "letter",
        name: "Formal Letter",
        icon: "doc.richtext",
        promptFragment: """
        Format as a formal business letter. Include proper structure: date \
        reference if mentioned, salutation, body paragraphs, closing, and \
        signature line. Use formal tone throughout.
        """
    )

    static let report = WritingFormat(
        id: "report",
        name: "Report",
        icon: "chart.bar.doc.horizontal",
        promptFragment: """
        Format as a professional report. Use structured sections with clear \
        headings if the content warrants them. Present information logically. \
        Use data-oriented language where the speaker provided numbers or metrics.
        """
    )

    static let code = WritingFormat(
        id: "code",
        name: "Code / Technical",
        icon: "chevron.left.forwardslash.chevron.right",
        promptFragment: """
        Format as technical writing for software. This could be a code comment, \
        commit message, PR description, documentation, or technical spec. Use \
        backticks for code references. Be precise and concise. Preserve any \
        code-like content exactly as spoken.
        """
    )

    static let allFormats: [WritingFormat] = [
        .general, .email, .socialMedia, .notes, .documentation,
        .chat, .letter, .report, .code
    ]
}
