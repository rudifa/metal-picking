import MetalKit

#if os(iOS)

    #if targetEnvironment(simulator)
        #warning("Cannot build a Metal target for simulator")
    #endif

    @UIApplicationMain
    class AppDelegate: UIResponder, UIApplicationDelegate {
        var window: UIWindow?

        func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
            return true
        }
    }

#elseif os(OSX)

    @NSApplicationMain
    class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
            return true
        }
    }

#endif
