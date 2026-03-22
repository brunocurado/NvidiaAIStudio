import SwiftUI

/// Usage panel showing real token consumption tracked locally.
struct UsagePanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [UsageStore.Record] = []
    @State private var dailyData: [(label: String, tokens: Int)] = []
    @State private var topModels: [(modelName: String, tokens: Int)] = []
    @State private var byProvider: [(provider: String, tokens: Int)] = []
    @State private var showClearConfirm = false

    private var totalToday: Int { UsageStore.shared.tokensToday() }
    private var totalAll: Int { UsageStore.shared.totalTokens() }
    private var maxDaily: Int { dailyData.map(\.tokens).max() ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Usage")
                    .font(.headline)
                Spacer()
                Button("Clear History") { showClearConfirm = true }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Summary Cards ──
                    HStack(spacing: 12) {
                        StatCard(
                            title: "Today",
                            value: formatTokens(totalToday),
                            icon: "sun.max.fill",
                            color: .orange
                        )
                        StatCard(
                            title: "All Time",
                            value: formatTokens(totalAll),
                            icon: "infinity",
                            color: .blue
                        )
                        StatCard(
                            title: "Sessions",
                            value: "\(records.count)",
                            icon: "bubble.left.and.bubble.right.fill",
                            color: .purple
                        )
                    }

                    // ── 7-Day Bar Chart ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 7 Days")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if dailyData.allSatisfy({ $0.tokens == 0 }) {
                            Text("No usage recorded yet. Start a conversation to see data here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            HStack(alignment: .bottom, spacing: 6) {
                                ForEach(dailyData, id: \.label) { day in
                                    VStack(spacing: 4) {
                                        if day.tokens > 0 {
                                            Text(formatTokens(day.tokens))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                        }
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(day.tokens > 0 ? Color.blue : Color.white.opacity(0.08))
                                            .frame(
                                                height: max(4, CGFloat(day.tokens) / CGFloat(maxDaily) * 80)
                                            )
                                        Text(day.label)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 110)
                        }
                    }
                    .padding()
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    // ── By Provider ──
                    if !byProvider.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Provider")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            HStack(spacing: 10) {
                                ForEach(byProvider, id: \.provider) { entry in
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .fill(providerColor(entry.provider).opacity(0.15))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: providerIcon(entry.provider))
                                                .font(.title3)
                                                .foregroundStyle(providerColor(entry.provider))
                                        }
                                        Text(entry.provider)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(formatTokens(entry.tokens))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding()
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // ── Top Models ──
                    if !topModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Model")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            ForEach(topModels, id: \.modelName) { entry in
                                HStack(spacing: 10) {
                                    Text(entry.modelName
                                        .drop(while: { !$0.isLetter && !$0.isNumber })
                                        .components(separatedBy: "—").first?
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
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                        }
                        .padding()
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // ── Recent Sessions ──
                    if !records.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Sessions")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            ForEach(records.suffix(10).reversed()) { record in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.sessionTitle)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(formatTokens(record.totalTokens))
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        HStack(spacing: 4) {
                                            Text("↑\(formatTokens(record.promptTokens))")
                                            Text("↓\(formatTokens(record.completionTokens))")
                                        }
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)

                                if record.id != records.suffix(10).reversed().last?.id {
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                        .padding()
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Text("Token counts are reported directly by the NVIDIA NIM API.\nData is stored locally on your Mac and never shared.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
        .frame(width: 460, height: 580)
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
        records = UsageStore.shared.load()
        dailyData = UsageStore.shared.tokensByDay()
        topModels = UsageStore.shared.topModels()
        byProvider = UsageStore.shared.tokensByProvider()
    }

    private func providerColor(_ provider: String) -> Color {
        switch provider {
        case "NVIDIA NIM": return .green
        case "Anthropic":  return .orange
        case "OpenAI":     return .teal
        case "Custom":     return .purple
        default:           return .blue
        }
    }

    private func providerIcon(_ provider: String) -> String {
        switch provider {
        case "NVIDIA NIM": return "cpu.fill"
        case "Anthropic":  return "brain.fill"
        case "OpenAI":     return "sparkles"
        case "Custom":     return "server.rack"
        default:           return "cloud.fill"
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
