import Foundation

/// The writing format/context — HOW the dictated text should be formatted,
/// independent of the industry. A lawyer writing an email is different from
/// a lawyer writing a contract. A programmer writing a PR description is
/// different from a programmer writing documentation.
///
/// IMPORTANT: All format prompts are wrappers around the user's actual content.
/// They MUST preserve every sentence and idea. They only affect FORMATTING
/// (paragraphs, bullets, greetings) — never the content itself.
struct WritingFormat: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let promptFragment: String

    static let general = WritingFormat(
        id: "general",
        name: "General",
        icon: "doc.text",
        promptFragment: "Format as clean prose paragraphs. Preserve every sentence and idea the speaker said."
    )

    static let email = WritingFormat(
        id: "email",
        name: "Email",
        icon: "envelope",
        promptFragment: """
        Format as a professional email. Include greeting/sign-off ONLY if the speaker said them. \
        Use clear paragraphs. Preserve EVERY sentence and idea from the dictation — \
        do not condense or summarize. The email should contain all the same content the \
        speaker said, just formatted as email paragraphs.
        """
    )

    static let socialMedia = WritingFormat(
        id: "social_media",
        name: "Social Media",
        icon: "bubble.left.and.bubble.right",
        promptFragment: """
        Format as a social media post with line breaks for readability. \
        Add hashtags ONLY if the speaker mentioned them. \
        Preserve every idea the speaker said — do not summarize or shorten content.
        """
    )

    static let notes = WritingFormat(
        id: "notes",
        name: "Notes",
        icon: "note.text",
        promptFragment: """
        Format as readable notes. Use bullet points ONLY when the speaker explicitly \
        listed items (e.g. "first... second... third..." or "one... two... three..."). \
        For each enumerated item, create a SEPARATE bullet — never combine multiple \
        items into one bullet. Preserve EVERY sentence and idea. Do not summarize. \
        Introductory remarks like "OK", "So", "Let's see" should appear above the list \
        as a regular paragraph, not be dropped.
        """
    )

    static let documentation = WritingFormat(
        id: "documentation",
        name: "Documentation",
        icon: "book",
        promptFragment: """
        Format as technical or professional documentation with clear paragraphs. \
        Use consistent terminology. Include EVERY detail the speaker mentioned — \
        do not summarize or condense.
        """
    )

    static let chat = WritingFormat(
        id: "chat",
        name: "Chat / Message",
        icon: "message",
        promptFragment: """
        Format as a chat message. Keep it natural and conversational. \
        No formal greeting or sign-off unless the speaker included them. \
        Preserve every sentence and idea — do not condense.
        """
    )

    static let letter = WritingFormat(
        id: "letter",
        name: "Formal Letter",
        icon: "doc.richtext",
        promptFragment: """
        Format as a formal business letter with proper structure: date reference if \
        mentioned, salutation, body paragraphs, closing. Preserve EVERY sentence and \
        idea from the dictation in the body — do not summarize.
        """
    )

    static let report = WritingFormat(
        id: "report",
        name: "Report",
        icon: "chart.bar.doc.horizontal",
        promptFragment: """
        Format as a professional report with structured paragraphs. Use headings only \
        if the speaker explicitly indicated them. Preserve EVERY data point, sentence, \
        and idea — do not summarize or condense.
        """
    )

    static let code = WritingFormat(
        id: "code",
        name: "Code / Technical",
        icon: "chevron.left.forwardslash.chevron.right",
        promptFragment: """
        Format as technical writing for software (code comment, commit message, PR \
        description, etc.). Use backticks for code references. Preserve any code-like \
        content exactly as spoken. Preserve every sentence — do not summarize.
        """
    )

    static let allFormats: [WritingFormat] = [
        .general, .email, .socialMedia, .notes, .documentation,
        .chat, .letter, .report, .code
    ]
}
