import SwiftUI

/// Panel showing all registered skills with toggle switches.
struct SkillsPanelView: View {
    @State private var skillStates: [String: Bool] = SkillsPanelView.loadSkillStates()
    @Environment(\.dismiss) private var dismiss
    
    private let registry = SkillRegistry.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Skills")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            Text("Enable or disable skills. Disabled skills won't be available to the AI.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Skills list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(registry.allSkills).sorted(by: { $0.name < $1.name }), id: \.name) { skill in
                        SkillRowView(
                            skill: skill,
                            isEnabled: Binding(
                                get: { skillStates[skill.name] ?? true },
                                set: { newVal in
                                    skillStates[skill.name] = newVal
                                    SkillsPanelView.saveSkillStates(skillStates)
                                    if newVal {
                                        registry.enable(skill.name)
                                    } else {
                                        registry.disable(skill.name)
                                    }
                                }
                            )
                        )
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 450)
    }
    
    static func loadSkillStates() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: "skillStates") as? [String: Bool] ?? [:]
    }
    
    static func saveSkillStates(_ states: [String: Bool]) {
        UserDefaults.standard.set(states, forKey: "skillStates")
    }
}

struct SkillRowView: View {
    let skill: any Skill
    @Binding var isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForSkill(skill.name))
                .font(.title3)
                .foregroundStyle(isEnabled ? colorForSkill(skill.name) : .gray)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(skill.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(isEnabled ? 0.03 : 0))
        )
    }
    
    private func iconForSkill(_ name: String) -> String {
        switch name {
        case "read_file": return "doc.text.fill"
        case "write_file": return "square.and.pencil"
        case "list_directory": return "folder.fill"
        case "search_files": return "magnifyingglass"
        case "run_command": return "terminal.fill"
        case "generate_image": return "photo.fill"
        case "git": return "arrow.triangle.branch"
        case "ssh_command": return "network"
        default: return "puzzlepiece.fill"
        }
    }
    
    private func colorForSkill(_ name: String) -> Color {
        switch name {
        case "read_file": return .blue
        case "write_file": return .orange
        case "list_directory": return .cyan
        case "search_files": return .purple
        case "run_command": return .green
        case "generate_image": return .pink
        case "git": return .red
        case "ssh_command": return .teal
        default: return .gray
        }
    }
}
