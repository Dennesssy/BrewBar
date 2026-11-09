// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

struct IconView: View {
    let item: FormulaItem
    let size: CGFloat

    init(item: FormulaItem, size: CGFloat = 48) {
        self.item = item
        self.size = size
    }

    /// GitHub avatars are the only remote artwork used; everything else gets
    /// a generated tile so no package browsing is sent to a third-party
    /// favicon service.
    var iconURL: URL? {
        let candidate = item.repository ?? item.homepage
        guard let urlString = candidate,
              let url = URL(string: urlString),
              let host = url.host,
              host.contains("github.com") else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let owner = pathComponents.first, !owner.isEmpty else { return nil }
        return URL(string: "https://github.com/\(owner).png?size=\(Int(size * 2))")
    }

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: max(0.5, size / 160))
        )
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        let hue = Double(Self.stableHash(item.id) % 360) / 360.0

        return ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.52, brightness: 0.96),
                    Color(hue: hue, saturation: 0.78, brightness: 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(monogram)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)

            if size >= 56, item.type == .cask {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(size * 0.12)
            }
        }
    }

    private var monogram: String {
        let words = (item.fullTitle ?? item.name)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// `hashValue` is seeded per process; icons must keep the same color
    /// between launches, so use a small FNV-1a hash instead.
    nonisolated static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
