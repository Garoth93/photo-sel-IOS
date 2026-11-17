import SwiftUI
import UniformTypeIdentifiers

@main
struct PhotoSelApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .commands { PhotoSelCommands(store: store) }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.chrome.ignoresSafeArea()
            if store.hasFolder {
                CullView()
            } else {
                WelcomeView()
            }
            ToastView()
        }
        .fileImporter(isPresented: Bindable(store).showFolderPicker,
                      allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): store.openFolder(pickedURL: url)
            case .failure(let error): store.showToast("Cartella non aperta: \(error.localizedDescription)")
            }
        }
    }
}
