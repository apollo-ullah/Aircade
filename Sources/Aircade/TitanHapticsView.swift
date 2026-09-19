import SwiftUI

struct TitanHapticsView: View {
    @ObservedObject var haptics: TitanHaptics
    @State private var ports = TitanHaptics.ports()
    @State private var port = ""
    @State private var effect = TitanEffect.hit

    var body: some View {
        Form {
            Text("TITAN Core Haptics").font(.title2.bold())
            Text("Connect the kit by USB-C with no mode jumper. Attach a motor to the selected channel.")
            HStack {
                Picker("USB port", selection: $port) {
                    Text("Choose a port").tag("")
                    ForEach(ports, id: \.self) { Text($0).tag($0) }
                }.disabled(haptics.connected)
                Button("Refresh") { ports = TitanHaptics.ports() }
            }
            Picker("Motor channel", selection: $haptics.channel) {
                Text("L").tag(1); Text("R").tag(2); Text("M").tag(3)
            }
            Picker("Worn by", selection: $haptics.recipient) {
                Text("AirPod / hand-tracked player").tag(ControllerDevice.airPod)
                Text("Phone player").tag(ControllerDevice.phone)
            }
            HStack {
                Text("Strength")
                Slider(value: $haptics.intensity, in: 0...1)
                Text("\(Int(haptics.intensity * 100))%")
            }
            Text(haptics.status).font(.callout).accessibilityIdentifier("titan-status")
            HStack {
                Button(haptics.connected ? "Disconnect" : "Connect") {
                    if haptics.connected { haptics.disconnect() } else { haptics.connect(path: port) }
                }.disabled(!haptics.connected && port.isEmpty)
                Picker("Effect", selection: $effect) {
                    ForEach(TitanEffect.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button("Test") { haptics.play(effect) }.disabled(!haptics.connected)
            }
            Text("Hits, blocks, damage and results have distinct effects. Port open confirms the connection only; Test verifies the physical motor. Effects finish within 200 ms.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 550)
    }
}
