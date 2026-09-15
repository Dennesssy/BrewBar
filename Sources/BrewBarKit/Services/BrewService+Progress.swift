// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

extension BrewService {
    @MainActor
    func parseProgressOutput(_ output: String, defaultMessage: String) {
        if activeTaskMessage == nil {
            activeTaskMessage = defaultMessage
        }
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("==> ") {
                activeTaskMessage = line.replacingOccurrences(of: "==> ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Parse download progress: "Downloading... 45.0%"
            if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)%"#) {
                let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                if let match = matches.last, let range = Range(match.range(at: 1), in: line), let percent = Double(line[range]) {
                    activeTaskProgress = percent / 100.0
                }
            }
        }
    }
    
    @MainActor
    func resetProgress() {
        activeTaskMessage = nil
        activeTaskProgress = nil
    }
}
