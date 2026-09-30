import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { DemoScreen() }
    }
}

struct DemoScreen: View {
    @State private var otp = OTPFieldController()
    @State private var isVerified = false
    @State private var length = 4
    @AppStorage("dark") private var isDark = true
    @State private var palette = 0 // 0 default, 1 blue, 2 purple

    var body: some View {
        VStack(spacing: 28) {
            Text(isVerified ? "Verified ✓" : "Enter \(String("12345678".prefix(length)))")
                .font(.title2.bold())
            Text("status: \(String(describing: otp.status))")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            OTPAnimatedField(
                length: length,
                controller: otp,
                autofocus: true,
                onVerify: { code in
                    try await Task.sleep(for: .seconds(2)) // simulated backend
                    return code == String("12345678".prefix(code.count))
                },
                onVerified: { _ in isVerified = true }
            )
            .id(length)
            .otpFieldColors(
                accent: [nil, Color.blue, Color.purple][palette],
                fill: [nil, Color.blue.opacity(0.12), Color.purple.opacity(0.12)][palette],
                success: [nil, Color.cyan, Color.pink][palette]
            )

            HStack {
                Button("Reset") { otp.reset(); isVerified = false }
                Picker("Length", selection: $length) {
                    Text("4").tag(4); Text("6").tag(6); Text("8").tag(8)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Button(isDark ? "Light" : "Dark") { isDark.toggle() }
            }
            .buttonStyle(.bordered)

            Picker("Colors", selection: $palette) {
                Text("Default").tag(0); Text("Blue").tag(1); Text("Purple").tag(2)
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color(white: 0.03) : Color(white: 0.92))
        .preferredColorScheme(isDark ? .dark : .light)
        .onChange(of: length) { otp.reset(); isVerified = false }
    }
}
