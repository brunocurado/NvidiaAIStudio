import SwiftUI

/// GlassCode-style Usage Dashboard with heatmap, stats, and streaks.
struct UsagePanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [UsageStore.Record] = []
    @State private var heatmapGrid: [[Int]] = Array(repeating: Array(repeating: 0, count: 53), count: 7)
    @State private var topModels: [(modelName: String, tokens: Int)] = []
    @State private var showClearConfirm = false

    private let store = UsageStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(store.sessionsActiveToday()) active today \u{00B7} \(store.sessionsInLast30Days()) sessions in 30 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    PillBadge(text: "Updated just now")
                    PillBadge(text: "Local Storage")
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── 4 Stat Cards ──
                    HStack(spacing: 10) {
                        UsageStatCard(value: "\(store.projectCount())", label: "Projects", dotColor: .blue)
                        UsageStatCard(value: "\(store.sessionsInLast30Days())", label: "Sessions", dotColor: .blue)
                        UsageStatCard(value: "\(store.messagesInLast7Days())", label: "Msgs (7d)", dotColor: .blue)
                        UsageStatCard(value: "\(store.weekUsagePercent())%", label: "Week used", dotColor: .blue)
                    }

                    // ── Session & Weekly progress ──
                    HStack(spacing: 10) {
                        UsageProgressCard(
                            title: "Current session",
                            subtitle: "5-hour rolling window",
                            percent: min(100, store.tokensToday() * 100 / max(1, store.totalTokens() / max(1, records.count))),
                            accentColor: .blue,
                            footnote: "From local usage"
                        )
                        UsageProgressCard(
                            title: "Weekly",
                            subtitle: "All models",
                            percent: store.weekUsagePercent(),
                            accentColor: .green,
                            footnote: "From local usage"
                        )
                    }

                    // ── Token Activity Heatmap ──
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Token Activity")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()

                            HStack(spacing: 16) {
                                TokenStatLabel(label: "INPUT TOKENS", value: formatTokens(store.totalInputTokens()))
                                TokenStatLabel(label: "OUTPUT TOKENS", value: formatTokens(store.totalOutputTokens()))
                                TokenStatLabel(label: "TOTAL TOKENS", value: formatTokens(store.totalTokens()))
                            }
                        }

                        Text("Daily token history across the last 53 weeks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TokenActivityHeatmap(grid: heatmapGrid, maxValue: heatmapGrid.flatMap { $0 }.max() ?? 1)

                        // Footer stats row
                        HStack(spacing: 0) {
                            FooterStat(label: "MOST USED MODEL", value: topModels.first?.modelName.components(separatedBy: "\u{2014}").first?.trimmingCharacters(in: .whitespaces) ?? "—")
                            FooterStat(label: "RECENT USE (30D)", value: topModels.first.map { formatTokens($0.tokens) } ?? "—")
                            FooterStat(label: "LONGEST STREAK", value: "\(store.longestStreak()) days")
                            FooterStat(label: "CURRENT STREAK", value: "\(store.currentStreak()) days")
                        }
                    }
                    .padding(16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))

                    // ── By Model breakdown ──
                    if !topModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Model")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            ForEach(topModels, id: \.modelName) { entry in
                                HStack(spacing: 10) {
                                    Text(entry.modelName
                                        .drop(while: { !$0.isLetter && !$0.isNumber })
                                        .components(separatedBy: "\u{2014}").first?
                                        .trimmingCharacters(in: .whitespaces) ?? entry.modelName
                                    )
                                    .font(.caption)
                                    .lineLimit(1)
                                    Spacer()
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.blue.opacity(0.6))
                                            .frame(
                                                width: max(4, geo.size.width * CGFloat(entry.tokens) / CGFloat(topModels.first?.tokens ?? 1)),
                                                height: 6
                                            )
                                            .frame(maxHeight: .infinity, alignment: .center)
                                    }
                                    .frame(width: 120, height: 14)
                                    Text(formatTokens(entry.tokens))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 55, alignment: .trailing)
                                }
                            }
                        }
                        .padding(16)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                    }

                    // ── Footer note ──
                    Text("Token counts are reported directly by the API provider.\nData is stored locally on your Mac and never shared.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Clear button
                    HStack {
                        Spacer()
                        Button("Clear History", role: .destructive) { showClearConfirm = true }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
                .padding()
            }
        }
        .frame(width: 720, height: 680)
        .onAppear { reload() }
        .confirmationDialog("Clear all usage history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                UsageStore.shared.clear()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func reload() {
        records = store.load()
        heatmapGrid = store.tokensByWeekdayAndWeek()
        topModels = store.topModels()
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Subviews

private struct PillBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08), in: Capsule())
    }
}

private struct UsageStatCard: View {
    let value: String
    let label: String
    let dotColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            HStack(spacing: 4) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct UsageProgressCard: View {
    let title: String
    let subtitle: String
    let percent: Int
    let accentColor: Color
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("\(percent)%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor)
                        .frame(width: geo.size.width * CGFloat(min(percent, 100)) / 100, height: 6)
                }
            }
            .frame(height: 6)

            Text(footnote)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TokenStatLabel: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

private struct FooterStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Token Activity Heatmap

private struct TokenActivityHeatmap: View {
    let grid: [[Int]] // [7 weekdays][53 weeks]
    let maxValue: Int

    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 2

    private let heatmapColors: [Color] = [
        Color(red: 0.15, green: 0.18, blue: 0.25),
        Color(red: 0.15, green: 0.30, blue: 0.55),
        Color(red: 0.20, green: 0.45, blue: 0.75),
        Color(red: 0.30, green: 0.55, blue: 0.90),
        Color(red: 0.45, green: 0.70, blue: 1.00),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Month labels
            HStack(spacing: 0) {
                Text("").frame(width: 28) // weekday label spacer
                ForEach(0..<53, id: \.self) { week in
                    if week % 4 == 0 {
                        Text(monthLabel(forWeek: week))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: (cellSize + cellSpacing) * 4, alignment: .leading)
                    }
                }
            }

            HStack(alignment: .top, spacing: cellSpacing) {
                // Weekday labels
                VStack(spacing: cellSpacing) {
                    Text("Mon").font(.system(size: 8)).foregroundStyle(.secondary).frame(height: cellSize)
                    Text("").frame(height: cellSize)
                    Text("Wed").font(.system(size: 8)).foregroundStyle(.secondary).frame(height: cellSize)
                    Text("").frame(height: cellSize)
                    Text("Fri").font(.system(size: 8)).foregroundStyle(.secondary).frame(height: cellSize)
                    Text("").frame(height: cellSize)
                    Text("Sun").font(.system(size: 8)).foregroundStyle(.secondary).frame(height: cellSize)
                }
                .frame(width: 24)

                ForEach(0..<53, id: \.self) { week in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorForValue(grid[day][week]))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 9)).foregroundStyle(.secondary)
                ForEach(heatmapColors.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapColors[i])
                        .frame(width: cellSize, height: cellSize)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    private func colorForValue(_ value: Int) -> Color {
        guard maxValue > 0 && value > 0 else { return heatmapColors[0] }
        let ratio = Double(value) / Double(maxValue)
        let index = min(4, Int(ratio * 4) + 1)
        return heatmapColors[index]
    }

    private func monthLabel(forWeek week: Int) -> String {
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        guard let date = Calendar.current.date(byAdding: .weekOfYear, value: -(52 - week), to: Date()) else { return "" }
        let month = Calendar.current.component(.month, from: date) - 1
        return months[month]
    }
}
