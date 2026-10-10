import ARKit
import RealityKit
import SwiftUI

/// ARView ni boshqaradigan dvigatel (skan yoki AR ko'rish).
@MainActor
protocol ARDvigatel: AnyObject {
    func ulan(_ v: ARView)
    func toxtat()
    func bosildi(_ nuqta: CGPoint)
}

/// RealityKit ARView — kamera, LiDAR mesh va belgilar. Bosish dvigatelga uzatiladi.
struct ARKorinish: UIViewRepresentable {
    let dvigatel: ARDvigatel
    /// UI-04: tizimning sozlanish ko'rsatmasi faol/nofaol — ekran boshqa HUD ni yashiradi.
    var sozlanish: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Koordinator { Koordinator(dvigatel, sozlanish: sozlanish) }

    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        v.renderOptions.insert(.disableMotionBlur)
        v.renderOptions.insert(.disableDepthOfField)
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Koordinator.bosildi(_:))))
        dvigatel.ulan(v)
        // HIG: boshlanishda va joy qayta aniqlanganda o'zi chiqadi, qo'lda boshqarish shart emas
        let c = ARCoachingOverlayView()
        c.session = v.session
        c.goal = .tracking
        c.activatesAutomatically = true
        c.delegate = context.coordinator
        c.frame = v.bounds
        c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.addSubview(c)
        return v
    }

    func updateUIView(_ v: ARView, context: Context) {}

    static func dismantleUIView(_ v: ARView, coordinator: Koordinator) {
        coordinator.dvigatel.toxtat()
    }

    final class Koordinator: NSObject, ARCoachingOverlayViewDelegate {
        let dvigatel: ARDvigatel
        let sozlanish: ((Bool) -> Void)?
        init(_ d: ARDvigatel, sozlanish: ((Bool) -> Void)?) { dvigatel = d; self.sozlanish = sozlanish }

        func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) { sozlanish?(true) }
        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) { sozlanish?(false) }
        @MainActor @objc func bosildi(_ g: UITapGestureRecognizer) {
            dvigatel.bosildi(g.location(in: g.view))
        }
    }
}
