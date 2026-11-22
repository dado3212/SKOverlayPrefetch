import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var demo: PrefetchDemo

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("App Store ID")) {
                    NumberField(placeholder: "App Store ID", text: $demo.appIdentifier)
                }

                Section(header: Text("Overlay"),
                        footer: Text("Compare a cold present with one after a prefetch. Backgrounding the app tears the service and daemon down again.")) {
                    Button("1. Prefetch") { demo.prefetch() }
                        .disabled(demo.isPrefetching)
                    Button("2. Present overlay") { demo.present() }
                    Button("Dismiss overlay") { demo.dismiss() }
                }

                Section(header: HStack {
                    Text("Log")
                    Spacer()
                    Button("Clear") { demo.clearLog() }
                        .font(.caption)
                }) {
                    ForEach(demo.log.reversed()) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.timeFormat.string(from: line.time))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("SKOverlay Prefetch")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

/// Number-pad text field with a Done button above the keyboard (iOS 14 has no SwiftUI
/// keyboard toolbar or @FocusState).
private struct NumberField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = .numberPad
        field.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                                           weight: .regular)
        field.text = text
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)),
                        for: .editingChanged)

        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(systemItem: .done,
                            primaryAction: UIAction { [weak field] _ in field?.resignFirstResponder() }),
        ]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func textChanged(_ field: UITextField) { text.wrappedValue = field.text ?? "" }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(PrefetchDemo())
    }
}
