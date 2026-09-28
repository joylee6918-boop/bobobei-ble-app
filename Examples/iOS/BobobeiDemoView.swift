import BobobeiBLE
import SwiftUI

struct BobobeiDemoView: View {
    @StateObject private var toy = BobobeiCentral()
    @State private var motion = 0.0
    @State private var vibration = 0.0
    @State private var rotation = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Text(toy.status)
                    Button("Scan") { toy.scan() }
                    ForEach(toy.devices) { device in
                        Button("Connect \(device.name)") { toy.connect(device.id) }
                    }
                    Button("Disconnect", role: .destructive) { toy.disconnect() }
                }

                Section("Levels") {
                    level("Motion", value: $motion)
                    level("Vibration", value: $vibration)
                    level("Rotation", value: $rotation)
                    Button("Send") {
                        Task {
                            try? await toy.setLevels(.init(
                                motion: Int(motion), vibration: Int(vibration),
                                rotation: Int(rotation)))
                        }
                    }
                    Button("Stop", role: .destructive) {
                        Task { try? await toy.stop() }
                    }
                }
                .disabled(!toy.isReady)
            }
            .navigationTitle("Bobobei BLE")
        }
    }

    private func level(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int(value.wrappedValue))")
            Slider(value: value, in: 0...100, step: 1)
        }
    }
}
