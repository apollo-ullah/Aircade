import SwiftUI
import MotionCore

struct ScriptedControllerSetup: View {
    @ObservedObject var motion: MotionModel
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("SCRIPTED SABER TESTS").font(.system(size: 21, weight: .black, design: .rounded))
                Spacer()
                Button("Done", action: done)
            }
            Text("Test the game without AirPods. The script moves the saber through the same collision, scoring and round rules as your controller.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Scenario", selection: $motion.selectedScript) {
                ForEach(SaberScript.allCases) { script in Text(script.rawValue).tag(script) }
            }.pickerStyle(.radioGroup)
            Text(motion.selectedScript.expectation).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            Text("Scripted input is labelled during play and never saves a high score. Your AirPod grip calibration stays saved.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Use AirPods instead") {
                    done(); motion.game.leave(); motion.start()
                }
                Spacer()
                Button("Run scripted test") {
                    done(); motion.startScripted(motion.selectedScript)
                }.buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black).controlSize(.large)
            }
        }.padding(26).frame(width: 560)
            .background(Color(red: 0.035, green: 0.045, blue: 0.07)).preferredColorScheme(.dark)
    }
}
