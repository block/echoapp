import SwiftUI

/// A Picker that toggles between enum cases
struct EnumPicker<Enum: CaseIterable, Content: View, Style: PickerStyle>: View
    where Enum: RawRepresentable, Enum.RawValue == String, Enum.AllCases.Indices == Range<Int> {

    private let style: Style
    private let cases: [Enum]
    private let content: (Enum) -> Content

    @State private var selectedCaseIndex: Int

    init(
        style: Style,
        enum: Enum.Type,
        defaultSelection: Enum = Enum.allCases.first!,
        content: @escaping (Enum) -> Content
    ) {
        self.style = style
        self.cases = Array(Enum.allCases)
        self.content = content
        self._selectedCaseIndex = State(
            initialValue: cases.firstIndex { $0 == defaultSelection }!
        )
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Picker("", selection: $selectedCaseIndex) {
                    ForEach(cases.indices) { index in
                        Text(self.cases[index].rawValue)
                    }
                }
                .pickerStyle(self.style)
                Spacer()
            }
            content(cases[selectedCaseIndex])
        }
    }

}
