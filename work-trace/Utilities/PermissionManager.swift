import AVFoundation
import CoreLocation
import SwiftUI

class PermissionManager: NSObject, ObservableObject {
    static let shared = PermissionManager()
    private let locationManager = CLLocationManager()
    
    @Published var isNotificationAuthorized = false
    @Published var isCameraAuthorized = false
    @Published var isMicrophoneAuthorized = false
    @Published var isLocationAuthorized = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        checkPermissions()
        
        // 添加通知中心观察者
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func applicationDidBecomeActive() {
        // 每次应用程序变为活动状态时检查权限
        checkPermissions()
    }
    
    func checkPermissions() {
        checkNotificationPermission()
        checkCameraPermission()
        checkMicrophonePermission()
        checkLocationPermission()
    }
    
    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = granted
                completion(granted)
                // 请求完成后再次检查状态
                self?.checkNotificationPermission()
            }
        }
    }
    
    func checkCameraPermission() {
        DispatchQueue.main.async { [weak self] in
            self?.isCameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }
    }
    
    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isCameraAuthorized = granted
                completion(granted)
                // 请求完成后再次检查状态
                self?.checkCameraPermission()
            }
        }
    }
    
    func checkMicrophonePermission() {
        DispatchQueue.main.async { [weak self] in
            self?.isMicrophoneAuthorized = AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.isMicrophoneAuthorized = granted
                completion(granted)
                // 请求完成后再次检查状态
                self?.checkMicrophonePermission()
            }
        }
    }
    
    func checkLocationPermission() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let status = self.locationManager.authorizationStatus
            self.isLocationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        // 状态变化会通过 delegate 方法通知
    }
    
    func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

extension PermissionManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationPermission()
    }
} 