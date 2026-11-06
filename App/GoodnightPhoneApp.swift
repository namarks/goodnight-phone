import SwiftUI
import UIKit

@main
struct GoodnightPhoneApp: App {
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
        // iOS relaunches the app in the background to deliver beacon enter/exit events and
        // (for the spare-device stand-in) Bluetooth events. Both monitors have to be recreated
        // on every launch for those events to arrive.
        RoomMonitor.shared.start()
        HubMonitor.shared.sync()
        return true
    }

    /// Info.plist lists landscape for the iPhone Duo's inner screen; phone-sized screens
    /// (including the Duo folded) stay portrait-only as before.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        guard let screen = window?.windowScene?.screen else { return .portrait }
        let shortSide = min(screen.bounds.width, screen.bounds.height)
        // Every phone screen is under 500 pt on its short side; the Duo's inner screen is well over 600.
        return shortSide >= 600 ? .allButUpsideDown : .portrait
    }
}
