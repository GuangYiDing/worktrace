import SwiftUI
import SwiftData

struct PhotoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Company.name) private var companies: [Company]
    @EnvironmentObject private var settings: Settings
    
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    
    // 创建一个以周一为第一天的日历
    private var chineseCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2  // 2 代表周一
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
    
    var body: some View {
        NavigationView {
            if companies.isEmpty {
                ContentUnavailableView("暂无记录", 
                    systemImage: "photo.stack",
                    description: Text("拍照或录音后会显示在这里"))
                    .navigationTitle("留痕记录")
            } else {
                List {
                    Section(header: Text("概览")){              
                        let endDate = Date()
                        let startDate = chineseCalendar.date(byAdding: .month, value: -3, to: endDate)!
                        let numberOfWeeks = Int(ceil(endDate.timeIntervalSince(startDate) / (7 * 24 * 3600)))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // 月份标签行
                            HStack(alignment: .bottom, spacing: 0) {
                                // 左侧空白，对应星期标签的宽度
                                Text("")
                                    .frame(width: 24)
                                
                                // 月份标签
                                HStack(spacing: 4) {
                                    ForEach(0..<numberOfWeeks) { week in
                                        if let date = chineseCalendar.date(byAdding: .day, value: week * 7, to: startDate),
                                           chineseCalendar.component(.day, from: date) <= 7 {
                                            Text(monthFormatter.string(from: date))
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .frame(width: 16, alignment: .center)
                                        } else {
                                            Text("")
                                                .frame(width: 16)
                                        }
                                    }
                                }
                            }
                            
                            // 热力图主体
                            HStack(alignment: .center, spacing: 8) {
                                // 星期标签
                                VStack(alignment: .trailing, spacing: 4) {
                                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                                        Text(weekday)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .frame(width: 16, height: 16)
                                    }
                                }
                                
                                // 热力图格子
                                HStack(spacing: 4) {
                                    ForEach(0..<numberOfWeeks) { week in
                                        VStack(spacing: 4) {
                                            // 获取这一周的起始日期
                                            let weekStartDate = chineseCalendar.date(byAdding: .day, value: week * 7, to: startDate)!
                                            
                                            // 调整到这一周的第一天（周一）
                                            let weekday = chineseCalendar.component(.weekday, from: weekStartDate)
                                            let daysToSubtract = (weekday + 5) % 7 // 将日期调整到本周一
                                            let mondayDate = chineseCalendar.date(byAdding: .day, value: -daysToSubtract, to: weekStartDate)!
                                            
                                            ForEach(0..<7) { dayOffset in
                                                let date = chineseCalendar.date(byAdding: .day, value: dayOffset, to: mondayDate)!
                                                if date <= endDate {
                                                    let count = getPhotoCount(for: date, in: companies)
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(colorForCount(count))
                                                        .frame(width: 16, height: 16)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .strokeBorder(
                                                                    colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray5),
                                                                    lineWidth: 0.5
                                                                )
                                                        )
                                                } else {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.clear)
                                                        .frame(width: 16, height: 16)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // 打卡统计
                            HStack(spacing: 16) {
                                // 左侧空白，对应星期标签的宽度
                                Text("")
                                    .frame(width: 24)
                                
                                let stats = getPhotoStats(in: companies)
                                Group {
                                    HStack(spacing: 4) {
                                        Text("上班")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Text("\(stats.checkIn)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Text("下班")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Text("\(stats.checkOut)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.green)
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Text("加班")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Text("\(stats.overtime)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.orange)
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Text("录音")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Text("\(stats.audio)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.purple)
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Text("其他")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Text("\(stats.other)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    ForEach(companies) { company in
                        Section(header: Text("留痕记录")) {
                            let sortedPhotos = company.photos.sorted(by: { $0.timestamp > $1.timestamp })
                            ForEach(sortedPhotos, id: \.id) { photo in
                                PhotoRow(photo: photo, company: company)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .navigationTitle(companies.first?.name ?? "工作记录")
            }
        }
        .onAppear {
            print("PhotoListView appeared, companies count: \(companies.count)")
            companies.forEach { company in
                print("Company: \(company.name), photos count: \(company.photos.count)")
            }
        }
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    private struct DayCount {
        var photos: Int = 0
        var audios: Int = 0
    }

    private func getPhotoCount(for date: Date, in companies: [Company]) -> DayCount {
        return companies.reduce(DayCount()) { counts, company in
            var newCounts = counts
            company.photos.forEach { item in
                if chineseCalendar.isDate(item.timestamp, inSameDayAs: date) {
                    if item.fileType == .audio {
                        newCounts.audios += 1
                    } else {
                        newCounts.photos += 1
                    }
                }
            }
            return newCounts
        }
    }
    
    private func colorForCount(_ count: DayCount) -> Color {
        let emptyColor: Color = colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
        
        // 如果同时有照片和录音，优先显示录音的颜色
        if count.audios > 0 {
            let purpleColor: Color = .purple
            switch count.audios {
            case 1:
                return purpleColor.opacity(0.3)
            case 2:
                return purpleColor.opacity(0.6)
            case 3:
                return purpleColor.opacity(0.8)
            default:
                return purpleColor
            }
        } else if count.photos > 0 {
            let baseColor: Color = colorScheme == .dark ? .green : .green
            switch count.photos {
            case 1:
                return baseColor.opacity(0.3)
            case 2:
                return baseColor.opacity(0.6)
            case 3:
                return baseColor.opacity(0.8)
            default:
                return baseColor
            }
        }
        return emptyColor
    }

    private struct PhotoStats {
        var checkIn: Int = 0
        var checkOut: Int = 0
        var overtime: Int = 0
        var other: Int = 0
        var audio: Int = 0
    }
    
    private func getPhotoStats(in companies: [Company]) -> PhotoStats {
        var stats = PhotoStats()
        for company in companies {
            for photo in company.photos {
                if photo.fileType == .audio {
                    stats.audio += 1
                    continue
                }
                switch photo.tag {
                case .checkIn:
                    stats.checkIn += 1
                case .checkOut:
                    stats.checkOut += 1
                case .overtime:
                    stats.overtime += 1
                default:
                    stats.other += 1
                }
            }
        }
        return stats
    }
}

struct PhotoRow: View {
    let photo: WorkPhoto
    let company: Company
    @Environment(\.modelContext) private var modelContext
    @State private var showingPreview = false
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 EEEE HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    
    var body: some View {
        Button(action: {
            showingPreview = true
        }) {
            HStack {
                if photo.fileType == .audio {
                    Image(systemName: "waveform.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.purple)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let uiImage = UIImage(data: photo.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(photo.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(photo.tag.rawValue)
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(photo.tag.color.opacity(0.1))
                            .foregroundColor(photo.tag.color)
                            .clipShape(Capsule())
                    }
                    
                    // 日期时间
                    Text(Self.dateFormatter.string(from: photo.timestamp))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    // 位置信息
                    if let location = photo.location {
                        Text(location)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 4)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                showingDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(.red)
            
            Button {
                showingEditSheet = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                withAnimation {
                    deletePhoto()
                }
            }
        } message: {
            Text("删除后照片将无法找回，确定要删除吗？")
        }
        .fullScreenCover(isPresented: $showingPreview) {
            if photo.fileType == .audio {
                AudioPreviewView(photo: photo)
            } else {
                PhotoPreviewView(photo: photo)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            PhotoEditView(photo: photo)
                .presentationDetents([.medium])
        }
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func deletePhoto() {
        // Dispatch deletion to the main queue to avoid state update conflicts
        DispatchQueue.main.async {
            // First remove from the company's photos array
            if let index = company.photos.firstIndex(where: { $0.id == photo.id }) {
                company.photos.remove(at: index)
            }
            
            // Then delete from the model context
            modelContext.delete(photo)
            
            // Save changes after a brief delay to ensure UI updates are complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                try? modelContext.save()
            }
        }
    }
} 