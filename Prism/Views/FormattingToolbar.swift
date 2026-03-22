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
        .padding(.horizontal, KSpacing.nano)
        .padding(.vertical, 6)
        .modifier(GlassToolbarModifier())
        .padding(.horizontal, KSpacing.micro)
        .padding(.bottom, KSpacing.nano)
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
                    KHaptics.light()
                    onCommand("heading", ["level": level])
                } label: {
                    HStack {
                        Text("H\(level)")
                            .font(.system(size: headingFontSize(level), weight: level <= 3 ? .bold : .semibold, design: .rounded))
                        Spacer()
                        Text("Heading \(level)")
                            .khagwalCaption()
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
                    in: RoundedRectangle(cornerRadius: KSpacing.nano, style: .continuous)
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
            KHaptics.light()
            onCommand(command, nil)
        } label: {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 32, height: 26)
                .background(
                    active ? Color.accentColor.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: KSpacing.nano, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Divider()
            .frame(height: KSpacing.micro)
            .padding(.horizontal, 3)
    }
}

private struct GlassToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
                .khagwalShadow()
        } else {
            content
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .strokeBorder(KColors.border, lineWidth: 1)
                        }
                }
                .khagwalShadow()
        }
    }
}
