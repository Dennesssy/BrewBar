// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

struct TaskConsoleView: View {
    let message: String
    let progress: Double?
    let command: String?
    let output: String
    
    @State private var isExpanded = false
    @ObservedObject private var brewService = BrewService.shared

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            VStack(spacing: 6) {
                HStack {
                    Button(action: {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let percent = progress {
                        Text("\(Int(percent * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Cancel") {
                        Task {
                            await brewService.cancelActiveTask()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.leading, 8)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                
                if let percent = progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * CGFloat(percent)))
                                .animation(.linear(duration: 0.2), value: percent)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                } else {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if let command = command {
                        HStack {
                            Text(command)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Copy command")
                        }
                        .padding(8)
                        .background(Color(NSColor.windowBackgroundColor))
                        Divider()
                    }
                    
                    ScrollView {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 150)
                    .background(Color(NSColor.textBackgroundColor))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
