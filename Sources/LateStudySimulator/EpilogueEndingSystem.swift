import Foundation
import SwiftUI

enum EndingType: String, CaseIterable, Hashable {
    case emergencyHandoff
    case urgentHandoff
    case voluntaryAndShared
    case unclearDisclosure
    case lowTrustHandoff
    case didNotShare
    case standardLight

    var title: String {
        switch self {
        case .emergencyHandoff:
            return "已经有人接手"
        case .urgentHandoff:
            return "把事情交出去"
        case .voluntaryAndShared:
            return "今天不一样了"
        case .unclearDisclosure:
            return "不知道，也要行动"
        case .lowTrustHandoff:
            return "你做了你能做的"
        case .didNotShare:
            return "下次也可以"
        case .standardLight:
            return "这里有光"
        }
    }

    var body: String {
        switch self {
        case .emergencyHandoff:
            return "你没有负责解决一切。你做的是让可靠的大人及时接住接下来的事。"
        case .urgentHandoff:
            return "陪伴不是独自承担。今天，接下来的重量已经交给能够负责的大人。"
        case .voluntaryAndShared:
            return "有些改变从开口开始。不管是他，还是你。"
        case .unclearDisclosure:
            return "他没有把一切说清楚。你没有把沉默当成没事，而是找来了能够接手的人。"
        case .lowTrustHandoff:
            return "不是每一次尝试都能立刻得到回应。但今天，责任不再只落在学生身上。"
        case .didNotShare:
            return "今天你先坐了一会儿。门没有关上，你可以按自己的速度再来。"
        case .standardLight:
            return "有人发现，有人开口，也有人接手。支持不是一个人的任务。"
        }
    }

    var symbol: String {
        switch self {
        case .emergencyHandoff:
            return "cross.case.fill"
        case .urgentHandoff:
            return "shield.lefthalf.filled"
        case .voluntaryAndShared:
            return "heart.text.square.fill"
        case .unclearDisclosure:
            return "questionmark.bubble.fill"
        case .lowTrustHandoff:
            return "person.2.badge.gearshape.fill"
        case .didNotShare:
            return "figure.seated.side"
        case .standardLight:
            return "lightbulb.max.fill"
        }
    }

    var accent: Color {
        switch self {
        case .emergencyHandoff:
            return .red
        case .urgentHandoff:
            return .orange
        case .voluntaryAndShared:
            return .mint
        case .unclearDisclosure:
            return .yellow
        case .lowTrustHandoff:
            return .cyan
        case .didNotShare:
            return .purple
        case .standardLight:
            return .green
        }
    }

    var priorityLabel: String {
        let index = (Self.allCases.firstIndex(of: self) ?? 0) + 1
        return "P\(index)"
    }
}

struct EndingSelector {
    static func select(campaign: NarrativeCampaign) -> EndingType {
        if campaign.safetyHandoffState?.route == .emergencyServices || campaign.safetyRoute == NarrativeSafetyRoute.emergencyServices.displayName {
            return .emergencyHandoff
        }
        if campaign.safetyHandoffState?.route == .urgentSchoolResponse || campaign.safetyRoute == NarrativeSafetyRoute.urgentSchoolResponse.displayName {
            return .urgentHandoff
        }
        if campaign.safetyHandoffState?.resolutionPath == .voluntary && campaign.sharedSelf {
            return .voluntaryAndShared
        }
        if campaign.safetyHandoffState?.resolutionPath == .adultCameAfterUnclearDisclosure {
            return .unclearDisclosure
        }
        if campaign.safetyHandoffState?.resolutionPath == .adultCameAfterLowTrust {
            return .lowTrustHandoff
        }
        if campaign.sharedSelf == false {
            return .didNotShare
        }
        return .standardLight
    }

    static func needsSelfCareReminder(campaign: NarrativeCampaign) -> Bool {
        campaign.selfCared == false
    }

    static func routeSpectrum(for campaign: NarrativeCampaign) -> [EndingRouteSignal] {
        let selected = select(campaign: campaign)
        return EndingType.allCases.map { type in
            routeSignal(for: type, campaign: campaign, isSelected: type == selected)
        }
    }

    private static func routeSignal(
        for type: EndingType,
        campaign: NarrativeCampaign,
        isSelected: Bool
    ) -> EndingRouteSignal {
        let handoff = campaign.safetyHandoffState
        let route = handoff?.route
        let routeName = campaign.safetyRoute.isEmpty ? "未写入安全路线" : campaign.safetyRoute
        let riskAsked = handoff?.riskAsked == true
        let adultContact = handoff?.adultContactInitiated == true
        let handoffComplete = handoff?.safetyHandoffComplete == true

        let isEmergency = route == .emergencyServices || campaign.safetyRoute == NarrativeSafetyRoute.emergencyServices.displayName
        let isUrgent = route == .urgentSchoolResponse || campaign.safetyRoute == NarrativeSafetyRoute.urgentSchoolResponse.displayName
        let isVoluntaryShared = handoff?.resolutionPath == .voluntary && campaign.sharedSelf
        let isUnclear = handoff?.resolutionPath == .adultCameAfterUnclearDisclosure
        let isLowTrust = handoff?.resolutionPath == .adultCameAfterLowTrust
        let didNotShare = campaign.sharedSelf == false

        switch type {
        case .emergencyHandoff:
            let riskBoost = handoff?.authoredRisk == .imminent ? 0.68 : 0.24
            return EndingRouteSignal(
                type: type,
                isSelected: isSelected,
                matchStrength: isEmergency ? 1 : riskBoost,
                triggerLine: "优先级最高：紧急服务路线",
                evidenceLine: isEmergency ? "本局：\(routeName) 已接入，现场重量交给能负责的人。" : "本局：未进入紧急服务路线。"
            )
        case .urgentHandoff:
            let riskBoost = handoff?.authoredRisk == .high ? 0.62 : 0.28
            return EndingRouteSignal(
                type: type,
                isSelected: isSelected,
                matchStrength: isUrgent ? 1 : riskBoost,
                triggerLine: "高优先级：校内紧急响应",
                evidenceLine: isUrgent ? "本局：\(routeName) 已建立，老师和学校支持开始接手。" : "本局：没有命中校内紧急支持路线。"
            )
        case .voluntaryAndShared:
            return EndingRouteSignal(
                type: type,
                isSelected: isSelected,
                matchStrength: isVoluntaryShared ? 1 : (campaign.sharedSelf ? 0.72 : 0.34),
                triggerLine: "自愿同行，并且苏念说出自己的事",
                evidenceLine: isVoluntaryShared ? "本局：自愿交接后，苏念也把自己的疲惫说出口。" : "本局：还缺少自愿交接或苏念自我表达。"
            )
        case .unclearDisclosure:
            return EndingRouteSignal(
                type: type,
                isSelected: isSelected,
                matchStrength: isUnclear ? 1 : (riskAsked ? 0.54 : 0.24),
                triggerLine: "信息不完整，但成人已经到场",
                evidenceLine: isUnclear ? "本局：没有把沉默当作没事，成人支持接了上来。" : "本局：未进入未明确披露后的成人接管线。"
            )
        case .lowTrustHandoff:
            return EndingRouteSignal(
                type: type,
                isSelected: isSelected,
                matchStrength: isLowTrust ? 1 : (adultContact ? 0.58 : 0.22),
                triggerLine: "低信任回应下仍完成交接",
                evidenceLine: isLowTrust ? "本局：回应没有完全打开，但责任仍转给能负责的人。" : "本局：低信任成人接管不是主路线。"
            )
        case .didNotShare:
            return EndingRouteSignal(
                type: type,
                isSelected: isSelected,
                matchStrength: didNotShare ? 1 : 0.38,
                triggerLine: "苏念今天先坐一会儿",
                evidenceLine: didNotShare ? "本局：苏念保留了节奏，门仍然开着，下次也可以。" : "本局：苏念已经说出了自己的疲惫。"
            )
        case .standardLight:
            let base = (handoffComplete ? 0.58 : 0.34) + (campaign.sharedSelf ? 0.22 : 0) + (campaign.privacyProtected ? 0.12 : 0)
            return EndingRouteSignal(
                type: type,
                isSelected: isSelected,
                matchStrength: isSelected ? 1 : base.clamped(to: 0.22...0.92),
                triggerLine: "普通路线完成，支持网络闭合",
                evidenceLine: isSelected ? "本局：有人看见、有人开口，也有人接手。" : "本局：\(handoffComplete ? "交接已完成" : "交接仍需确认")，但更高优先级路线先命中。"
            )
        }
    }
}

struct EndingRouteSignal: Identifiable {
    let type: EndingType
    let isSelected: Bool
    let matchStrength: Double
    let triggerLine: String
    let evidenceLine: String

    var id: String { type.rawValue }
}

struct EndingRouteSpectrumView: View {
    let campaign: NarrativeCampaign
    var compact = false

    private var routes: [EndingRouteSignal] {
        EndingSelector.routeSpectrum(for: campaign)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.mint)
                Text("结局路线谱")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("7 条主线")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }

            if compact {
                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 132), spacing: 7),
                    GridItem(.flexible(minimum: 132), spacing: 7)
                ], spacing: 7) {
                    ForEach(routes) { route in
                        EndingRouteCompactTile(signal: route)
                    }
                }
            } else {
                VStack(spacing: 7) {
                    ForEach(routes) { route in
                        EndingRouteRow(signal: route, compact: compact)
                    }
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("结局路线谱，七条主结局，当前路线为 \(routes.first(where: \.isSelected)?.type.title ?? "未知")")
    }
}

private struct EndingRouteCompactTile: View {
    let signal: EndingRouteSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: signal.type.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(signal.isSelected ? signal.type.accent : .white.opacity(0.58))
                    .frame(width: 14)
                Text(signal.type.priorityLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(signal.type.accent.opacity(0.82))
                Text(signal.type.title)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(signal.type.accent.opacity(signal.isSelected ? 0.88 : 0.46))
                        .frame(width: geo.size.width * CGFloat(signal.matchStrength.clamped(to: 0...1)))
                }
            }
            .frame(height: 5)

            Text(signal.isSelected ? signal.evidenceLine : signal.triggerLine)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(signal.isSelected ? 0.70 : 0.54))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .background(.white.opacity(signal.isSelected ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(signal.type.accent.opacity(signal.isSelected ? 0.34 : 0.10), lineWidth: 1)
        )
    }
}

private struct EndingRouteRow: View {
    let signal: EndingRouteSignal
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(signal.type.accent.opacity(signal.isSelected ? 0.28 : 0.12))
                Image(systemName: signal.type.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(signal.isSelected ? signal.type.accent : .white.opacity(0.64))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: compact ? 4 : 5) {
                HStack(spacing: 6) {
                    Text(signal.type.priorityLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(signal.type.accent.opacity(0.86))
                    Text(signal.type.title)
                        .font(.system(size: compact ? 10 : 11, weight: .bold))
                        .lineLimit(1)
                    if signal.isSelected {
                        Text("当前")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black.opacity(0.78))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(signal.type.accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(signal.matchStrength.clamped(to: 0...1) * 100))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.54))
                }

                Text(signal.triggerLine)
                    .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.67))
                    .lineLimit(1)

                Text(signal.evidenceLine)
                    .font(.system(size: compact ? 8 : 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(compact ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.10))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(signal.type.accent.opacity(signal.isSelected ? 0.86 : 0.45))
                            .frame(width: geo.size.width * CGFloat(signal.matchStrength.clamped(to: 0...1)))
                    }
                }
                .frame(height: compact ? 4 : 5)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, compact ? 7 : 8)
        .background(.white.opacity(signal.isSelected ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(signal.type.accent.opacity(signal.isSelected ? 0.34 : 0.10), lineWidth: 1)
        )
    }
}

struct SupportNetworkNode: Identifiable {
    let id: String
    let title: String
    let detail: String
    let traceLines: [String]
    let strength: Double
    let tint: Color
    let point: CGPoint
    let activationDelay: TimeInterval
}

enum SupportNetworkModel {
    static func nodes(for campaign: NarrativeCampaign) -> [SupportNetworkNode] {
        let echoes = campaign.consequenceEchoes

        func echoTrace(for kind: NarrativeConsequenceEchoKind, fallback: String) -> String {
            echoes.first { $0.kind == kind }?.trace ?? fallback
        }

        func echoStrength(for kind: NarrativeConsequenceEchoKind, fallback: Double) -> Double {
            echoes.first { $0.kind == kind }?.strength ?? fallback
        }
        let mirrorDialogueTrace = mirrorDialogueEpilogueTrace(for: campaign)

        let rawNodes = [
            SupportNetworkNode(
                id: "see",
                title: "看见",
                detail: echoTrace(for: .noticed, fallback: campaign.clueCount > 0 ? "\(campaign.clueCount) 条线索" : "仍在收集"),
                traceLines: [
                    "本局痕迹：你留下了 \(max(0, campaign.clueCount)) 条可回看的线索。",
                    campaign.clueCount >= 4 ? "下一步：把异常当成信号，而不是立刻当成结论。" : "下一步：还可以继续观察声音、停顿和没有说出口的动作。"
                ],
                strength: echoStrength(for: .noticed, fallback: min(1, Double(max(0, campaign.clueCount)) / 5.0)),
                tint: .cyan,
                point: CGPoint(x: 0.10, y: 0.70),
                activationDelay: 0
            ),
            SupportNetworkNode(
                id: "companion",
                title: "陪伴",
                detail: echoTrace(for: .companion, fallback: campaign.companionID.isEmpty ? "尚未选择同伴" : campaign.companionID),
                traceLines: [
                    "本局痕迹：\(campaign.companionID.isEmpty ? "你还没有把同行者纳入现场。" : "\(campaign.companionID)进入了这条支持链。")",
                    "下一步：可靠同伴负责在场和联络，不负责独自判断风险。"
                ],
                strength: echoStrength(for: .companion, fallback: campaign.companionID.isEmpty ? 0.34 : 0.88),
                tint: .mint,
                point: CGPoint(x: 0.30, y: 0.34),
                activationDelay: 0.5
            ),
            SupportNetworkNode(
                id: "trust",
                title: "倾听",
                detail: echoTrace(
                    for: .riskQuestion,
                    fallback: mirrorDialogueEpilogueDetail(for: campaign) ?? (campaign.linCheTrust > 1 ? "继续说下去" : "仍可再靠近")
                ),
                traceLines: mirrorDialogueTrace.map {
                    [
                        $0,
                        jiangDialogueTraceLine(for: campaign)
                    ]
                } ?? [
                    jiangDialogueTraceLine(for: campaign),
                    "下一步：说清安全问题，同时让成人承担后续评估。"
                ],
                strength: echoStrength(for: .riskQuestion, fallback: min(1, Double(max(0, campaign.linCheTrust)) / 20.0)),
                tint: .yellow,
                point: CGPoint(x: 0.50, y: 0.58),
                activationDelay: 1.0
            ),
            SupportNetworkNode(
                id: "handoff",
                title: "交接",
                detail: echoTrace(for: .handoff, fallback: campaign.safetyRoute.isEmpty ? "咨询室支持" : campaign.safetyRoute),
                traceLines: [
                    "本局痕迹：\(campaign.safetyRoute.isEmpty ? "安全路线尚未写入。" : "安全路线进入「\(campaign.safetyRoute)」。")",
                    "下一步：学生把位置和需要支持说清楚，接手由能负责的人完成。"
                ],
                strength: echoStrength(for: .handoff, fallback: {
                    switch campaign.safetyHandoffState?.route {
                    case .emergencyServices: return 1
                    case .urgentSchoolResponse: return 0.92
                    case .standardCounseling: return 0.76
                    case nil: return 0.42
                    }
                }()),
                tint: .orange,
                point: CGPoint(x: 0.70, y: 0.30),
                activationDelay: 1.5
            ),
            SupportNetworkNode(
                id: "selfcare",
                title: "自照",
                detail: echoTrace(for: .selfCare, fallback: campaign.selfCared ? "已经照顾自己" : "还在学着停下来"),
                traceLines: [
                    "本局痕迹：\(campaign.selfCared ? "你把自己也放回了支持网络。" : "你一路照顾别人，但自己还需要被接住。")",
                    campaign.sharedSelf ? "下一步：你已经开口，支持可以流向你自己。" : "下一步：今天先坐一会儿，也是一种有效的开始。"
                ],
                strength: echoStrength(for: .selfCare, fallback: campaign.selfCared ? 0.96 : 0.46),
                tint: .pink,
                point: CGPoint(x: 0.90, y: 0.68),
                activationDelay: 2.0
            )
        ]

        return rawNodes
    }

    private static func mirrorDialogueEpilogueDetail(for campaign: NarrativeCampaign) -> String? {
        guard let choiceID = mirrorDialogueChoiceID(for: campaign) else { return nil }
        switch choiceID {
        case "invite":
            return "可靠的大人被放进网络"
        case "present":
            return "先陪在旁边"
        case "reassure":
            return "负担被接住"
        default:
            return nil
        }
    }

    private static func mirrorDialogueEpilogueTrace(for campaign: NarrativeCampaign) -> String? {
        guard let choiceID = mirrorDialogueChoiceID(for: campaign) else { return nil }
        switch choiceID {
        case "invite":
            return "镜中痕迹：你邀请林澈一起找可靠的大人，后面的交接不再像突然发生。"
        case "present":
            return "镜中痕迹：你先陪林澈站了一会儿，后面的支持也保留了空间。"
        case "reassure":
            return "镜中痕迹：你告诉林澈不用一个人扛完，后面的等待也更平稳。"
        default:
            return nil
        }
    }

    private static func mirrorDialogueChoiceID(for campaign: NarrativeCampaign) -> String? {
        guard let impact = campaign.lastChoiceImpact,
              impact.sourceMomentID == "2.listen",
              let choiceID = impact.id.split(separator: ".").last.map(String.init),
              ["invite", "present", "reassure"].contains(choiceID) else { return nil }
        return choiceID
    }

    private static func jiangDialogueTraceLine(for campaign: NarrativeCampaign) -> String {
        if campaign.jiangDialoguePerformanceSupport >= 0.55,
           campaign.jiangDialoguePerformanceRupture < 0.25 {
            return "本局痕迹：江越对话里，复述和陪伴让他愿意继续停留。"
        }
        if campaign.jiangDialoguePerformanceRupture >= 0.45 {
            return "本局痕迹：江越对话里，部分回应让他退回防线，后续仍把成人支持接上。"
        }
        return "本局痕迹：江越对话里，现场没有被学生独自扛下，安全问题被说清。"
    }
}

struct SupportNetworkView: View {
    let campaign: NarrativeCampaign
    let canvasHeight: CGFloat
    let compact: Bool
    @State private var selectedNodeID: String
    @State private var appearedAt: Date

    init(campaign: NarrativeCampaign, canvasHeight: CGFloat = 220, compact: Bool = false) {
        self.campaign = campaign
        self.canvasHeight = canvasHeight
        self.compact = compact
        _selectedNodeID = State(initialValue: "see")
        _appearedAt = State(initialValue: Date())
    }

    private var nodes: [SupportNetworkNode] {
        SupportNetworkModel.nodes(for: campaign)
    }

    private var consequenceEchoes: [NarrativeConsequenceEcho] {
        campaign.consequenceEchoes
    }

    private var selectedNode: SupportNetworkNode {
        nodes.first { $0.id == selectedNodeID } ?? nodes[0]
    }

    private func nodeActivation(_ node: SupportNetworkNode, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(appearedAt) - node.activationDelay
        return (elapsed / 0.5).clamped(to: 0...1)
    }

    private func nodeVisibility(_ node: SupportNetworkNode, at date: Date) -> Double {
        0.24 + nodeActivation(node, at: date) * 0.76
    }

    private var selectedNodePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(selectedNode.tint.opacity(0.82))
                    .frame(width: 8, height: 8)
                Text(selectedNode.title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("点亮 \(String(format: "%.1fs", selectedNode.activationDelay))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.54))
            }

            ForEach(Array(selectedNode.traceLines.prefix(2).enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(selectedNode.tint.opacity(0.9))
                        .frame(width: 14, alignment: .leading)
                    Text(line)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedNode.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedNode.tint.opacity(0.22), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: selectedNodeID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("支持网络")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(compact ? "五节点" : "五个节点")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                Canvas { context, size in
                    let points = nodes.map { node in
                        CGPoint(x: size.width * node.point.x, y: size.height * node.point.y)
                    }

                    let background = Path(CGRect(origin: .zero, size: size))
                    context.fill(background, with: .linearGradient(
                        Gradient(colors: [
                            campaign.chapter.atmosphere.opacity(0.18),
                            .black.opacity(0.16)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    ))

                    for index in 0..<(points.count - 1) {
                        let a = points[index]
                        let b = points[index + 1]
                        let visible = min(
                            nodeVisibility(nodes[index], at: timeline.date),
                            nodeVisibility(nodes[index + 1], at: timeline.date)
                        )
                        var line = Path()
                        line.move(to: a)
                        line.addLine(to: b)
                        let lineStrength = min(1, (nodes[index].strength + nodes[index + 1].strength) / 2)
                        context.stroke(
                            line,
                            with: .color(.white.opacity((0.08 + lineStrength * 0.18) * visible)),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7])
                        )
                    }

                    for (index, node) in nodes.enumerated() {
                        let point = points[index]
                        let visible = nodeVisibility(node, at: timeline.date)
                        let isSelected = selectedNodeID == node.id
                        let radius = CGFloat(10 + node.strength * 11 + (isSelected ? 4 : 0)) * (0.82 + visible * 0.18)
                        let outer = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                        let inner = CGRect(x: point.x - radius * 0.55, y: point.y - radius * 0.55, width: radius * 1.1, height: radius * 1.1)

                        context.fill(
                            Path(ellipseIn: outer),
                            with: .color(node.tint.opacity((0.16 + node.strength * 0.24) * visible))
                        )
                        context.fill(
                            Path(ellipseIn: inner),
                            with: .radialGradient(
                                Gradient(colors: [
                                    node.tint.opacity((isSelected ? 1 : 0.86) * visible),
                                    .white.opacity(0.28 * visible),
                                    .clear
                                ]),
                                center: CGPoint(x: point.x, y: point.y),
                                startRadius: 0,
                                endRadius: radius
                            )
                        )
                        context.stroke(
                            Path(ellipseIn: outer),
                            with: .color(.white.opacity((isSelected ? 0.42 : 0.18) * visible)),
                            lineWidth: isSelected ? 1.6 : 1
                        )
                        context.draw(
                            Text(node.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(visible)),
                            at: CGPoint(x: point.x, y: point.y + radius + 15),
                            anchor: .top
                        )
                        context.draw(
                            Text(node.detail)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72 * visible)),
                            at: CGPoint(x: point.x, y: point.y + radius + 28),
                            anchor: .top
                        )
                    }
                }
            }
            .frame(height: canvasHeight)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: compact ? 70 : 92), spacing: 8), count: 5), spacing: 8) {
                ForEach(nodes) { node in
                    Button {
                        selectedNodeID = node.id
                    } label: {
                        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
                            HStack {
                                Text(node.title)
                                    .font(.system(size: 10, weight: .bold))
                                Spacer()
                                Text("\(Int(node.strength * 100))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(.white.opacity(0.10))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(node.tint.opacity(0.72))
                                            .frame(width: geo.size.width * node.strength)
                                    }
                            }
                            .frame(height: 5)
                            if compact == false {
                                Text(node.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.64))
                                    .lineLimit(2)
                            }
                        }
                        .padding(compact ? 8 : 10)
                        .frame(maxWidth: .infinity, minHeight: compact ? 52 : 82, alignment: .topLeading)
                        .background(.white.opacity(selectedNodeID == node.id ? 0.105 : 0.06), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(selectedNodeID == node.id ? 0.24 : 0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("查看\(node.title)的本局痕迹")
                }
            }

            if compact == false {
                selectedNodePanel

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 160), spacing: 8), count: 3), spacing: 8) {
                    ForEach(consequenceEchoes.prefix(6)) { echo in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: echo.symbol)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .frame(width: 14)
                                Text(echo.title)
                                    .font(.system(size: 10, weight: .bold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(Int(echo.strength * 100))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.52))
                            }
                            Text(echo.trace)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.66))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(9)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.10 + echo.strength * 0.08), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.46))
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(campaign.chapter.atmosphere.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
    }
}

struct EmpathyReplayView: View {
    let campaign: NarrativeCampaign

    private var beats: [NarrativeEmpathyReplayBeat] {
        campaign.empathyReplayBeats
    }

    private var supportIndex: Double {
        guard beats.isEmpty == false else { return 0 }
        return beats.map(\.empathyScore).reduce(0, +) / Double(beats.count)
    }

    private var pressureIndex: Double {
        guard beats.isEmpty == false else { return 0 }
        return beats.map(\.tensionScore).reduce(0, +) / Double(beats.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.mint)
                Text("同理心回放")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("支持 \(Int(supportIndex * 100)) · 压力 \(Int(pressureIndex * 100))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(beats.prefix(6)) { beat in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: beat.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.82))
                                .frame(width: 13)
                            Text(beat.chapterTitle)
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(beat.playerTrace)
                                .foregroundStyle(.white.opacity(0.78))
                            Text(beat.supportResponse)
                                .foregroundStyle(.mint.opacity(0.74))
                        }
                        .font(.system(size: 8.5, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.10))
                                Capsule()
                                    .fill(.mint.opacity(0.68))
                                    .frame(width: geo.size.width * beat.empathyScore)
                                Capsule()
                                    .fill(.orange.opacity(0.54))
                                    .frame(width: geo.size.width * beat.tensionScore, height: 2)
                                    .offset(y: 4)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.10 + beat.empathyScore * 0.08), lineWidth: 1)
                    )
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }
}

struct TruthReplayView: View {
    let campaign: NarrativeCampaign

    private var reveals: [NarrativeTruthReplayReveal] {
        campaign.truthReplayReveals
    }

    private var revealIndex: Double {
        guard reveals.isEmpty == false else { return 0 }
        return reveals.map(\.revealStrength).reduce(0, +) / Double(reveals.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("真相回放")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("揭示 \(Int(revealIndex * 100))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 148), spacing: 8), count: 2), spacing: 8) {
                ForEach(reveals.prefix(4)) { reveal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: reveal.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.82))
                                .frame(width: 13)
                            Text(reveal.perspective.title)
                                .font(.system(size: 10, weight: .bold))
                            Spacer(minLength: 0)
                            Text("\(Int(reveal.revealStrength * 100))")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.48))
                        }

                        Text(reveal.apparentRead)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(2)
                        Text(reveal.hiddenTruth)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.cyan.opacity(0.78))
                            .lineLimit(2)

                        GeometryReader { geo in
                            Capsule()
                                .fill(.white.opacity(0.10))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(.cyan.opacity(0.68))
                                        .frame(width: geo.size.width * reveal.revealStrength)
                                }
                        }
                        .frame(height: 5)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.10 + reveal.revealStrength * 0.08), lineWidth: 1)
                    )
                    .help(reveal.repairAction)
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }
}

struct PolicyExperimentLabView: View {
    let campaign: NarrativeCampaign

    private var experiments: [NarrativePolicyExperiment] {
        campaign.policyExperiments
    }

    private var bestScenario: NarrativePolicyExperiment? {
        experiments.min { lhs, rhs in
            lhs.missedSignalRisk < rhs.missedSignalRisk
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.yellow)
                Text("制度实验室")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                if let bestScenario {
                    Text("最低漏看 \(Int(bestScenario.missedSignalRisk * 100))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            Text("把同一晚放进不同制度参数里，观察压力、支持和漏看风险怎样改变。")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                ForEach(experiments.prefix(3)) { experiment in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: experiment.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.yellow.opacity(0.9))
                                .frame(width: 14)
                            Text(experiment.title)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }

                        Text(experiment.scheduleText)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                        Text(experiment.ruleText)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.yellow.opacity(0.72))
                            .lineLimit(1)
                        Text(experiment.outcomeLine)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        policyBar(title: "压", value: experiment.pressureIndex, tint: .orange)
                        policyBar(title: "支", value: experiment.supportIndex, tint: .mint)
                        policyBar(title: "漏", value: experiment.missedSignalRisk, tint: .red)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.10 + (1 - experiment.missedSignalRisk) * 0.08), lineWidth: 1)
                    )
                    .help(experiment.premise)
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func policyBar(title: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 12, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.68))
                            .frame(width: geo.size.width * value)
                    }
            }
            .frame(height: 5)
            Text("\(Int(value * 100))")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 22, alignment: .trailing)
        }
    }
}
