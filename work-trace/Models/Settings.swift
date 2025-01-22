import Foundation
import SwiftUI
import Combine
import Photos
import CoreTelephony

@MainActor
public final class Settings: ObservableObject {
    @Published public var currentCompany: String {
        didSet {
            UserDefaults.standard.set(currentCompany, forKey: "currentCompany")
        }
    }
    
    @Published public var workSchedule: WorkScheduleType {
        didSet {
            UserDefaults.standard.set(workSchedule.rawValue, forKey: "workSchedule")
        }
    }
    
    @Published public var isLongWeek: Bool {
        didSet {
            UserDefaults.standard.set(isLongWeek, forKey: "isLongWeek")
            if oldValue != isLongWeek {
                UserDefaults.standard.set(Date(), forKey: "lastWeekToggleDate")
            }
        }
    }
    
    @Published public var customWeekendSettings: CustomWeekendSettings {
        didSet {
            if let encoded = try? JSONEncoder().encode(customWeekendSettings) {
                UserDefaults.standard.set(encoded, forKey: "customWeekendSettings")
            }
        }
    }
    
    @Published public var workTime: WorkTime {
        didSet {
            if let encoded = try? JSONEncoder().encode(workTime) {
                UserDefaults.standard.set(encoded, forKey: "workTime")
            }
        }
    }
    
    @Published public var isStorageAuthorized: Bool = false {
        didSet {
            UserDefaults.standard.set(isStorageAuthorized, forKey: "isStorageAuthorized")
        }
    }
    
    @Published public var isCellularDataEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isCellularDataEnabled, forKey: "isCellularDataEnabled")
        }
    }
    
    @Published public var colorScheme: ColorSchemePreference {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: "colorScheme")
        }
    }
    
    private let cellularData = CTCellularData()
    
    public init() {
        // 首先初始化所有存储属性
        self.currentCompany = UserDefaults.standard.string(forKey: "currentCompany") ?? "准时下班才怪有限公司"
        self.workTime = WorkTime(startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
        self.isLongWeek = UserDefaults.standard.bool(forKey: "isLongWeek")
        self.isStorageAuthorized = UserDefaults.standard.bool(forKey: "isStorageAuthorized")
        self.isCellularDataEnabled = UserDefaults.standard.bool(forKey: "isCellularDataEnabled")
        
        // 初始化自定义休息日设置
        if let customWeekendData = UserDefaults.standard.data(forKey: "customWeekendSettings"),
           let decodedSettings = try? JSONDecoder().decode(CustomWeekendSettings.self, from: customWeekendData) {
            self.customWeekendSettings = decodedSettings
        } else {
            self.customWeekendSettings = CustomWeekendSettings()
        }
        
        // 初始化主题设置
        if let themeString = UserDefaults.standard.string(forKey: "colorScheme"),
           let theme = ColorSchemePreference(rawValue: themeString) {
            self.colorScheme = theme
        } else {
            self.colorScheme = .system
        }
        
        // 初始化工作日设置
        if let scheduleString = UserDefaults.standard.string(forKey: "workSchedule"),
           let schedule = WorkScheduleType(rawValue: scheduleString) {
            self.workSchedule = schedule
        } else {
            self.workSchedule = .doubleWeekend
        }
        
        // 所有属性初始化完成后，再处理大小周的逻辑
        if let workTimeData = UserDefaults.standard.data(forKey: "workTime"),
           let decodedWorkTime = try? JSONDecoder().decode(WorkTime.self, from: workTimeData) {
            self.workTime = decodedWorkTime
        }
        
        // 如果是大小周，根据上次切换时间自动计算当前是大周还是小周
        if let lastToggleDate = UserDefaults.standard.object(forKey: "lastWeekToggleDate") as? Date,
           self.workSchedule == .alternatingWeekend {
            let weeksSinceToggle = Calendar.current.dateComponents([.weekOfYear], from: lastToggleDate, to: Date()).weekOfYear ?? 0
            self.isLongWeek = weeksSinceToggle % 2 == 0 ? self.isLongWeek : !self.isLongWeek
        }
        
        // 检查权限状态
        checkStoragePermission()
        startMonitoringCellularData()
    }
    
    // 判断指定日期是否为工作日
    public func isWorkday(date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)  // 1 = 周日, 2 = 周一, ..., 7 = 周六
        
        switch workSchedule {
        case .doubleWeekend:
            // 周一至周五工作
            return weekday >= 2 && weekday <= 6
            
        case .singleWeekend:
            // 周一至周六工作
            return weekday >= 2 && weekday <= 7
            
        case .alternatingWeekend:
            if weekday == 1 { return false }  // 周日永远休息
            if weekday >= 2 && weekday <= 5 { return true }  // 周一至周五永远工作
            // 周六根据大小周判断
            if weekday == 6 || weekday == 7 {
                return isLongWeek
            }
            return false
            
        case .custom:
            // 检查当前日期是否在自定义休息日中
            return !customWeekendSettings.restDays.contains(weekday)
        }
    }
    
    public func checkStoragePermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        isStorageAuthorized = status == .authorized || status == .limited
    }
    
    public func requestStoragePermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                let granted = status == .authorized || status == .limited
                self?.isStorageAuthorized = granted
                completion(granted)
            }
        }
    }
    
    private func startMonitoringCellularData() {
        cellularData.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
            DispatchQueue.main.async {
                self?.isCellularDataEnabled = state == .notRestricted
            }
        }
    }
    
    public func checkCellularDataStatus() -> Bool {
        return cellularData.restrictedState == .notRestricted
    }
}

public enum ColorSchemePreference: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色模式"
    case dark = "深色模式"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
} 