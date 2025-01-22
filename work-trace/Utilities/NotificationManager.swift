import Foundation
import UserNotifications
import SwiftUI

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var isNotificationAuthorized = false
    private var settings: Settings?
    
    init() {
        checkNotificationStatus()
    }
    
    func setSettings(_ settings: Settings) {
        self.settings = settings
    }
    
    func checkNotificationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.isNotificationAuthorized = settings.authorizationStatus == .authorized
                print("当前通知权限状态: \(settings.authorizationStatus.rawValue)")
            }
        }
    }
    
    func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await MainActor.run {
                    self.isNotificationAuthorized = granted
                    print("请求通知权限结果: \(granted)")
                    completion(granted)
                }
            } catch {
                print("通知权限获取失败: \(error.localizedDescription)")
                await MainActor.run {
                    completion(false)
                }
            }
        }
    }
    
    func scheduleWorkNotifications(startTime: WorkTime, endTime: WorkTime) {
        guard let settings = settings else { return }
        
        Task {
            // 移除之前的通知
            await UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            
            // 设置上班提醒
            await scheduleDaily(hour: startTime.startHour,
                              minute: startTime.startMinute,
                              title: "上班打卡提醒",
                              body: "点击通知直接拍照记录上班打卡",
                              identifier: "work-start",
                              settings: settings)
            
            // 设置下班提醒
            await scheduleDaily(hour: endTime.endHour,
                              minute: endTime.endMinute,
                              title: "下班打卡提醒",
                              body: "点击通知直接拍照记录下班打卡",
                              identifier: "work-end",
                              settings: settings)
        }
    }
    
    private func scheduleDaily(hour: Int, minute: Int, title: String, body: String, identifier: String, settings: Settings) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["type": identifier.hasPrefix("work-start") ? "check-in" : "check-out"]
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let workSchedule = await settings.workSchedule
        switch workSchedule {
        case .doubleWeekend:
            // 周一至周五
            for weekday in 2...6 {
                dateComponents.weekday = weekday
                await scheduleNotification(with: content, dateComponents: dateComponents, identifier: "\(identifier)-\(weekday)")
            }
            
        case .singleWeekend:
            // 周一至周六
            for weekday in 2...7 {
                dateComponents.weekday = weekday
                await scheduleNotification(with: content, dateComponents: dateComponents, identifier: "\(identifier)-\(weekday)")
            }
            
        case .alternatingWeekend:
            // 周一至周五固定
            for weekday in 2...5 {
                dateComponents.weekday = weekday
                await scheduleNotification(with: content, dateComponents: dateComponents, identifier: "\(identifier)-\(weekday)")
            }
            
            // 周六根据大小周设置
            let isLongWeek = await settings.isLongWeek
            if isLongWeek {
                dateComponents.weekday = 6
                await scheduleNotification(with: content, dateComponents: dateComponents, identifier: "\(identifier)-6")
            }
            
        case .custom:
            // 获取自定义休息日设置
            let customSettings = await settings.customWeekendSettings
            // 遍历所有工作日（非休息日）
            for weekday in 1...7 where !customSettings.restDays.contains(weekday) {
                dateComponents.weekday = weekday
                await scheduleNotification(with: content, dateComponents: dateComponents, identifier: "\(identifier)-\(weekday)")
            }
        }
    }
    
    private func scheduleNotification(with content: UNNotificationContent, dateComponents: DateComponents, identifier: String) async {
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("添加通知失败: \(error.localizedDescription)")
        }
    }
    
    // 用于测试的即时通知
    func sendTestNotification(type: String = "check-in", completion: @escaping (Bool, String) -> Void) {
        Task {
            do {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                guard settings.authorizationStatus == .authorized else {
                    await MainActor.run {
                        print("通知未授权")
                        completion(false, "请先授权通知权限")
                    }
                    return
                }
                
                let content = UNMutableNotificationContent()
                content.title = type == "check-in" ? "上班打卡提醒" : "下班打卡提醒"
                content.body = type == "check-in" ? "点击通知直接拍照记录上班打卡" : "点击通知直接拍照记录下班打卡"
                content.sound = .default
                content.userInfo = ["type": type]
                
                // 5秒后发送通知
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                
                try await UNUserNotificationCenter.current().add(request)
                await MainActor.run {
                    print("通知请求添加成功")
                    completion(true, "通知将在5秒后发送")
                }
            } catch {
                await MainActor.run {
                    print("发送通知失败: \(error.localizedDescription)")
                    completion(false, "发送通知失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func getNextNotificationTime(completion: @escaping (Date?) -> Void) {
        Task {
            guard let settings = settings else {
                print("⚠️ Settings not available")
                await MainActor.run { completion(nil) }
                return
            }
            
            let calendar = Calendar.current
            let now = Date()
            
            // 获取当前是周几 (1是周日，2是周一，以此类推)
            let currentWeekday = calendar.component(.weekday, from: now)
            print("📅 当前时间: \(now)")
            print("📅 当前是周\(currentWeekday == 1 ? "日" : String(currentWeekday - 1))")
            print("📅 工作日设置: \(settings.workSchedule.rawValue)")
            if settings.workSchedule == .alternatingWeekend {
                print("📅 本周是\(settings.isLongWeek ? "大" : "小")周")
            }
            
            // 获取今天的上下班时间
            var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
            startComponents.hour = settings.workTime.startHour
            startComponents.minute = settings.workTime.startMinute
            
            var endComponents = calendar.dateComponents([.year, .month, .day], from: now)
            endComponents.hour = settings.workTime.endHour
            endComponents.minute = settings.workTime.endMinute
            
            let startTime = calendar.date(from: startComponents)!
            let endTime = calendar.date(from: endComponents)!
            print("⏰ 上班时间: \(startTime)")
            print("⏰ 下班时间: \(endTime)")
            
            
            // 检查当前是否是工作日
            let todayIsWorkday = self.isWorkday(weekday: currentWeekday, settings: settings)
            print("📆 今天是\(todayIsWorkday ? "工作日" : "休息日")")
            
            // 如果是工作日，检查下一个通知时间
            if todayIsWorkday {
                if now < startTime {
                    // 如果当前时间早于今天的上班时间，返回今天的上班时间
                    print("🔔 下次提醒: 今天上班时间")
                    await MainActor.run { completion(startTime) }
                    return
                } else if now < endTime {
                    // 如果当前时间在上班时间和下班时间之间，返回今天的下班时间
                    print("🔔 下次提醒: 今天下班时间")
                    await MainActor.run { completion(endTime) }
                    return
                }
            }
            
            // 如果当前时间晚于今天的下班时间，或者今天不是工作日，查找下一个工作日
            var nextDate = calendar.date(byAdding: .day, value: 1, to: now)!
            var daysChecked = 0
            
            while daysChecked < 7 {
                let nextWeekday = calendar.component(.weekday, from: nextDate)
                print("📅 检查下一天: \(nextDate), 周\(nextWeekday == 1 ? "日" : String(nextWeekday - 1))")
                if self.isWorkday(weekday: nextWeekday, settings: settings) {
                    // 找到下一个工作日，返回其上班时间
                    var components = calendar.dateComponents([.year, .month, .day], from: nextDate)
                    components.hour = settings.workTime.startHour
                    components.minute = settings.workTime.startMinute
                    if let nextWorkdayStart = calendar.date(from: components) {
                        print("🔔 下次提醒: 下一个工作日上班时间")
                        await MainActor.run { completion(nextWorkdayStart) }
                        return
                    }
                }
                nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate)!
                daysChecked += 1
            }
            
            print("⚠️ 未找到下一个提醒时间")
            await MainActor.run { completion(nil) }
        }
    }
    
    private func isWorkday(weekday: Int, settings: Settings) -> Bool {
        switch settings.workSchedule {
        case .doubleWeekend:
            // 周一至周五 (2-6)
            return weekday >= 2 && weekday <= 6
            
        case .singleWeekend:
            // 周一至周六 (2-7)
            return weekday >= 2 && weekday <= 7
            
        case .alternatingWeekend:
            // 周一至周五固定 (2-6)
            if weekday >= 2 && weekday <= 5 { 
                return true
            }
            // 周六 (6) 根据大小周判断
            if weekday == 6 {
                return settings.isLongWeek
            }
            return false
            
        case .custom:
            // 检查是否为休息日
            return !settings.customWeekendSettings.restDays.contains(weekday)
        }
    }
} 
