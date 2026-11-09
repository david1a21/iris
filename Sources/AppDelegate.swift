import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let win = UIWindow(frame: UIScreen.main.bounds)
        win.backgroundColor = UIColor(red: 8.0 / 255.0, green: 8.0 / 255.0, blue: 10.0 / 255.0, alpha: 1.0)
        win.rootViewController = ShellViewController()
        win.makeKeyAndVisible()
        window = win
        return true
    }
}
