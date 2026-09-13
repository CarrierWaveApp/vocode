import SwiftUI

/// Searchable picker over the AllStarLink node directory. Tapping a node
/// sets the bound target; a Custom section keeps free-text entry for
/// private nodes not in the directory.
struct NodePickerView: View {
    // MARK: Internal

    @Binding var node: String

    var body: some View {
        Form {
            Section {
                ForEach(filtered) { node in
                    row(node)
                }
            } header: {
                SectionLabel(directory.refreshing ? "Nodes · updating directory" : "Nodes")
            } footer: {
                FooterNote("Showing up to \(Self.maxRows) matches. Search by node number, callsign, or location.")
            }
            Section {
                TextField("Node number", text: $customNode)
                    .keyboardType(.numberPad)
                    .font(CW.mono(14))
                Button {
                    node = trimmedCustomNode
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text("Use this node")
                            .font(CW.sans(15))
                        if node == trimmedCustomNode, !trimmedCustomNode.isEmpty {
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
            if directory.node(forNumber: node) == nil {
                customNode = node
            }
        }
    }

    // MARK: Private

    private static let maxRows = 200

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var directory = ASLDirectory.shared
    @State private var search = ""
    @State private var customNode = ""

    private var trimmedCustomNode: String {
        customNode.trimmingCharacters(in: .whitespaces).filter(\.isNumber)
    }

    private var filtered: [ASLNode] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            return Array(directory.all.prefix(Self.maxRows))
        }
        var matches: [ASLNode] = []
        for node in directory.all where matches.count < Self.maxRows {
            if node.node.hasPrefix(needle)
                || node.callsign.lowercased().contains(needle)
                || node.desc.lowercased().contains(needle)
                || node.location.lowercased().contains(needle)
            {
                matches.append(node)
            }
        }
        return matches
    }

    private func row(_ entry: ASLNode) -> some View {
        Button {
            node = entry.node
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.node)
                    .font(CW.mono(14, medium: true))
                    .foregroundStyle(CW.blue)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.callsign)
                            .font(CW.sans(14, .medium))
                            .foregroundStyle(CW.white)
                        if node == entry.node {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CW.green)
                        }
                    }
                    Text([entry.desc, entry.location].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(CW.mono(11))
                        .foregroundStyle(CW.dim)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }
}
