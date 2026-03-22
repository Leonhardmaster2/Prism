import SwiftUI

struct FormattingToolbar: View {
    let editorState: EditorStateInfo
    let onCommand: (String, [String: Any]?) -> Void

    @State private var showHeadingPicker = false

    var body: some View {
        HStack(spacing: 2) {
            if editorState.hasSelection {
                inlineMode
            } else {
                blockMode
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .modifier(GlassToolbarModifier())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Block Mode (no selection)

    private var blockMode: some View {
        Group {
            toolbarButton("paragraph", icon: "text.alignleft",
                          active: editorState.headingLevel == 0 && !editorState.isInList && !editorState.isInBlockquote && !editorState.isInCodeBlock)
            headingPicker
            divider
            toolbarButton("bulletList", icon: "list.bullet",
                          active: editorState.isInList && editorState.listType == "bullet")
            toolbarButton("orderedList", icon: "list.number",
                          active: editorState.isInList && editorState.listType == "ordered")
            toolbarButton("taskList", icon: "checklist",
                          active: false)
            divider
            toolbarButton("blockquote", icon: "text.quote",
                          active: editorState.isInBlockquote)
            toolbarButton("codeBlock", icon: "chevron.left.forwardslash.chevron.right",
                          active: editorState.isInCodeBlock)
            toolbarButton("insertTable", icon: "tablecells",
                          active: false)
            divider
            toolbarButton("insertMathBlock", icon: "function",
                          active: false)
            toolbarButton("horizontalRule", icon: "minus",
                          active: false)
        }
    }

    // MARK: - Inline Mode (text selected)

    private var inlineMode: some View {
        Group {
            toolbarButton("bold", icon: "bold",
                          active: editorState.isBold)
            toolbarButton("italic", icon: "italic",
                          active: editorState.isItalic)
            toolbarButton("strikethrough", icon: "strikethrough",
                          active: editorState.isStrikethrough)
            toolbarButton("inlineCode", icon: "chevron.left.forwardslash.chevron.right",
                          active: editorState.isInlineCode)
            divider
            toolbarButton("link", icon: "link",
                          active: false)
            toolbarButton("highlight", icon: "highlighter",
                          active: false)
            divider
            toolbarButton("subscript", icon: "textformat.subscript",
                          active: false)
            toolbarButton("superscript", icon: "textformat.superscript",
                          active: false)
        }
    }

    // MARK: - Heading Picker

    private var headingPicker: some View {
        Menu {
            ForEach(1...6, id: \.self) { level in
                Button {
                    onCommand("heading", ["level": level])
                } label: {
                    HStack {
                        Text("H\(level)")
                            .font(.system(size: headingFontSize(level), weight: level <= 3 ? .bold : .semibold, design: .rounded))
                        Spacer()
                        Text("Heading \(level)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            Text(editorState.headingLevel > 0 ? "H\(editorState.headingLevel)" : "H")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(editorState.headingLevel > 0 ? Color.accentColor : .secondary)
                .frame(width: 32, height: 26)
                .background(
                    editorState.headingLevel > 0
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 17
        case 2: return 15
        case 3: return 14
        default: return 12
        }
    }

    // MARK: - Reusable Button

    private func toolbarButton(_ command: String, icon: String, active: Bool) -> some View {
        Button {
            onCommand(command, nil)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 32, height: 26)
                .background(
                    active ? Color.accentColor.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 3)
    }
}

private struct GlassToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
        } else {
            content
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        }
                }
                .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
        }
    }
}
