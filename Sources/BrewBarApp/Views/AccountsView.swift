// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct AccountsView: View {
    @StateObject private var viewModel = AccountsViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with which-account indicator
                HStack {
                    Text("Accounts")
                        .font(.largeTitle)
                        .bold()
                    Spacer()
                    VStack(alignment: .trailing) {
                        if let gh = viewModel.activeGhAccount {
                            Text("gh: \(gh)").font(.caption).foregroundColor(.secondary)
                        }
                        if let gcloud = viewModel.activeGcloudAccount {
                            Text("gcloud: \(gcloud)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Button(action: {
                        Task {
                            await viewModel.refresh()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding(.bottom, 10)

                if viewModel.isLoading {
                    ProgressView("Checking CLI statuses...")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("CLI Status")
                        .font(.headline)
                    
                    ForEach(viewModel.cliStatuses) { status in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(status.name).font(.headline)
                                Spacer()
                                Text(status.stateString)
                                    .foregroundColor(status.state == .loggedIn ? .green : (status.state == .notLoggedIn ? .orange : .secondary))
                            }
                            if let account = status.account {
                                Text("Account: \(account)")
                                    .font(.subheadline)
                            }
                            if let cmd = status.commandUsed {
                                Text(cmd)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    Text("Credential Hygiene")
                        .font(.headline)
                        .padding(.top, 10)

                    if viewModel.hygieneIssues.isEmpty {
                        Text("No hygiene issues found.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(viewModel.hygieneIssues) { issue in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(issue.path)
                                    .font(.headline)
                                Text("Permissions: \(issue.permissionsString) (Warning: may contain credentials)")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                Text("chmod 600 \(issue.path)")
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .padding(4)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(4)
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
        }
        .task {
            await viewModel.refresh()
        }
    }
}
