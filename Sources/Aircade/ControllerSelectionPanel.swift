import SwiftUI
import MotionCore

/// Shared setup content; the shell owns presentation and the app owns the session.
struct ControllerSelectionPanel: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var controllers: ControllerSession
    var duel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Your controllers", systemImage: "gamecontroller.fill").font(.title3.bold())
                Spacer()
                Text("Connect once · play every game").font(.caption).foregroundStyle(.secondary)
            }
            if duel {
                Picker("Player 1 · Blue", selection: Binding(
                    get: { controllers.device(for: .one) ?? .airPod },
                    set: { controllers.assign($0, to: .one) })) {
                    Text(controllers.name(for: .airPod)).tag(ControllerDevice.airPod)
                    Text("iPhone").tag(ControllerDevice.phone)
                }.pickerStyle(.segmented)
                Text("Player 2 uses the other controller. One AirPods pair provides one player.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Play with", selection: Binding(get: { controllers.soloDevice }, set: {
                    controllers.selectSolo($0); controllers.selectMenu($0)
                })) {
                    Label(controllers.name(for: .airPod), systemImage: "airpodspro").tag(ControllerDevice.airPod)
                    Label("iPhone", systemImage: "iphone").tag(ControllerDevice.phone)
                }.pickerStyle(.segmented)
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(motion.controllerName, systemImage: "airpodspro").font(.headline)
                    Text(motion.sourceMismatch ? motion.controllerLabel : controllers.readiness(for: .airPod))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(motion.running ? "Reconnect AirPods" : "Start AirPods") { motion.start() }
                        Button("Recenter") { controllers.recenter(.airPod) }.disabled(!motion.hasFreshMotion)
                    }.buttonStyle(WiiButtonStyle())
                }.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("iPhone", systemImage: "iphone").font(.headline)
                    if controllers.phoneHost.connected {
                        Text(controllers.readiness(for: .phone)).font(.callout).foregroundStyle(.secondary)
                        Text("Hold portrait, screen facing you, top edge up.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Recenter iPhone") { controllers.recenter(.phone) }
                            Button("Unpair") { controllers.forgetPhone() }
                        }.buttonStyle(WiiButtonStyle())
                    } else {
                        Text("Open Aircade Controller on your phone, select this Mac, and enter:")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(controllers.phoneHost.code.isEmpty ? "Starting…" : controllers.phoneHost.code)
                            .font(.system(size: 28, weight: .bold, design: .monospaced)).tracking(3).textSelection(.enabled)
                        Text(controllers.phoneHost.status).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(20).wiiPanel()
            .onAppear { motion.startControllerSession() }
    }
}

struct ActiveControllerBadge: View {
    @ObservedObject var motion: MotionModel
    @ObservedObject var controllers: ControllerSession
    var body: some View {
        let device = controllers.soloDevice
        Label(controllers.readiness(for: device), systemImage: device == .phone ? "iphone" : "airpodspro")
            .font(.caption.weight(.semibold)).foregroundStyle(WiiTheme.accentDeep)
            .accessibilityLabel("Selected controller: \(controllers.name(for: device)). \(controllers.readiness(for: device))")
    }
}
