import SwiftUI
import UIKit

@main
struct LightsOutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppModel.shared)
                .fullScreenCover(isPresented: .constant(!didFinishOnboarding)) {
                    OnboardingView { didFinishOnboarding = true }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // iOS relaunches the app in the background to deliver beacon enter/exit events.
        // The monitor has to be recreated on every launch for those events to arrive.
        RoomMonitor.shared.start()
        return true
    }
}
