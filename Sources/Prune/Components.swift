import SwiftUI
import AppKit
import PruneCore

/// Coloured tag with the artifact type's icon and name.
struct TypeBadge: View {
    let type: ArtifactType?
    let fallback: String

    var body: some View {
        let color = Palette.color(type?.color)
        HStack(spacing: 3) {
            Image(systemName: type?.icon ?? "questionmark.folder")
                .font(.system(size: 8, weight: .semibold))
            Text(type?.displayName ?? fallback)
        }
        .badge(color: color)
    }
}

/// Size tag coloured by severity (large red, medium orange, small green).
struct SizeBadge: View {
    let bytes: Int64
    let formatted: String
    var unknown: Bool = false

    var body: some View {
        Text(formatted)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .badge(color: Theme.sizeColor(bytes: bytes, unknown: unknown))
            .help(unknown ? "The size could not be measured and is not counted in totals" : "")
    }
}

/// Marks a type whose contents cannot be regenerated (user data).
struct NotRegenerableTag: View {
    var compact = false

    var body: some View {
        Group {
            if compact {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            } else {
                Text("not regenerable").badge(color: .orange)
            }
        }
        .help("Not regenerable: deleting this removes data that cannot be rebuilt or downloaded again")
        .accessibilityLabel("Not regenerable")
    }
}

/// Square checkbox glyph used by rows that toggle as a whole.
struct CheckboxGlyph: View {
    enum Mark { case on, off, mixed }
    let mark: Mark

    var body: some View {
        Image(systemName: mark == .on ? "checkmark.square.fill" : mark == .mixed ? "minus.square.fill" : "square")
            .font(.system(size: 14))
            .foregroundColor(mark == .off ? .secondary : .accentColor)
    }
}

/// Large figure with a caption, used in header and summary cards.
struct StatView: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown when the scan hit folders it was not allowed to read.
struct DeniedNotice: View {
    let count: Int
    let examples: [URL]

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) \(count == 1 ? "folder" : "folders") could not be read")
                    .font(.callout)
                Text("Grant Full Disk Access to include them in the next scan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .help(examples.prefix(10).map { Formatter.shortenPath($0.path) }.joined(separator: "\n"))
            Spacer()
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(Self.privacySettingsURL)
            }
            .controlSize(.small)
        }
    }
}

/// Finder and pasteboard helpers for result rows.
enum FileActions {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}

extension Int {
    /// "1 item" / "3 items".
    func counted(_ singular: String, _ plural: String? = nil) -> String {
        "\(self) \(self == 1 ? singular : (plural ?? singular + "s"))"
    }
}
