import EchoPluginUI
import SwiftUI

struct AccessibilityDetailView: View {
    var selectedElement: AccessibilityElement?

    var body: some View {
        if let element = selectedElement {
            List {
                SectionView(
                    title: "Description",
                    content: element.description,
                    helpText: """
                    The description of the accessibility element that will be read by VoiceOver when the element is brought into focus.
                    """
                )
                SectionView(
                    title: "Identifier",
                    content: element.identifier,
                    helpText: """
                    A unique identifier for the element, primarily used in UI tests for locating and interacting with elements. This identifier is not visible to users.
                    """
                )
                SectionView(
                    title: "Hint",
                    content: element.hint,
                    helpText: """
                    A hint that will be read by VoiceOver if focus remains on the element after the description is read.
                    """
                )
                SectionView(
                    title: "User Input Labels",
                    content: element.userInputLabels,
                    helpText: """
                    The labels that will be used by Voice Control for user input.
                    """
                )
                SectionView(
                    title: "Custom Actions",
                    content: element.customActions,
                    helpText: """
                    The names of the custom actions supported by the element.
                    """
                )
                SectionView(
                    title: "Frame",
                    content: element.frame.displayValues,
                    helpText: """
                    Frame of the accessibility element.
                    """
                )
            }
            .listStyle(SidebarListStyle())
        } else {
            InitialView()
        }
    }
}

extension AccessibilityDetailView {
    struct SectionView<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content
        let helpText: String

        var body: some View {
            Section(title) {
                content
            }
            .help(helpText)
        }
    }

    private struct InitialView: View {
        var body: some View {
            EchoNullStateView(
                iconName: "rectangle.inset.filled.and.cursorarrow",
                message: "Select an Accessibility Element"
            )
        }
    }
}

// MARK: -

private extension AccessibilityDetailView.SectionView where Content == Text {
    init(title: String, content: String?, helpText: String) {
        self.title = title
        self.content = Text(content ?? "None")
            .foregroundStyle(content == nil ? .tertiary : .primary)
        self.helpText = helpText
    }
}

private extension AccessibilityDetailView.SectionView where Content == ForEach<[String], String, Text> {
    init(title: String, content: [String]?, helpText: String) {
        self.title = title

        let contentToDisplay: [String] = {
            if let content, !content.isEmpty {
                return content
            } else {
                return ["None"]
            }
        }()

        let isContentNilOrEmpty = content == nil || content?.isEmpty == true

        self.content = ForEach(contentToDisplay, id: \.self) { action in
            Text(action)
                .foregroundStyle(isContentNilOrEmpty ? .tertiary : .primary)
        }

        self.helpText = helpText
    }
}
