import AppKit
import Foundation
import SwiftUI

struct SupportResourceView: View {
    let resources: [SupportResource]
    @State private var copiedResourceID: String?

    private var primaryHotline: SupportResource? {
        resources.first { $0.number == "12356" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("真实求助资源")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("已审核 \(resources.first?.reviewedAtText ?? "今日")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }

            Text("如果你或你认识的人需要帮助，先把可用的联系方式记下来。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            if let hotline = primaryHotline {
                resourceBanner(hotline)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: 10, alignment: .top)],
                spacing: 10
            ) {
                ForEach(resources) { resource in
                    resourceCard(resource)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func resourceBanner(_ resource: SupportResource) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.displayName)
                    .font(.system(size: 12, weight: .bold))
                Text(resource.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(resource.number ?? resource.copyText)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                copyButton(for: resource, style: .banner)
            }
        }
        .padding(12)
        .background(resource.region == "中国大陆" ? .cyan.opacity(0.14) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resourceCard(_ resource: SupportResource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(resource.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(resource.region)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer(minLength: 8)
                copyButton(for: resource, style: .card)
            }

            Text(resource.detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let number = resource.number {
                    Text(number)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                } else {
                    Text(resource.copyText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("审核 \(resource.reviewedAtText)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
            }

            Text(resource.sourceTitle)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(2)
        }
        .padding(12)
        .frame(minHeight: 136, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func copyButton(for resource: SupportResource, style: CopyButtonStyle) -> some View {
        Button {
            if PasteboardBridge.copy(resource.copyText) {
                copiedResourceID = resource.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                    if copiedResourceID == resource.id {
                        copiedResourceID = nil
                    }
                }
            }
        } label: {
            Image(systemName: copiedResourceID == resource.id ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.system(size: style.iconSize, weight: .bold))
                .frame(width: style.frameWidth, height: style.frameHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(copiedResourceID == resource.id ? .mint : .white.opacity(0.9))
        .padding(style.padding)
        .background(.white.opacity(style.backgroundOpacity), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .help("复制 \(resource.displayName)")
        .accessibilityLabel("复制 \(resource.displayName)")
    }

    private enum CopyButtonStyle {
        case banner
        case card

        var iconSize: CGFloat {
            switch self {
            case .banner: return 13
            case .card: return 11
            }
        }

        var frameWidth: CGFloat {
            switch self {
            case .banner: return 30
            case .card: return 26
            }
        }

        var frameHeight: CGFloat {
            switch self {
            case .banner: return 28
            case .card: return 24
            }
        }

        var padding: CGFloat {
            switch self {
            case .banner: return 0
            case .card: return 0
            }
        }

        var backgroundOpacity: Double {
            switch self {
            case .banner: return 0.12
            case .card: return 0.08
            }
        }
    }
}

struct SupportResourceCompactStripView: View {
    let resources: [SupportResource]
    @State private var copiedResourceID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("真实求助资源")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("已审核 \(resources.first?.reviewedAtText ?? "今日")")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.54))
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 8, alignment: .top)],
                spacing: 8
            ) {
                ForEach(resources) { resource in
                    compactCard(resource)
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func compactCard(_ resource: SupportResource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(resource.region)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer(minLength: 4)
                Button {
                    if PasteboardBridge.copy(resource.copyText) {
                        copiedResourceID = resource.id
                    }
                } label: {
                    Image(systemName: copiedResourceID == resource.id ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedResourceID == resource.id ? .mint : .white.opacity(0.88))
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .help("复制 \(resource.displayName)")
                .accessibilityLabel("复制 \(resource.displayName)")
            }

            Text(resource.number ?? resource.copyText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(resource.detail)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(minHeight: 108, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}
