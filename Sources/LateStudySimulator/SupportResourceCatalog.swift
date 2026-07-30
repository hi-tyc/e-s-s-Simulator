import AppKit
import Foundation

struct SupportResourceCatalog: Equatable {
    enum BuildPolicy: Equatable {
        case debug
        case release
    }

    struct Validation: Equatable {
        let checkedAt: Date
        let expiredResources: [SupportResource]
        let buildPolicy: BuildPolicy

        var hasExpiredResources: Bool { expiredResources.isEmpty == false }
        var allowsDebugBuild: Bool { true }
        var allowsReleaseBuild: Bool { buildPolicy == .debug || expiredResources.isEmpty }
    }

    private struct CatalogFile: Decodable {
        let resources: [SupportResource]
    }

    let resources: [SupportResource]

    static let reviewFreshnessMonths = 6

    static func load(bundle: Bundle = .module) throws -> SupportResourceCatalog {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "SupportResources") else {
            return SupportResourceCatalog(resources: fallbackResources)
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        return SupportResourceCatalog(resources: file.resources)
    }

    static func bundledOrFallback() -> SupportResourceCatalog {
        (try? load()) ?? SupportResourceCatalog(resources: fallbackResources)
    }

    var primaryHotline: SupportResource? {
        resources.first { $0.number == "12356" }
    }

    func validate(on date: Date = .now, buildPolicy: BuildPolicy = .debug) -> Validation {
        Validation(
            checkedAt: date,
            expiredResources: resources.filter { Self.isExpired($0, on: date) },
            buildPolicy: buildPolicy
        )
    }

    static func isExpired(_ resource: SupportResource, on date: Date = .now) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        guard let expiresAt = calendar.date(byAdding: .month, value: reviewFreshnessMonths, to: resource.reviewedAt) else {
            return true
        }
        return expiresAt < date
    }

    private static var fallbackResources: [SupportResource] {
        [
            SupportResource(
                id: "cn-national-12356",
                region: "中国大陆",
                displayName: "全国统一心理援助热线",
                number: "12356",
                detail: "提供心理健康教育、心理咨询、心理疏导和心理危机干预；服务时间以所在地接听安排为准。",
                url: nil,
                reviewedAt: SupportResource.dateFormatter.date(from: "2026-07-23") ?? .distantPast,
                sourceURL: "https://www.gov.cn/zhengce/zhengceku/202412/content_6994470.htm",
                sourceTitle: "国家卫生健康委关于应用 12356 全国统一心理援助热线电话号码的通知"
            ),
            SupportResource(
                id: "cn-emergency-adult-120-110",
                region: "中国大陆",
                displayName: "正在发生的人身危险",
                number: "120 / 110",
                detail: "请立即联系现场可信成人，并根据现场危险联系急救或公安。",
                url: nil,
                reviewedAt: SupportResource.dateFormatter.date(from: "2026-07-23") ?? .distantPast,
                sourceURL: "local://late-study-simulator/safety-protocol/emergency",
                sourceTitle: "游戏内安全交接脚本"
            ),
            SupportResource(
                id: "school-counseling-room",
                region: "本校",
                displayName: "学校心理咨询室",
                number: nil,
                detail: "开放时间、预约方式和紧急联系人以学校实际信息为准；优先联系班主任、校医或心理老师。",
                url: nil,
                reviewedAt: SupportResource.dateFormatter.date(from: "2026-07-23") ?? .distantPast,
                sourceURL: "local://late-study-simulator/school-support-template",
                sourceTitle: "学校资源本地配置模板"
            )
        ]
    }
}

@MainActor
enum PasteboardBridge {
    static var copyHandler: (String) -> Bool = { text in
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    private(set) static var lastCopiedText: String?

    @discardableResult
    static func copy(_ text: String) -> Bool {
        lastCopiedText = text
        return copyHandler(text)
    }
}
