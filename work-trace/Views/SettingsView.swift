import AVFoundation
import CoreLocation
import Foundation
import SwiftData
import SwiftUI
import ZIPFoundation

struct SettingsIconStyle: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        if let label = content as? Label<Text, Image> {
            HStack {
                label
                    .labelStyle(.iconOnly)
                    .imageScale(.medium)
                    .foregroundColor(color)
                    .frame(width: 29, height: 29)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(color.opacity(0.15))
                    )

                label.labelStyle(.titleOnly)
            }
        } else {
            content
        }
    }
}

extension View {
    func settingsIcon(color: Color) -> some View {
        modifier(SettingsIconStyle(color: color))
    }
}

struct SettingsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var exportManager = ExportManager.shared
    @StateObject private var companyManager = CompanyManager.shared
    
    @EnvironmentObject private var settings: Settings
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var nextNotificationTime: Date?
    @State private var versionTapCount = 0
    @State private var showEasterEgg = false
    @State private var isVersionAnimating = false

    @State private var startDate = Date.distantPast
    @State private var endDate = Date()
    @State private var showDatePicker = false
    @State private var selectedDateRange = "全部"
    @State private var exportType = "压缩包📦"

    private let dateRange = ["全部", "最近一个月", "最近三个月", "自定义"]
    private let exportTypes = ["压缩包📦", "文件夹📂"]

    var body: some View {
        NavigationView {
            Form {
                Section("公司信息") {
                    HStack {
                        Text(settings.currentCompany)
                            .foregroundColor(.gray)
                        Spacer()
                        Button("编辑") {
                            // Create a temporary company name for editing
                            let tempName = settings.currentCompany

                            let alert = UIAlertController(
                                title: "编辑公司名称",
                                message: "请输入新的公司名称",
                                preferredStyle: .alert
                            )

                            alert.addTextField { textField in
                                textField.text = tempName
                                textField.placeholder = "公司名称"
                            }

                            let cancelAction = UIAlertAction(
                                title: "取消",
                                style: .cancel
                            )

                            let confirmAction = UIAlertAction(
                                title: "确定",
                                style: .default
                            ) { [weak alert] _ in
                                guard let textField = alert?.textFields?.first,
                                    let newName = textField.text?.trimmingCharacters(
                                        in: .whitespacesAndNewlines)
                                else { return }

                                Task {
                                    do {
                                        try await companyManager.updateCompanyName(newName, modelContext: modelContext)
                                        settings.currentCompany = newName
                                    } catch CompanyError.emptyName {
                                        alertMessage = "公司名称不能为空"
                                        showingAlert = true
                                    } catch {
                                        alertMessage = "更新公司名称失败"
                                        showingAlert = true
                                    }
                                }
                            }

                            alert.addAction(cancelAction)
                            alert.addAction(confirmAction)

                            // Present the alert
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first,
                               let rootVC = window.rootViewController {
                                rootVC.present(alert, animated: true)
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }

                Section("提醒时间") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("📅")
                                .settingsIcon(color: .blue)
                            Text("休息日选项")
                        }
                        Picker("工作日选项", selection: $settings.workSchedule) {
                            ForEach(
                                [
                                    WorkScheduleType.doubleWeekend,
                                    WorkScheduleType.singleWeekend,
                                    WorkScheduleType.alternatingWeekend,
                                    WorkScheduleType.custom,
                                ], id: \.self
                            ) { type in
                                Text(type.rawValue)
                                    .tag(type)
                                    .foregroundColor(
                                        settings.workSchedule == type ? .white : .primary
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                settings.workSchedule == type
                                                    ? type.backgroundColor : Color.clear)
                                    )
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: settings.workSchedule) { _ in
                            updateNextNotificationTime()
                        }

                        if settings.workSchedule == .alternatingWeekend {
                            Toggle(isOn: $settings.isLongWeek) {
                                HStack {
                                    Text("📊")
                                        .settingsIcon(color: .purple)
                                    Text("本周为大周")
                                }
                            }
                            .padding(.top, 8)
                            .onChange(of: settings.isLongWeek) { _ in
                                updateNextNotificationTime()
                            }
                        } else if settings.workSchedule == .custom {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("选择休息日")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                
                                let weekdays = [
                                    (2, "周一"),
                                    (3, "周二"),
                                    (4, "周三"),
                                    (5, "周四"),
                                    (6, "周五"),
                                    (7, "周六"),
                                    (1, "周日")
                                ]
                                
                                ForEach(weekdays, id: \.0) { weekday, name in
                                    Toggle(isOn: Binding(
                                        get: { settings.customWeekendSettings.restDays.contains(weekday) },
                                        set: { isOn in
                                            if isOn {
                                                settings.customWeekendSettings.restDays.insert(weekday)
                                            } else {
                                                settings.customWeekendSettings.restDays.remove(weekday)
                                            }
                                            updateNextNotificationTime()
                                        }
                                    )) {
                                        Text(name)
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        HStack {
                            Text("🌞")
                                .settingsIcon(color: .orange)
                            Text("上班打卡时间")
                        }
                        Spacer()
                        TimeDisplayButton(
                            hour: $settings.workTime.startHour,
                            minute: $settings.workTime.startMinute
                        )
                        .onChange(of: settings.workTime.startHour) { _ in
                            updateNextNotificationTime()
                        }
                        .onChange(of: settings.workTime.startMinute) { _ in
                            updateNextNotificationTime()
                        }
                    }

                    HStack {
                        HStack {
                            Text("🌙")
                                .settingsIcon(color: .indigo)
                            Text("下班打卡时间")
                        }
                        Spacer()
                        TimeDisplayButton(
                            hour: $settings.workTime.endHour,
                            minute: $settings.workTime.endMinute,
                            isEndTime: true,
                            startHour: settings.workTime.startHour,
                            startMinute: settings.workTime.startMinute
                        )
                        .onChange(of: settings.workTime.endHour) { _ in
                            updateNextNotificationTime()
                        }
                        .onChange(of: settings.workTime.endMinute) { _ in
                            updateNextNotificationTime()
                        }
                    }

                    if let nextTime = nextNotificationTime {
                        HStack {
                            HStack {
                                Text("⏰")
                                    .settingsIcon(color: .blue)
                                Text("下次提醒时间")
                            }
                            Spacer()
                            Text(formatNextNotificationTime(nextTime))
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                    }
                }

                Section("数据导出") {
                    Picker("导出时间范围", selection: $selectedDateRange) {
                        ForEach(dateRange, id: \.self) { range in
                            Text(range).tag(range)
                        }
                    }
                    .onChange(of: selectedDateRange) { _, newValue in
                        updateDateRange(for: newValue)
                    }

                    HStack {
                        Text("导出为")
                        Spacer()

                        Picker("导出格式", selection: $exportType) {
                            ForEach(exportTypes, id: \.self) { type in
                                Text(type)
                                    .tag(type)
                                    .foregroundColor(exportType == type ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(exportType == type ? Color.blue : Color.clear)
                                    )
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if selectedDateRange == "自定义" {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: [.date])
                        DatePicker("结束日期", selection: $endDate, displayedComponents: [.date])
                    }

                    if exportManager.isExporting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("正在导出 \(exportManager.processedItems)/\(exportManager.totalItems) 项")
                                .font(.footnote)
                                .foregroundColor(.secondary)

                            ProgressView(value: exportManager.exportProgress)
                                .progressViewStyle(.linear)
                                .frame(height: 4)
                        }
                        .padding(.vertical, 4)
                    }

                    Button(action: {
                        Task {
                            do {
                                try await exportManager.exportData(
                                    modelContext: modelContext,
                                    startDate: startDate,
                                    endDate: endDate,
                                    exportType: exportType
                                )
                            } catch {
                                alertMessage = "导出失败：\(error.localizedDescription)"
                                showingAlert = true
                            }
                        }
                    }) {
                        HStack {
                            if exportManager.isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, 8)
                            }
                            Text(exportManager.isExporting ? "导出中..." : "一键导出数据")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(exportManager.isExporting)
                }

                Section("权限设置") {
                    HStack {
                        HStack {
                            Text("🔔")
                                .settingsIcon(color: .red)
                            Text("通知权限")
                        }
                        Spacer()
                        if permissionManager.isNotificationAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("请求权限") {
                                permissionManager.requestNotificationPermission { granted in
                                    if granted {
                                        alertMessage = "通知权限获取成功"
                                    } else {
                                        alertMessage = "通知权限获取失败，请在系统设置中开启"
                                    }
                                    showingAlert = true
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }

                    HStack {
                        HStack {
                            Text("📸")
                                .settingsIcon(color: Color(red: 0.6, green: 0.6, blue: 0.6))
                            Text("相机权限")
                        }
                        Spacer()
                        if permissionManager.isCameraAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("请求权限") {
                                permissionManager.requestCameraPermission { granted in
                                    if granted {
                                        alertMessage = "相机权限获取成功"
                                    } else {
                                        alertMessage = "相机权限获取失败，请在系统设置中开启"
                                    }
                                    showingAlert = true
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }

                    HStack {
                        HStack {
                            Text("🎙️")
                                .settingsIcon(color: .orange)
                            Text("录音权限")
                        }
                        Spacer()
                        if permissionManager.isMicrophoneAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("请求权限") {
                                permissionManager.requestMicrophonePermission { granted in
                                    if granted {
                                        alertMessage = "录音权限获取成功"
                                    } else {
                                        alertMessage = "录音权限获取失败，请在系统设置中开启"
                                    }
                                    showingAlert = true
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack {
                                Text("📍")
                                    .settingsIcon(color: .blue)
                                Text("位置权限")
                            }
                            Spacer()
                            if permissionManager.isLocationAuthorized {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Button("请求权限") {
                                    permissionManager.requestLocationPermission()
                                }
                                .foregroundColor(.blue)
                            }
                        }
                        Text("用于获取经纬度坐标")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack {
                                Text("📶")
                                    .settingsIcon(color: .green)
                                Text("移动网络数据")
                            }
                            Spacer()
                            if settings.isCellularDataEnabled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Button("前往设置") {
                                    permissionManager.openSettings()
                                }
                                .foregroundColor(.blue)
                            }
                        }
                        Text("用于坐标转换为具体的地理位置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                
                Section("重要说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("⚠️")
                                .settingsIcon(color: .red)
                            Text("删除 App 会删除所有留痕记录，请在删除 App 前导出重要记录。")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }

                    Button(action: {
                        if let url = URL(
                            string:
                                "https://nolimit35.feishu.cn/wiki/Fes3wK9cIiyb2UkPGBwcs4BDnmh?from=from_copylink"
                        ) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("❓")
                                .settingsIcon(color: .pink)
                            Text("水印打卡是否具有法律效益")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }


                Section("其他") {
                    HStack {
                        Text("🎨")
                            .settingsIcon(color: .purple)
                        Spacer()
                        Picker("主题设置", selection: $settings.colorScheme) {
                            ForEach(ColorSchemePreference.allCases, id: \.self) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Button(action: {
                        if let url = URL(
                            string:
                                "https://nolimit35.feishu.cn/share/base/form/shrcn4bB9vNvXyIsbWlnfANAbVb"
                        ) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("💡")
                                .settingsIcon(color: .orange)
                            Text("意见反馈")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }

                    Button(action: {
                        if let url = URL(
                            string:
                                "https://nolimit35.feishu.cn/share/base/form/shrcnrGgmv9bZokZVwN1IYxJY0E"
                        ) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("🎁")
                                .settingsIcon(color: .pink)
                            Text("推广返会员")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }

                Section("关于") {
                    Button(action: {
                        // 触发动画
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                            isVersionAnimating = true
                        }
                        // 重置动画状态
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            isVersionAnimating = false
                        }
                        
                        versionTapCount += 1
                        print("版本号被点击: 第\(versionTapCount)次")
                        if versionTapCount == 11 {
                            print("触发彩蛋显示")
                            showEasterEgg = true
                            versionTapCount = 0
                            // 3秒后自动隐藏
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                print("彩蛋自动隐藏")
                                showEasterEgg = false
                            }
                        }
                    }) {
                        HStack {
                            Text("📱")
                                .settingsIcon(color: .green)
                            Text("版本")
                            Spacer()
                            Text("v\(getAppVersion())")
                                .foregroundColor(.gray)
                                .scaleEffect(isVersionAnimating ? 1.2 : 1.0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if let url = URL(string: "https://apps.apple.com/app/id6740536209") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("🔄")
                                .settingsIcon(color: .orange)
                            Text("检查更新")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }

                    Button(action: {
                        if let url = URL(string: "https://work-trace.nolimit35.cn/privacy") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("🔒")
                                .settingsIcon(color: .purple)
                            Text("隐私政策")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }

                Button(action: {
                    if let url = URL(string: "https://nolimit35.cn") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("不限进步出品 ©2025")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("设置")
            .alert("通知提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .overlay {
                if showEasterEgg {
                    VStack {
                        Spacer()
                        Text("小迪万岁~😘")
                            .foregroundColor(.primary)
                            .font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(uiColor: UIColor.systemBackground))
                                    .colorInvert()
                                    .opacity(0.1)
                            )
                            .transition(.scale.combined(with: .opacity))
                        Spacer()
                    }
                }
            }
            .onAppear {
                notificationManager.setSettings(settings)
                notificationManager.checkNotificationStatus()
                updateNextNotificationTime()
                // 初始化时间范围并计算总数
                updateDateRange(for: selectedDateRange)
                // 检查所有权限状态
                permissionManager.checkPermissions()
            }
            .onChange(of: modelContext.hasChanges) { _ in
                // 数据库有变化时重新计算总数
                Task {
                    await exportManager.calculateTotalItems(modelContext: modelContext, startDate: startDate, endDate: endDate)
                }
            }
        }
    }

    private func formatNextNotificationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: date)
    }

    private func updateNextNotificationTime() {
        // 先重新调度通知
        notificationManager.scheduleWorkNotifications(
            startTime: settings.workTime,
            endTime: settings.workTime
        )

        // 然后获取下一次通知时间
        notificationManager.getNextNotificationTime { date in
            if let date = date {
                print("下次通知时间: \(formatNextNotificationTime(date))")
            } else {
                print("没有找到下次通知时间")
            }
            nextNotificationTime = date
        }
    }

    private func getAppVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return version
    }

    private func updateDateRange(for newValue: String) {
        switch newValue {
        case "最近一个月":
            startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            endDate = Date()
        case "最近三个月":
            startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
            endDate = Date()
        case "全部":
            startDate = Date.distantPast
            endDate = Date()
        default:
            showDatePicker = true
        }
        
        Task {
            await exportManager.calculateTotalItems(modelContext: modelContext, startDate: startDate, endDate: endDate)
        }
    }
}

extension WorkScheduleType {
    var backgroundColor: Color {
        switch self {
        case .doubleWeekend:
            return Color(red: 0.4, green: 0.8, blue: 0.4)  // 更鲜艳的绿色
        case .singleWeekend:
            return Color(red: 0.95, green: 0.8, blue: 0.3)  // 更鲜艳的黄色
        case .alternatingWeekend:
            return Color(red: 0.9, green: 0.4, blue: 0.4)  // 更鲜艳的红色
        case .custom:
            return Color(red: 0.4, green: 0.4, blue: 0.9)  // 更鲜艳的蓝色
        }
    }
}
