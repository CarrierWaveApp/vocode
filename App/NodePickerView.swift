import SwiftUI

/// Searchable picker over the AllStarLink node directory. Tapping a node
/// sets the AllStar target; a Custom section keeps free-text entry for
/// private nodes not in the directory.
struct NodePickerView: View {
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var directory = ASLDirectory.shared
    @State private var search = ""
    @State private var customNode = ""

    private static let maxRows = 200

    private var trimmedCustomNode: String {
        customNode.trimmingCharacters(in: .whitespaces).filter(\.isNumber)
    }

    private var filtered: [ASLNode] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Array(directory.all.prefix(Self.maxRows)) }
        var matches: [ASLNode] = []
        for node in directory.all where matches.count < Self.maxRows {
            if node.node.hasPrefix(needle)
                || node.callsign.lowercased().contains(needle)
                || node.desc.lowercased().contains(needle)
                || node.location.lowercased().contains(needle) {
                matches.append(node)
            }
        }
        return matches
    }

    var body: some View {
        Form {
            Section {
                ForEach(filtered) { node in
                    row(node)
                }
            } header: {
                SectionLabel(directory.refreshing ? "Nodes · updating directory" : "Nodes")
            } footer: {
                Text("Showing up to \(Self.maxRows) matches. Search by node number, callsign, or location.")
                    .font(CW.mono(11))
                    .foregroundStyle(CW.dim)
            }
            Section {
                TextField("Node number", text: $customNode)
                    .keyboardType(.numberPad)
                    .font(CW.mono(14))
                Button {
                    settings.aslTarget = trimmedCustomNode
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text("Use this node")
                            .font(CW.sans(15))
                        if settings.aslTarget == trimmedCustomNode, !trimmedCustomNode.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CW.green)
                        }
                    }
                }
                .disabled(trimmedCustomNode.isEmpty)
            } header: {
                SectionLabel("Custom")
            }
        }
        .cwList()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("AllStar nodes")
        .toolbarBackground(CW.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            directory.loadIfNeeded()
            if directory.node(forNumber: settings.aslTarget) == nil {
                customNode = settings.aslTarget
            }
        }
    }

    private func row(_ node: ASLNode) -> some View {
        Button {
            settings.aslTarget = node.node
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(node.node)
                    .font(CW.mono(14, medium: true))
                    .foregroundStyle(CW.blue)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(node.callsign)
                            .font(CW.sans(14, .medium))
                            .foregroundStyle(CW.white)
                        if settings.aslTarget == node.node {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CW.green)
                        }
                    }
                    Text([node.desc, node.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }
}
