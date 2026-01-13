import SwiftUI
import SwiftData

struct StatsView: View {
    @StateObject private var store = StatsDashboardStore()
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]
    @AppStorage("weightUnit") private var weightUnit: String = "lb"
    @State private var activeDetail: MetricDetailModel?
    @State private var showManagePins = false

    private var preferredUnit: WorkoutUnits { WorkoutUnits(from: weightUnit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                topControls
                cardsRow
                minimumStrip
                sections
                alertsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .atlasBackground()
        .atlasBackgroundTheme(.stats)
        .sheet(item: $activeDetail) { detail in
            MetricDetailView(detail: detail, unit: preferredUnit)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showManagePins) {
            KeyLiftManagerView(
                pinned: Binding(
                    get: { store.pinnedLifts },
                    set: { store.pinnedLifts = $0 }
                ),
                availableExercises: store.availableExercises
            )
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            store.updatePreferredUnit(preferredUnit)
            store.updateSessions(Array(allSessions))
        }
        .onChange(of: allSessions) { _, newValue in
            store.updateSessions(Array(newValue))
        }
        .onChange(of: weightUnit) { _, newValue in
            store.updatePreferredUnit(WorkoutUnits(from: newValue))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stats")
                .appFont(.title, weight: .semibold)
                .foregroundStyle(.white)
            Text(store.mode.title)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
        }
    }

    private var topControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $store.mode) {
                ForEach(StatsMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StatsRange.allCases) { range in
                        ChipButton(title: range.title, isSelected: store.range == range) {
                            Haptics.playLightTap()
                            store.range = range
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                ForEach(StatsExerciseFilter.allCases) { filter in
                    ChipButton(title: filter.title, isSelected: store.filter == filter) {
                        Haptics.playLightTap()
                        store.filter = filter
                        if filter == .keyLifts && store.pinnedLifts.isEmpty {
                            showManagePins = true
                        }
                    }
                }
                Spacer()
                Button {
                    Haptics.playLightTap()
                    showManagePins = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
        }
    }

    private var cardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(store.dashboard.cards) { card in
                    TrendCardView(card: card)
                        .frame(width: 220)
                        .onTapGesture {
                            Haptics.playLightTap()
                            if let detail = store.dashboard.detail[card.metric] {
                                activeDetail = detail
                            }
                        }
                }
                if store.dashboard.cards.isEmpty {
                    GlassSkeleton(height: 140, width: 220)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var minimumStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimums")
                .appFont(.section, weight: .bold)
                .foregroundStyle(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.dashboard.minimumStrip) { metric in
                        MinimumStripView(metric: metric)
                    }
                }
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(store.dashboard.sections.prefix(4)) { section in
                SectionCard(section: section) {
                    if let detail = store.dashboard.detail[section.metric] {
                        activeDetail = detail
                    }
                }
            }
        }
    }

    private var alertsSection: some View {
        Group {
            if !store.dashboard.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Alerts")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    ForEach(store.dashboard.alerts) { alert in
                        Text("• \(alert.message)")
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

private struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.footnote, weight: .semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TrendCardView: View {
    let card: TrendCardModel

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title)
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(card.primaryValue)
                            .appFont(.title3, weight: .bold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: arrowName(card.direction))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(card.direction == .down ? Color.red.opacity(0.8) : Color.green.opacity(0.9))
                }
                Text(card.comparisonText)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(card.streakText)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                if let context = card.context {
                    Text(context)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func arrowName(_ direction: TrendDirection) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "arrow.right"
        }
    }
}

private struct MinimumStripView: View {
    let metric: MinimumStripMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            MiniBarChart(series: metric.weekly, baseline: metric.baseline?.floor ?? 0)
                .frame(height: 46)
            if let baseline = metric.baseline {
                Text(baseline.statusText)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MiniBarChart: View {
    let series: [WeeklyMetricValue]
    let baseline: Double

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(series.map(\.value).max() ?? 1, baseline > 0 ? baseline : 1)
            let barWidth = max(6, geo.size.width / CGFloat(max(series.count, 1)) - 4)
            ZStack(alignment: .bottomLeading) {
                if baseline > 0 {
                    let y = geo.size.height * CGFloat(1 - baseline / maxValue)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(series) { point in
                        let height = max(4, CGFloat(point.value / maxValue) * geo.size.height)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.32))
                            .frame(width: barWidth, height: height)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SectionCard: View {
    let section: StatsSectionModel
    var onTap: () -> Void

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .appFont(.body, weight: .semibold)
                        if let description = section.description {
                            Text(description)
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if !section.series.isEmpty {
                    MiniLineChart(series: section.series, baseline: section.baseline)
                        .frame(height: 120)
                }

                if let baseline = section.baseline {
                    Text(baseline.statusText)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }

                if !section.breakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(section.breakdown) { item in
                            HStack {
                                Text(item.title)
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(item.valueText)
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.secondary)
                            }
                            if let detail = item.detail {
                                Text(detail)
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }
}

private struct MiniLineChart: View {
    let series: [WeeklyMetricValue]
    let baseline: BaselineResult?

    var body: some View {
        GeometryReader { geo in
            let values = series.map(\.value)
            let maxValue = max(values.max() ?? 1, baseline?.band?.upperBound ?? 0, baseline?.floor ?? 0, 1)
            let minValue = 0.0
            let points: [CGPoint] = series.enumerated().map { index, point in
                let x = geo.size.width * CGFloat(Double(index) / Double(max(series.count - 1, 1)))
                let normalized = (point.value - minValue) / max(maxValue - minValue, 0.0001)
                let y = geo.size.height * CGFloat(1 - normalized)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                if let band = baseline?.band {
                    let lowerValue = min(band.lowerBound, band.upperBound)
                    let upperValue = max(band.lowerBound, band.upperBound)
                    let lowerY = geo.size.height * CGFloat(1 - lowerValue / maxValue)
                    let upperY = geo.size.height * CGFloat(1 - upperValue / maxValue)
                    let height = max(2, lowerY - upperY)
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: height)
                        .offset(y: upperY)
                }

                if let baseline = baseline {
                    let y = geo.size.height * CGFloat(1 - (baseline.floor / maxValue))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if points.count >= 2 {
                    Path { path in
                        path.move(to: points.first!)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
                } else if let point = points.first {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
        }
    }
}

private struct GlassSkeleton: View {
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
            .fill(Color.white.opacity(0.06))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shimmering()
    }
}

// MARK: - Metric Detail

struct MetricDetailView: View {
    let detail: MetricDetailModel
    let unit: WorkoutUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.title)
                        .appFont(.title3, weight: .semibold)
                    Text(detail.contextLines.first ?? "")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !detail.series.isEmpty {
                MiniLineChart(series: detail.series, baseline: detail.baseline)
                    .frame(height: 180)
            }

            if let baseline = detail.baseline {
                Text(baseline.statusText)
                    .appFont(.body, weight: .semibold)
            }

            if detail.contextLines.count > 1 {
                ForEach(detail.contextLines.dropFirst(), id: \.self) { line in
                    Text(line)
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }

            if !detail.breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(detail.breakdown) { item in
                        HStack {
                            Text(item.title)
                                .appFont(.body, weight: .semibold)
                            Spacer()
                            Text(item.valueText)
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                        if let detail = item.detail {
                            Text(detail)
                                .appFont(.footnote, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(AppStyle.contentPaddingLarge)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

// MARK: - Key lifts manager

private struct KeyLiftManagerView: View {
    @Binding var pinned: [String]
    let availableExercises: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [String] {
        guard searchText.isEmpty == false else { return availableExercises }
        return availableExercises.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Manage Key Lifts")
                    .appFont(.title3, weight: .semibold)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if filtered.isEmpty {
                    Text("No exercises yet.")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(filtered, id: \.self) { name in
                                HStack {
                                    Text(name)
                                        .appFont(.body, weight: .semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if pinned.contains(normalize(name)) {
                                        Image(systemName: "pin.fill")
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Haptics.playLightTap()
                                    toggle(name)
                                }
                                Divider()
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(AppStyle.contentPaddingLarge)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ name: String) {
        let normalized = normalize(name)
        if pinned.contains(normalized) {
            pinned.removeAll { $0 == normalized }
        } else {
            pinned.append(normalized)
        }
    }

    private func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension View {
    func shimmering() -> some View {
        self
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.white.opacity(0.25), Color.white.opacity(0.05)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: -150)
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: UUID())
            )
    }
}
