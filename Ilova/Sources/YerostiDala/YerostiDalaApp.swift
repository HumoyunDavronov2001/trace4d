import SwiftUI

@main
struct YerostiDalaApp: App {
    @State private var ombor = LoyihaOmbori()
    @State private var rtk = RTKBoshqaruv()
    @State private var sozlama = Sozlamalar()
    @State private var yuklovchi = Yuklovchi()
    @State private var qurilma = QurilmaHolati()

    var body: some Scene {
        WindowGroup {
            LoyihalarEkrani()
                .environment(ombor)
                .environment(rtk)
                .environment(sozlama)
                .environment(yuklovchi)
                .environment(qurilma)
                .tint(Rang.urgu)
        }
    }
}
