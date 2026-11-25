import SwiftUI

@main
struct ProjecaoRendaApp: App {
    var body: some Scene {
        Window("Projeção Vitalícia", id: "projection") {
            SimulatorView()
                .frame(minWidth: 850, minHeight: 610)
                .environment(\.locale, LifeStyle.pt)
                .environment(\.calendar, LifetimeClock.calendar)
                .environment(\.timeZone, LifetimeClock.calendar.timeZone)
        }
        .defaultSize(width: 1_080, height: 840)
    }
}
