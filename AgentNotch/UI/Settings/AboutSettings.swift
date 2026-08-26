import AppKit
import Foundation
import SwiftUI

struct AppVersionInfo: Equatable, Sendable {
    let version: String?
    let build: String?

    init(infoDictionary: [String: Any]) {
        version = Self.nonEmptyString(
            infoDictionary["CFBundleShortVersionString"]
        )
        build = Self.nonEmptyString(
            infoDictionary["CFBundleVersion"]
        )
    }

    static var current: AppVersionInfo {
        AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }
}

struct OpenSourceLicense: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let licenseName: String
    let projectURLString: String
    let resourceNames: [String]

    var projectURL: URL? {
        URL(string: projectURLString)
    }

    func licenseText(in bundle: Bundle = .module) -> String? {
        let texts = resourceNames.compactMap { resourceName -> String? in
            guard
                let url = bundle.url(
                    forResource: resourceName,
                    withExtension: "txt"
                )
            else {
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        guard texts.count == resourceNames.count else { return nil }
        return texts.joined(separator: "\n\n––––––––––––––––––––––––––––––––––––––––\n\n")
    }
}

enum OpenSourceLicenseCatalog {
    /// Runtime libraries shipped with the GUI. Compiler-only packages such as
    /// swift-syntax are not part of the distributed application.
    static let licenses: [OpenSourceLicense] = [
        OpenSourceLicense(
            id: "defaults",
            name: "Defaults",
            version: "9.0.8",
            licenseName: "MIT",
            projectURLString: "https://github.com/sindresorhus/Defaults",
            resourceNames: ["License-Defaults"]
        ),
        OpenSourceLicense(
            id: "highlighterswift",
            name: "HighlighterSwift",
            version: "3.1.0",
            licenseName: "MIT / BSD-3-Clause",
            projectURLString: "https://github.com/smittytone/HighlighterSwift",
            resourceNames: ["License-HighlighterSwift"]
        ),
        OpenSourceLicense(
            id: "keyboardshortcuts",
            name: "KeyboardShortcuts",
            version: "2.4.0",
            licenseName: "MIT",
            projectURLString: "https://github.com/sindresorhus/KeyboardShortcuts",
            resourceNames: ["License-KeyboardShortcuts"]
        ),
        OpenSourceLicense(
            id: "launchatlogin-modern",
            name: "LaunchAtLogin",
            version: "1.1.0",
            licenseName: "MIT",
            projectURLString: "https://github.com/sindresorhus/LaunchAtLogin-Modern",
            resourceNames: ["License-LaunchAtLogin"]
        ),
        OpenSourceLicense(
            id: "swift-markdown-ui",
            name: "MarkdownUI",
            version: "2.4.1",
            licenseName: "MIT",
            projectURLString: "https://github.com/gonzalezreal/swift-markdown-ui",
            resourceNames: ["License-MarkdownUI"]
        ),
        OpenSourceLicense(
            id: "networkimage",
            name: "NetworkImage",
            version: "6.0.1",
            licenseName: "MIT",
            projectURLString: "https://github.com/gonzalezreal/NetworkImage",
            resourceNames: ["License-NetworkImage"]
        ),
        OpenSourceLicense(
            id: "swift-cmark",
            name: "swift-cmark",
            version: "0.7.1",
            licenseName: "BSD-2-Clause and others",
            projectURLString: "https://github.com/swiftlang/swift-cmark",
            resourceNames: ["License-swift-cmark"]
        ),
        OpenSourceLicense(
            id: "swift-log",
            name: "swift-log",
            version: "1.11.0",
            licenseName: "Apache-2.0",
            projectURLString: "https://github.com/apple/swift-log",
            resourceNames: ["License-swift-log", "Notice-swift-log"]
        ),
    ]
}

struct AboutSettings: View {
    @State private var selectedLicense: OpenSourceLicense?
    @State private var isShowingOpenSourceLicenses = false
    private let versionInfo = AppVersionInfo.current

    init(isShowingOpenSourceLicenses: Bool = false) {
        _isShowingOpenSourceLicenses = State(
            initialValue: isShowingOpenSourceLicenses
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    productMark
                    Text(verbatim: "Agent Notch")
                        .font(.title2.weight(.semibold))

                    version

                    Text(
                        l10n:
                            "Agent Notch’s original source code is under the MIT License."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let sourceURL = URL(
                        string: "https://github.com/tosaka07/agent-notch"
                    ) {
                        Link(L("Source Code"), destination: sourceURL)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                Button {
                    isShowingOpenSourceLicenses.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isShowingOpenSourceLicenses
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                        Text(L("Open Source Licenses"))

                        Spacer()

                        Text(verbatim: "\(OpenSourceLicenseCatalog.licenses.count)")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    isShowingOpenSourceLicenses ? L("Expanded") : L("Collapsed")
                )

                if isShowingOpenSourceLicenses {
                    ForEach(OpenSourceLicenseCatalog.licenses) { license in
                        Button {
                            selectedLicense = license
                        } label: {
                            licenseRow(license)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text(l10n: "Agent Notch uses the following open source software.")
            }
        }
        .sheet(item: $selectedLicense) { license in
            OpenSourceLicenseDetail(license: license)
        }
    }

    @ViewBuilder
    private var version: some View {
        if let version = versionInfo.version {
            VStack(spacing: 2) {
                Text(L("Version \(version)"))
                if let build = versionInfo.build {
                    Text(L("Build \(build)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(l10n: "Development build")
                .foregroundStyle(.secondary)
        }
    }

    private var productMark: some View {
        GlyphView(
            bitmap: GlyphBitmap.square(ProductMark.size, on: .primary) { x, y in
                let cell = ProductMark.GridCell(col: x, row: y)
                return ProductMark.outlineCells.contains(cell)
                    || ProductMark.pupilCells.contains(cell)
            },
            dot: 3.5,
            gap: 1.75
        )
        .accessibilityLabel("Agent Notch")
    }

    private func licenseRow(_ license: OpenSourceLicense) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: license.name)
                Text(verbatim: license.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(verbatim: license.licenseName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct OpenSourceLicenseDetail: View {
    @Environment(\.dismiss) private var dismiss
    let license: OpenSourceLicense

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: license.name)
                        .font(.title2.weight(.semibold))
                    Text(verbatim: "\(license.version) · \(license.licenseName)")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                Text(verbatim: license.licenseText() ?? L("License text unavailable."))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let projectURL = license.projectURL {
                Link(L("Project Website"), destination: projectURL)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}
