import SwiftUI

/// In-app license/acknowledgments viewer.
struct LicensesView: View {
    struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let license: String
        let file: String
        let url: String
    }

    static let entries: [Entry] = [
        Entry(name: "tunaneko",
              detail: "The app itself",
              license: "MIT License",
              file: "MIT",
              url: "https://github.com/"),
        Entry(name: "OpenConnect",
              detail: "VPN core (bundled, v9.21)",
              license: "LGPL v2.1",
              file: "LGPL-2.1",
              url: "https://www.infradead.org/openconnect/"),
        Entry(name: "vpnc-script",
              detail: "Network configuration script (bundled, modified)",
              license: "GPL v2+",
              file: "GPL-2.0",
              url: "https://gitlab.com/openconnect/vpnc-scripts"),
    ]

    @State private var selected: Entry?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.entries) { entry in
                Button { selected = entry } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                            Text("\(entry.detail) — \(entry.license)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $selected) { entry in
            LicenseTextView(entry: entry)
        }
    }
}

struct LicenseTextView: View {
    let entry: LicensesView.Entry
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        guard let url = Bundle.main.url(forResource: entry.file, withExtension: "txt", subdirectory: "Licenses"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text not found."
        }
        return content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.name).font(.title2)
                    Text(entry.license).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.tr("licenses.close")) { dismiss() }
            }
            Link(entry.url, destination: URL(string: entry.url)!)
                .font(.caption)
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 360)
        }
        .padding(20)
        .frame(width: 560)
    }
}
