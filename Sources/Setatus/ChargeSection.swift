import SwiftUI

struct ChargeSection: View {
    @ObservedObject var charge: ChargeController

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    PanelLabel("Charge limit")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(charge.limit >= 100 ? "OFF" : "\(charge.limit)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.ink)
                            .monospacedDigit()
                        Text("%").font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.ink)
                    }
                }
                Spacer()
                Text(charge.state?.inhibited == true ? "PAUSED" : "SMC LIMIT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Bru.cardInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .slab(charge.state?.inhibited == true ? Bru.yellow : Bru.green)
            }
            BlockSlider(value: Binding(get: { Double(charge.limit) },
                                       set: { charge.limit = Int($0) }),
                        range: 50...100,
                        step: 5,
                        fill: charge.state?.inhibited == true ? Bru.yellow : Bru.green) { editing in
                if !editing { Task { await charge.apply(charge.limit) } }
            }
            .disabled(charge.state?.supported == false)
            .opacity(charge.state?.supported == false ? 0.5 : 1)
            if let message = statusText {
                Text(message).font(.system(size: 9)).foregroundStyle(Bru.muted)
            }
        }
        .card()
    }

    private var statusText: String? {
        if let error = charge.message { return error }
        guard let state = charge.state else { return nil }
        if !state.supported { return "Charge limit not exposed by this Mac's SMC" }
        guard state.limit > 0, state.limit < 100 else { return nil }
        let percent = Int(state.percent ?? 0)
        return state.inhibited
            ? "charging paused at \(percent)%"
            : "holding \(state.limit)%"
    }
}
