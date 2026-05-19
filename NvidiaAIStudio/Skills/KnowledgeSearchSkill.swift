import Foundation

struct KnowledgeSearchSkill: Skill {
    let name = "search_knowledge_base"
    let description = "Searches the internal enterprise knowledge base (PDFs, docs) for relevant procedures, policies, and facts. Use this to lookup company-specific knowledge before answering."
    
    let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "The search query (e.g., 'host cancellation policy', 'how to modify a reservation')"
            ]
        ],
        "required": ["query"]
    ]
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let query = try SkillArgs.getString(args, key: "query")
        
        let context = KnowledgeManager.shared.buildContext(query: query)
        
        if context.isEmpty {
            return "No relevant information found in the Knowledge Base for '\(query)'. Make sure files are loaded in."
        }
        
        return context
    }
}
