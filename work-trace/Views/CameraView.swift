import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation
import UIKit

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var locationString: String = "未知位置"
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // 添加用于缓存的属性
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodingTime: Date?
    private let minimumGeocodingInterval: TimeInterval = 2.0  // 最小间隔2秒
    private let significantDistanceThreshold: CLLocationDistance = 50.0  // 50米的显著距离变化阈值
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10  // 10米的最小距离过滤
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        self.location = newLocation
        
        // 设置默认的经纬度字符串
        let coordinates = String(format: "%.6f, %.6f", newLocation.coordinate.latitude, newLocation.coordinate.longitude)
        
        // 检查是否需要进行反地理编码
        let shouldGeocodeLocation = shouldPerformGeocoding(for: newLocation)
        
        if shouldGeocodeLocation {
            // 更新最后一次地理编码的时间和位置
            lastGeocodingTime = Date()
            lastGeocodedLocation = newLocation
            
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(newLocation) { [weak self] placemarks, error in
                if let placemark = placemarks?.first {
                    let address = [
                        placemark.locality,        // 城市
                        placemark.subLocality,     // 区
                        placemark.thoroughfare,    // 街道
                        placemark.subThoroughfare  // 门牌号
                    ].compactMap { $0 }.joined(separator: "")
                    
                    if !address.isEmpty {
                        self?.locationString = address
                    } else {
                        self?.locationString = coordinates
                    }
                } else {
                    self?.locationString = coordinates
                }
            }
        } else {
            // 如果不进行反地理编码，就使用坐标字符串
            self.locationString = coordinates
        }
    }
    
    private func shouldPerformGeocoding(for newLocation: CLLocation) -> Bool {
        // 如果是第一次获取位置，允许地理编码
        guard let lastLocation = lastGeocodedLocation,
              let lastTime = lastGeocodingTime else {
            return true
        }
        
        // 检查时间间隔
        let timeSinceLastGeocoding = Date().timeIntervalSince(lastTime)
        guard timeSinceLastGeocoding >= minimumGeocodingInterval else {
            return false
        }
        
        // 检查距离变化
        let distanceChanged = newLocation.distance(from: lastLocation)
        return distanceChanged >= significantDistanceThreshold
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        if location == nil {
            locationString = "未知位置"
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse {
            startUpdatingLocation()
        }
    }
}

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: Settings
    @Environment(\.modelContext) private var modelContext
    @State private var image: UIImage?
    @State private var showingSaveError = false
    @State private var showingSaveSuccess = false
    @State private var locationManager = LocationManager()
    @State private var showingTimeError = false
    @State private var serverTime: Date?
    @State private var timeOffset: TimeInterval = 0  // 添加时间偏移量
    
    var body: some View {
        NavigationView {
            ZStack {
                ImagePicker(image: $image, sourceType: .camera, autoDismiss: false)
                    .navigationBarItems(
                        leading: Button("取消") {
                            dismiss()
                        }
                    )
                    .onChange(of: image) { oldValue, newValue in
                        if let _ = newValue {
                            print("准备保存照片，当前公司名称：\(settings.currentCompany)")
                            Task {
                                // 在拍照时刻重新检查时间同步
                                let (isValid, ntpTime) = await NTPManager.shared.checkTimeSync()
                                if !isValid {
                                    serverTime = ntpTime
                                    showingTimeError = true
                                    image = nil  // 清除拍摄的照片
                                    return
                                }
                                
                                // 更新时间偏移量
                                if let ntpTime = ntpTime {
                                    timeOffset = ntpTime.timeIntervalSince(Date())
                                    print("拍照时刻系统时间偏移量: \(timeOffset) 秒")
                                }
                                
                                // 保存照片
                                if savePhoto() {
                                    showingSaveSuccess = true
                                    // 延迟一秒后关闭，给用户一个保存成功的反馈
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        dismiss()
                                    }
                                } else {
                                    showingSaveError = true
                                    // 如果保存失败，清除图片
                                    image = nil
                                }
                            }
                        }
                    }
                    .edgesIgnoringSafeArea(.all)
                
                if showingSaveSuccess {
                    // 显示保存成功的提示
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 50))
                        Text("保存成功")
                            .foregroundColor(.white)
                            .font(.headline)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.7))
                }
            }
        }
        .navigationTitle("记录工作")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.all)
        .alert("保存失败", isPresented: $showingSaveError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("请确保已设置公司名称")
        }
        .alert("时间校验失败", isPresented: $showingTimeError) {
            Button("确定", role: .cancel) {
                dismiss()
            }
        } message: {
            if let serverTime = serverTime {
                Text("您的设备时间与北京时间不符\n当前北京时间: \(serverTime.formatted(date: .complete, time: .complete))")
            } else {
                Text("无法获取准确的北京时间，请检查网络连接")
            }
        }
        .task {
            // 检查时间同步
            let (isValid, ntpTime) = await NTPManager.shared.checkTimeSync()
            if !isValid {
                serverTime = ntpTime
                showingTimeError = true
            } else if let ntpTime = ntpTime {
                // 计算时间偏移量
                timeOffset = ntpTime.timeIntervalSince(Date())
                print("系统时间偏移量: \(timeOffset) 秒")
            }
        }
        .onAppear {
            print("CameraView appeared, current company: \(settings.currentCompany)")
            locationManager.startUpdatingLocation()
        }
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
    
    private func compressImage(_ image: UIImage) -> Data? {
        // 目标文件大小 (1MB)
        let targetSizeInBytes = 1024 * 1024
        
        // 首先检查原始图片大小
        if let originalData = image.jpegData(compressionQuality: 1.0),
           originalData.count <= targetSizeInBytes {
            return originalData
        }
        
        // 智能调整最大尺寸
        let maxDimension: CGFloat
        if max(image.size.width, image.size.height) > 4000 {
            maxDimension = 1440 // 对超大图片采用更激进的压缩
        } else {
            maxDimension = 1920
        }
        
        // 计算缩放比例
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        // 使用更高效的绘图上下文
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.preferredRange = .standard
        format.opaque = true // 如果图片没有透明度，设置为true可以提高性能
        
        let resizedImage = autoreleasepool { () -> UIImage in
            UIGraphicsImageRenderer(size: newSize, format: format).image { context in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        
        // 二分法查找最佳压缩质量
        var maxQuality: CGFloat = 1.0
        var minQuality: CGFloat = 0.0
        var bestData: Data?
        
        // 最多尝试8次二分查找
        for _ in 0..<8 {
            let midQuality = (maxQuality + minQuality) / 2
            if let data = resizedImage.jpegData(compressionQuality: midQuality) {
                if data.count <= targetSizeInBytes {
                    bestData = data
                    minQuality = midQuality
                } else {
                    maxQuality = midQuality
                }
            }
        }
        
        // 如果二分查找失败，使用最低质量
        if bestData == nil {
            bestData = resizedImage.jpegData(compressionQuality: 0.1)
        }
        
        return bestData
    }
    
    private func getCurrentTime() -> Date {
        // 使用系统时间加上偏移量得到准确时间
        return Date().addingTimeInterval(timeOffset)
    }
    
    private func savePhoto() -> Bool {
        // 确保公司名称不为空
        guard !settings.currentCompany.isEmpty,
              let image = image,
              let compressedData = compressImage(image) else {
            print("保存失败：数据验证未通过")
            print("公司名称为空：\(settings.currentCompany.isEmpty)")
            print("图片为空：\(image == nil)")
            return false
        }
        
        print("开始保存照片，公司名称：\(settings.currentCompany)")
        print("压缩后的图片大小：\(Double(compressedData.count) / 1024.0 / 1024.0)MB")
        
        // 使用NTP校准后的时间
        let now = getCurrentTime()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let totalMinutes = hour * 60 + minute
        
        // 从设置中读取上下班时间
        let checkInTime = settings.workTime.startHour * 60 + settings.workTime.startMinute
        let checkOutTime = settings.workTime.endHour * 60 + settings.workTime.endMinute
        let bufferMinutes = 30 // 前后30分钟缓冲时间
        
        let tag: WorkTag
        if totalMinutes >= (checkInTime - bufferMinutes) && totalMinutes <= (checkInTime + bufferMinutes) {
            tag = .checkIn  // 上班打卡时间段
        } else if totalMinutes >= (checkOutTime - bufferMinutes) && totalMinutes <= (checkOutTime + bufferMinutes) {
            tag = .checkOut // 下班打卡时间段
        } else if totalMinutes > (checkOutTime + bufferMinutes) {
            tag = .overtime // 加班打卡
        } else {
            tag = .other   // 其他工作时间
        }
        
        let photo = WorkPhoto(
            imageData: compressedData,
            timestamp: now,
            location: locationManager.locationString,
            companyName: settings.currentCompany,
            tag: tag,
            fileType: .image
        )
        
        do {
            // 查找或创建公司
            let descriptor = FetchDescriptor<Company>()
            let companies = try modelContext.fetch(descriptor)
            print("当前已有公司数量：\(companies.count)")
            
            let company: Company
            
            if let existingCompany = companies.first(where: { $0.name == settings.currentCompany }) {
                print("找到已存在的公司：\(existingCompany.name)")
                company = existingCompany
            } else {
                print("创建新公司：\(settings.currentCompany)")
                company = Company(name: settings.currentCompany)
                modelContext.insert(company)
            }
            
            // 添加照片
            company.photos.append(photo)
            print("添加照片到公司，当前照片数量：\(company.photos.count)")
            
            // 保存更改
            try modelContext.save()
            print("成功保存到数据库")
            return true
            
        } catch {
            print("保存照片失败，错误详情: \(error)")
            return false
        }
    }
} 
