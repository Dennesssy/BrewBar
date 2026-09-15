import sys

path = "/Users/denn/Desktop/Xcode/BrewBar/Sources/BrewBarKit/Utilities/ProcessManager.swift"
with open(path, "r") as f:
    content = f.read()

target = """            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_INTERACTIVE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            process.environment = env"""

replacement = """            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_INTERACTIVE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            
            // Generate an Apple-approved native authentication dialog for sudo prompts
            let askpassPath = FileManager.default.temporaryDirectory.appendingPathComponent("brewbar_askpass.sh").path
            if !FileManager.default.fileExists(atPath: askpassPath) {
                let script = \"\"\"
                #!/bin/bash
                osascript -e 'tell application "SystemUIServer" to activate' -e 'tell application "SystemUIServer" to text returned of (display dialog "Homebrew requires your administrator password to manage a Cask." default answer "" with hidden answer with title "BrewBar Authentication")'
                \"\"\"
                try? script.write(toFile: askpassPath, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: askpassPath)
            }
            env["SUDO_ASKPASS"] = askpassPath
            
            process.environment = env"""

if target in content:
    content = content.replace(target, replacement)
    with open(path, "w") as f:
        f.write(content)
    print("Patched successfully")
else:
    print("Target block not found!")
