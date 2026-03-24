import SwiftUI

/// GlassCode-style Skills panel with 2-column grid layout.
struct SkillsPanelView: View {
    @State private var skillStates: [String: Bool] = SkillsPanelView.loadSkillStates()
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    private let registry = SkillRegistry.shared

    private var filteredSkills: [any Skill] {
        let all = Array(registry.allSkills).sorted(by: { $0.name < $1.name })
        if searchText.isEmpty { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }

    private var installedSkills: [any Skill] {
        filteredSkills.filter { skillStates[$0.name] ?? true }
    }

    private var recommendedSkills: [any Skill] {
        filteredSkills.filter { !(skillStates[$0.name] ?? true) }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills").font(.headline)
                    Text("Give NvidiaAIStudio superpowers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search", text: $searchText).textFieldStyle(.plain).font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            Divider().padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Installed section
                    if !installedSkills.isEmpty {
                        Text("Installed")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(installedSkills, id: \.name) { skill in
                                SkillCardView(
                                    skill: skill,
                                    isEnabled: Binding(
                                        get: { skillStates[skill.name] ?? true },
                                        set: { newVal in
                                            skillStates[skill.name] = newVal
                                            SkillsPanelView.saveSkillStates(skillStates)
                                            if newVal { registry.enable(skill.name) } else { registry.disable(skill.name) }
                                        }
                                    )
                                )
                            }
                        }
                    }

                    // Recommended section
                    if !recommendedSkills.isEmpty {
                        Divider().opacity(0.3)

                        Text("Recommended")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(recommendedSkills, id: \.name) { skill in
                                SkillCardView(
                                    skill: skill,
                                    isEnabled: Binding(
                                        get: { skillStates[skill.name] ?? true },
                                        set: { newVal in
                                            skillStates[skill.name] = newVal
                                            SkillsPanelView.saveSkillStates(skillStates)
                                            if newVal { registry.enable(skill.name) } else { registry.disable(skill.name) }
                                        }
                                    )
                                )
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()
            HStack(spacing: 6) {
                Image(systemName: "puzzlepiece.extension.fill").font(.caption).foregroundStyle(.secondary)
                Text("Skills extend the AI's capabilities with tools and integrations.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
        .frame(width: 520, height: 580)
    }

    static func loadSkillStates() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: "skillStates") as? [String: Bool] ?? [:]
    }
    static func saveSkillStates(_ states: [String: Bool]) {
        UserDefaults.standard.set(states, forKey: "skillStates")
    }
}

// MARK: - Skill Card

struct SkillCardView: View {
    let skill: any Skill
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorForSkill(skill.name).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: iconForSkill(skill.name))
                        .font(.title3)
                        .foregroundStyle(isEnabled ? colorForSkill(skill.name) : .gray)
                }
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Text(displayName(skill.name))
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(skill.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .glassEffect(isEnabled ? .regular : .regular.tint(.white.opacity(0.02)), in: RoundedRectangle(cornerRadius: 12))
    }

    private func displayName(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private func iconForSkill(_ name: String) -> String {
        switch name {
        case "read_file":       return "doc.text.fill"
        case "write_file":      return "square.and.pencil"
        case "list_directory":  return "folder.fill"
        case "search_files":    return "magnifyingglass"
        case "run_command":     return "terminal.fill"
        case "generate_image":  return "photo.fill"
        case "git":             return "arrow.triangle.branch"
        case "ssh_command":     return "network"
        case "fetch_url":       return "globe"
        case "fetch_images":    return "eye.fill"
        case "web_search":      return "magnifyingglass.circle.fill"
        default:                return "puzzlepiece.fill"
        }
    }

    private func colorForSkill(_ name: String) -> Color {
        switch name {
        case "read_file":       return .blue
        case "write_file":      return .orange
        case "list_directory":  return .cyan
        case "search_files":    return .purple
        case "run_command":     return .green
        case "generate_image":  return .pink
        case "git":             return .red
        case "ssh_command":     return .teal
        case "fetch_url":       return .indigo
        case "fetch_images":    return .yellow
        case "web_search":      return .mint
        default:                return .gray
        }
    }
}
