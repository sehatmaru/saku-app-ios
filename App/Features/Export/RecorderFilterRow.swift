import SwiftUI

/// A8 (14): in a shared Workspace, limits an export to one member's records. Hidden in Workspace Pribadi.
struct RecorderFilterRow: View {
    @ObservedObject var viewModel: ExportViewModel

    var body: some View {
        if viewModel.isShared, !viewModel.members.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Dicatat oleh")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(L("Semua anggota"), selected: viewModel.recorder == nil) { viewModel.recorder = nil }
                        ForEach(viewModel.members) { member in
                            let id = member.profileId.uuidString.lowercased()
                            chip(label(member), selected: viewModel.recorder == id) { viewModel.recorder = id }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    /// Two members can share a name: the one signed in is marked "(kamu)", the others with a twin get a number.
    private func label(_ member: WorkspaceMember) -> String {
        if member.isFormer { return L("Mantan anggota") }
        if member.isMe { return "\(member.name) (\(L("kamu")))" }
        let twins = viewModel.members.filter { !$0.isMe && !$0.isFormer && $0.name == member.name }
        guard twins.count > 1, let index = twins.firstIndex(where: { $0.id == member.id }) else { return member.name }
        return "\(member.name) (\(index + 1))"
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Color.appText)
                .padding(.horizontal, 12).frame(height: 34)
                .background(selected ? Color.stGreen : Color.appBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}
