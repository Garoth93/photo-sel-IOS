import UIKit

/// System share sheet with real file URLs: Lightroom ("Lightroom" / "Copia in
/// Lightroom"), File, AirDrop… receive the original files. Files of the opened
/// folder are readable while its security scope is open.
@MainActor
enum SharePresenter {
    static func present(_ urls: [URL], completion: @escaping (Bool) -> Void = { _ in }) {
        guard !urls.isEmpty, let top = topViewController() else { return }
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
