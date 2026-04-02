import SwiftUI

/// Parse ANSI escape codes into a colored AttributedString.
struct TerminalOutputLine: Identifiable {
    let id = UUID()
    let raw: String
    
    var attributed: AttributedString {
        ANSIParser.parse(raw)
    }
}

/// Parses ANSI escape sequences into styled AttributedString.
enum ANSIParser {
    // Regex to match ANSI escape sequences: ESC[ ... m
    private static let ansiPattern = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*m", options: [])
    // Also strip other escape sequences (cursor movement, etc.) plus private-mode CSI sequences [?2004h etc.
    private static let otherEscapes = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[A-HJKSTfn]|\\x1B\\].*?\\x07|\\x1B\\(B|\\x1B\\[\\?[0-9;]*[a-zA-Z]", options: [])
    
    static func parse(_ raw: String) -> AttributedString {
        var clean = otherEscapes.stringByReplacingMatches(
            in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: ""
        )
        // Strip trailing \r which is just part of \r\n line endings
        if clean.hasSuffix("\r") {
            clean.removeLast()
        }
        
        var result = AttributedString()
        var currentColor: Color = .primary
        var isBold = false
        var isDim = false
        
        let nsString = clean as NSString
        let matches = ansiPattern.matches(in: clean, range: NSRange(location: 0, length: nsString.length))
        
        var lastEnd = 0
        
        for match in matches {
            // Text before this escape sequence
            if match.range.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let text = nsString.substring(with: textRange)
                
                var processedChars = [Character]()
                for char in text {
                    if char == "\u{08}" || char == "\u{7F}" { // Backspace or DEL
                        if !processedChars.isEmpty {
                            processedChars.removeLast()
                        } else if !result.characters.isEmpty {
                            result.characters.removeLast()
                        }
                    } else if char == "\r" { // Carriage Return
                        continue // Ignore instead of wiping the line!
                    } else if char == "\u{07}" { // Bell
                        continue
                    } else {
                        processedChars.append(char)
                    }
                }
                
                if !processedChars.isEmpty {
                    var attr = AttributedString(String(processedChars))
                    attr.foregroundColor = isDim ? currentColor.opacity(0.6) : currentColor
                    if isBold { attr.font = .system(size: 12, weight: .bold, design: .monospaced) }
                    result += attr
                }
            }
            
            // Parse the escape code
            let code = nsString.substring(with: match.range)
            let numbers = code.dropFirst(2).dropLast()
                .split(separator: ";")
                .compactMap { Int($0) }
            
            for num in (numbers.isEmpty ? [0] : numbers) {
                switch num {
                case 0:  currentColor = .primary; isBold = false; isDim = false
                case 1:  isBold = true
                case 2:  isDim = true
                case 22: isBold = false; isDim = false
                case 30: currentColor = Color(.darkGray)
                case 31: currentColor = Color(.systemRed)
                case 32: currentColor = Color(.systemGreen)
                case 33: currentColor = Color(.systemYellow)
                case 34: currentColor = Color(.systemBlue)
                case 35: currentColor = Color(.systemPurple)
                case 36: currentColor = Color(.systemTeal)
                case 37: currentColor = .white
                case 39: currentColor = .primary
                case 90: currentColor = .gray
                case 91: currentColor = Color(.systemRed).opacity(0.8)
                case 92: currentColor = Color(.systemGreen).opacity(0.8)
                case 93: currentColor = Color(.systemYellow).opacity(0.8)
                case 94: currentColor = Color(.systemBlue).opacity(0.8)
                case 95: currentColor = Color(.systemPurple).opacity(0.8)
                case 96: currentColor = Color(.systemTeal).opacity(0.8)
                case 97: currentColor = .white
                default: break
                }
            }
            
            lastEnd = match.range.location + match.range.length
        }
        
        // Remaining text after last escape
        if lastEnd < nsString.length {
            let text = nsString.substring(from: lastEnd)
            var processedChars = [Character]()
            for char in text {
                if char == "\u{08}" || char == "\u{7F}" {
                    if !processedChars.isEmpty {
                        processedChars.removeLast()
                    } else if !result.characters.isEmpty {
                        result.characters.removeLast()
                    }
                } else if char == "\r" {
                    // Ignore carriage returns at the end of lines instead of wiping the buffer,
                    // which prevents valid commands like `date` from disappearing!
                    continue
                } else if char == "\u{07}" {
                    continue
                } else {
                    processedChars.append(char)
                }
            }
            if !processedChars.isEmpty {
                var attr = AttributedString(String(processedChars))
                attr.foregroundColor = isDim ? currentColor.opacity(0.6) : currentColor
                if isBold { attr.font = .system(size: 12, weight: .bold, design: .monospaced) }
                result += attr
            }
        }
        
        // If no escapes found and result is empty after processing, return empty.
        // The original clean string might have been entirely erased by \b or \r.
        // Wait, if no escapes, lastEnd is 0, so the block above handles it perfectly!
        // We can just return result.
        
        return result
    }
}
