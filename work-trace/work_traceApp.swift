//
//  work_traceApp.swift
//  work-trace
//
//  Created by GuangYi Ding on 2025/1/13.
//

import SwiftUI
import SwiftData
import Inject
import UIKit

// 添加全局状态对象
@Observable final class AppState {
    static let shared = AppState()
    var shouldShowCamera = false
    var shouldShowAudioRecorder = false
    var selectedTab = 0
}

// Add scene delegate to handle quick actions
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        switch shortcutItem.type {
        case "com.worktrace.quickcamera":
            Task { @MainActor in
                AppState.shared.shouldShowCamera = true
            }
        case "com.worktrace.quickaudio":
            Task { @MainActor in
                AppState.shared.shouldShowAudioRecorder = true
            }
        default:
            break
        }
        completionHandler(true)
    }
}

@main
struct work_traceApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var settings = Settings()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Company.self,
            WorkPhoto.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(settings.colorScheme.colorScheme)
                .onAppear {
                    // 设置通知代理
                    UNUserNotificationCenter.current().delegate = NotificationHandler.shared
                    // 设置 settings 实例
                    NotificationManager.shared.setSettings(settings)
                    #if DEBUG
                    Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle")?.load()
                    #endif
                }
                .onOpenURL { url in
                    // Handle any deep links here if needed
                }
                .handlesExternalEvents(preferring: Set(arrayLiteral: "*"), allowing: Set(arrayLiteral: "*"))
        }
        .commands {
            // Add any menu commands here if needed
        }
    }
}

// Add app delegate to handle quick actions
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        
        if let shortcutItem = options.shortcutItem {
            // Handle the quick action if app was launched from it
            switch shortcutItem.type {
            case "com.worktrace.quickcamera":
                Task { @MainActor in
                    AppState.shared.shouldShowCamera = true
                }
            case "com.worktrace.quickaudio":
                Task { @MainActor in
                    AppState.shared.shouldShowAudioRecorder = true
                }
            default:
                break
            }
        }
        
        return configuration
    }
}

// 修改通知处理类
class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 允许在前台显示通知
        completionHandler([.banner, .sound, .badge])
    }
    
    // 添加通知响应处理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 获取通知类型
        if let type = response.notification.request.content.userInfo["type"] as? String {
            // 设置全局状态以显示相机
            Task { @MainActor in
                AppState.shared.shouldShowCamera = true
            }
        }
        completionHandler()
    }
}

#if canImport(HotSwiftUI)
@_exported import HotSwiftUI
#elseif canImport(Inject)
@_exported import Inject
#else
// This code can be found in the Swift package:
// https://github.com/johnno1962/HotSwiftUI

#if DEBUG
import Combine

private var loadInjectionOnce: () = {
        guard objc_getClass("InjectionClient") == nil else {
            return
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        let bundleName = "macOSInjection.bundle"
        #elseif os(tvOS)
        let bundleName = "tvOSInjection.bundle"
        #elseif os(visionOS)
        let bundleName = "xrOSInjection.bundle"
        #elseif targetEnvironment(simulator)
        let bundleName = "iOSInjection.bundle"
        #else
        let bundleName = "maciOSInjection.bundle"
        #endif
        let bundlePath = "/Applications/InjectionIII.app/Contents/Resources/"+bundleName
        guard let bundle = Bundle(path: bundlePath), bundle.load() else {
            return print("""
                ⚠️ Could not load injection bundle from \(bundlePath). \
                Have you downloaded the InjectionIII.app from either \
                https://github.com/johnno1962/InjectionIII/releases \
                or the Mac App Store?
                """)
        }
}()

public let injectionObserver = InjectionObserver()

public class InjectionObserver: ObservableObject {
    @Published var injectionNumber = 0
    var cancellable: AnyCancellable? = nil
    let publisher = PassthroughSubject<Void, Never>()
    init() {
        cancellable = NotificationCenter.default.publisher(for:
            Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .sink { [weak self] change in
            self?.injectionNumber += 1
            self?.publisher.send()
        }
    }
}

extension SwiftUI.View {
    public func eraseToAnyView() -> some SwiftUI.View {
        _ = loadInjectionOnce
        return AnyView(self)
    }
    public func enableInjection() -> some SwiftUI.View {
        return eraseToAnyView()
    }
    public func loadInjection() -> some SwiftUI.View {
        return eraseToAnyView()
    }
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
            .onReceive(injectionObserver.publisher, perform: bumpState)
            .eraseToAnyView()
    }
}

@available(iOS 13.0, *)
@propertyWrapper
public struct ObserveInjection: DynamicProperty {
    @ObservedObject private var iO = injectionObserver
    public init() {}
    public private(set) var wrappedValue: Int {
        get {0} set {}
    }
}
#else
extension SwiftUI.View {
    @inline(__always)
    public func eraseToAnyView() -> some SwiftUI.View { return self }
    @inline(__always)
    public func enableInjection() -> some SwiftUI.View { return self }
    @inline(__always)
    public func loadInjection() -> some SwiftUI.View { return self }
    @inline(__always)
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
    }
}

@available(iOS 13.0, *)
@propertyWrapper
public struct ObserveInjection {
    public init() {}
    public private(set) var wrappedValue: Int {
        get {0} set {}
    }
}
#endif
#endif
