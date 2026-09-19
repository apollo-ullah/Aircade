import SwiftUI

@main
struct AircadeControllerApp: App {
    @StateObject private var controller = PhoneController()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ControllerScreen(controller: controller)
                .preferredColorScheme(.light)
                .onAppear { controller.activate() }
                .onChange(of: phase) { value in
                    if value == .active { controller.activate() }
                    else if value == .background { controller.deactivate() }
                }
        }
    }
}

struct ControllerScreen: View {
    @ObservedObject var controller: PhoneController
    private let blue = Color(red: 0.04, green: 0.48, blue: 0.72)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Aircade").font(.system(size: 32, weight: .bold)).italic().foregroundStyle(blue)
                    Spacer()
                    Image(systemName: "gamecontroller.fill").font(.title).foregroundStyle(blue)
                }
                Text(controller.status).font(.headline)
                if controller.connected { controls } else { pairing }
            }.padding(26)
        }.background(Color(red: 0.93, green: 0.97, blue: 0.99)).tint(blue)
    }
    private var pairing: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Your phone.\nYour saber.").font(.system(size: 42, weight: .bold)).tracking(-1)
            Text("Open Saber Duel on your Mac. Connect both devices to the same Wi-Fi, allow Local Network access, then enter the six-digit lobby code.")
                .foregroundStyle(.secondary)
            TextField("Lobby code", text: $controller.code)
                .font(.system(size: 30, weight: .bold, design: .monospaced)).keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: controller.code) { value in
                    let filtered = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if filtered != value { controller.code = filtered }
                }
            if controller.lobbies.isEmpty {
                Label("Looking for Aircade lobbies…", systemImage: "antenna.radiowaves.left.and.right")
                Text("No Mac visible? Keep the Mac’s Saber Duel lobby open. Event Wi-Fi may block local connections; try a personal hotspot.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(controller.lobbies) { lobby in
                Button { controller.connect(lobby) } label: {
                    HStack { Image(systemName: "desktopcomputer"); Text(lobby.name); Spacer(); Image(systemName: "arrow.right") }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).disabled(controller.code.count != 6 || controller.connecting)
            }
            Text("This uses the iPhone’s own motion sensor. You don’t need AirPods connected to the phone.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var controls: some View {
        VStack(spacing: 24) {
            Text("ORANGE").font(.system(size: 42, weight: .heavy)).italic().foregroundStyle(.orange)
            ZStack {
                Circle().fill(.orange.opacity(0.10)).frame(width: 220, height: 220)
                VStack(spacing: 0) {
                    Capsule().fill(.orange.gradient).frame(width: 18, height: 130)
                    RoundedRectangle(cornerRadius: 8).fill(.gray).frame(width: 25, height: 45)
                }.rotationEffect(.degrees(controller.tilt))
            }
            Text(controller.feedback.isEmpty ? (controller.ready && controller.live ? "READY TO DUEL" : "HOLD UPRIGHT TO START") : controller.feedback)
                .font(.headline).foregroundStyle(.orange)
            Text("Hold your phone upright with its screen facing you. The top edge points along your saber. Tap Recenter, then tilt to swing.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { controller.recenter() } label: {
                Label(controller.ready ? "Recenter" : "I’m holding it upright", systemImage: "scope")
                    .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 16)
            }.buttonStyle(.borderedProminent).tint(.orange).disabled(!controller.live)
            if !controller.live { Text("Waiting for motion. Allow Motion & Fitness access in Settings.").font(.footnote) }
            Text("Start the match on the Mac. Keep this app open. Recenter pauses an active match.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Leave game") { controller.disconnect() }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity)
    }
}
