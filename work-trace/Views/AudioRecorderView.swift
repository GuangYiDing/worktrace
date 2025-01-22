import SwiftUI
import SwiftData
import AVFoundation

@Observable
class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    var audioRecorder: AVAudioRecorder?
    var isRecording = false
    var recordingURL: URL?
    
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    // 添加音频会话处理
    private var audioSession: AVAudioSession {
        AVAudioSession.sharedInstance()
    }
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    deinit {
        removeNotifications()
    }
    
    private func setupNotifications() {
        // 监听音频会话中断
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // 监听路由变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // 中断开始，保存录音状态
            if isRecording {
                _ = stopRecording()
            }
        case .ended:
            // 中断结束，检查是否可以恢复录音
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                startRecording()
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // 处理音频路由变化
        switch reason {
        case .oldDeviceUnavailable:
            // 如果旧设备不可用（例如拔出耳机），停止录音
            if isRecording {
                _ = stopRecording()
            }
        default:
            break
        }
    }
    
    private func generateMockAudioData() -> Data {
        // 生成1秒钟的44.1kHz, 16位深度的静音WAV数据
        let sampleRate = 44100
        let duration = 1.0
        let numSamples = Int(duration * Double(sampleRate))
        
        var audioData = Data()
        
        // WAV文件头
        let headerSize = 44
        var header = Data(count: headerSize)
        
        // RIFF chunk
        header.replaceSubrange(0..<4, with: "RIFF".data(using: .ascii)!)
        let fileSize = UInt32(numSamples * 2 + headerSize - 8).littleEndian
        header.replaceSubrange(4..<8, with: withUnsafeBytes(of: fileSize) { Data($0) })
        header.replaceSubrange(8..<12, with: "WAVE".data(using: .ascii)!)
        
        // fmt chunk
        header.replaceSubrange(12..<16, with: "fmt ".data(using: .ascii)!)
        let fmtSize = UInt32(16).littleEndian
        header.replaceSubrange(16..<20, with: withUnsafeBytes(of: fmtSize) { Data($0) })
        let audioFormat = UInt16(1).littleEndian // PCM
        header.replaceSubrange(20..<22, with: withUnsafeBytes(of: audioFormat) { Data($0) })
        let numChannels = UInt16(1).littleEndian // Mono
        header.replaceSubrange(22..<24, with: withUnsafeBytes(of: numChannels) { Data($0) })
        let sampleRateLE = UInt32(sampleRate).littleEndian
        header.replaceSubrange(24..<28, with: withUnsafeBytes(of: sampleRateLE) { Data($0) })
        let byteRate = UInt32(sampleRate * 2).littleEndian
        header.replaceSubrange(28..<32, with: withUnsafeBytes(of: byteRate) { Data($0) })
        let blockAlign = UInt16(2).littleEndian
        header.replaceSubrange(32..<34, with: withUnsafeBytes(of: blockAlign) { Data($0) })
        let bitsPerSample = UInt16(16).littleEndian
        header.replaceSubrange(34..<36, with: withUnsafeBytes(of: bitsPerSample) { Data($0) })
        
        // data chunk
        header.replaceSubrange(36..<40, with: "data".data(using: .ascii)!)
        let dataSize = UInt32(numSamples * 2).littleEndian
        header.replaceSubrange(40..<44, with: withUnsafeBytes(of: dataSize) { Data($0) })
        
        audioData.append(header)
        
        // 生成静音音频数据
        var samples = [Int16](repeating: 0, count: numSamples)
        audioData.append(Data(bytes: &samples, count: samples.count * 2))
        
        return audioData
    }
    
    func startRecording() {
        if isSimulator {
            isRecording = true
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
            recordingURL = tempURL
            return
        }
        
        do {
            // 配置音频会话支持后台录音
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 尝试将输入增益设置为最大
            try audioSession.setInputGain(1.0)
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
                AVEncoderBitRateKey: 128000,
                AVEncoderBitDepthHintKey: 16,
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            
            // 开始录音并激活后台音频会话
            audioRecorder?.record()
            
            recordingURL = audioFilename
            isRecording = true
            
        } catch {
            print("录音初始化失败: \(error)")
        }
    }
    
    func stopRecording() -> URL? {
        if isSimulator {
            guard let url = recordingURL else { return nil }
            do {
                let audioData = generateMockAudioData()
                try audioData.write(to: url)
            } catch {
                print("Failed to write mock audio data: \(error)")
                return nil
            }
            isRecording = false
            return url
        }
        
        audioRecorder?.stop()
        
        do {
            // 停止录音时取消激活音频会话
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("停止音频会话失败: \(error)")
        }
        
        isRecording = false
        return recordingURL
    }
}

struct AudioRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: Settings
    @Environment(\.modelContext) private var modelContext
    @State private var audioRecorder = AudioRecorder()
    @State private var showingSaveError = false
    @State private var showingSaveSuccess = false
    @State private var showingRecordingComplete = false
    @State private var locationManager = LocationManager()
    @State private var showingTimeError = false
    @State private var serverTime: Date?
    @State private var timeOffset: TimeInterval = 0
    @State private var isTimeValid = false
    @State private var rippleScale: CGFloat = 1.0 // 添加波纹缩放状态
    
    private func getCurrentTime() -> Date {
        // 使用系统时间加上偏移量得到准确时间
        return Date().addingTimeInterval(timeOffset)
    }
    
    private func checkTimeSync() async -> Bool {
        // 检查时间同步
        let (isValid, ntpTime) = await NTPManager.shared.checkTimeSync()
        if !isValid {
            serverTime = ntpTime
            showingTimeError = true
            return false
        }
        
        // 更新时间偏移量
        if let ntpTime = ntpTime {
            timeOffset = ntpTime.timeIntervalSince(Date())
            print("录音时刻系统时间偏移量: \(timeOffset) 秒")
        }
        return true
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Spacer()
                    
                    // 录音状态指示
                    if audioRecorder.isRecording {
                        Text("正在录音...")
                            .foregroundColor(.white)
                            .font(.title)
                    } else {
                        Button(action: {
                            Task {
                                if await checkTimeSync() {
                                    audioRecorder.startRecording()
                                }
                            }
                        }) {
                            Text("点击开始录音")
                                .foregroundColor(.white)
                                .font(.title)
                        }
                    }
                    
                    Spacer()
                    
                    // 录音按钮
                    ZStack {
                        // 外层波纹动画
                        if audioRecorder.isRecording {
                            ForEach(0..<3) { index in
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(rippleScale)
                                    .opacity(2 - rippleScale)
                                    .animation(
                                        Animation.easeInOut(duration: 1)
                                            .repeatForever(autoreverses: false)
                                            .delay(Double(index) * 0.3),
                                        value: rippleScale
                                    )
                            }
                        }
                        
                        // 中心录音按钮
                        Button(action: {
                            Task {
                                if audioRecorder.isRecording {
                                    if await checkTimeSync(), let recordingURL = audioRecorder.stopRecording() {
                                        saveAudioRecording(url: recordingURL)
                                    }
                                } else {
                                    if await checkTimeSync() {
                                        audioRecorder.startRecording()
                                    }
                                }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(audioRecorder.isRecording ? Color.red : Color.white)
                                    .frame(width: 80, height: 80)
                                
                                if audioRecorder.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white)
                                        .frame(width: 30, height: 30)
                                } else {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 60, height: 60)
                                }
                            }
                        }
                    }
                    .onAppear {
                        // 启动波纹动画
                        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                            rippleScale = 2.0
                        }
                    }
                    .padding(.bottom, 50)
                }
                
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
            .navigationBarItems(
                leading: Button("取消") {
                    if audioRecorder.isRecording {
                        _ = audioRecorder.stopRecording()
                    }
                    dismiss()
                }
            )
        }
        .navigationTitle("录音")
        .navigationBarTitleDisplayMode(.inline)
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
            isTimeValid = isValid
            if !isValid {
                serverTime = ntpTime
                showingTimeError = true
            } else if let ntpTime = ntpTime {
                // 计算时间偏移量
                timeOffset = ntpTime.timeIntervalSince(Date())
                print("初始系统时间偏移量: \(timeOffset) 秒")
            }
        }
        .onAppear {
            locationManager.startUpdatingLocation()
        }
    }
    
    private func saveAudioRecording(url: URL) {
        guard !settings.currentCompany.isEmpty else {
            showingSaveError = true
            return
        }
        
        do {
            let audioData = try Data(contentsOf: url)
            
            // 使用NTP校准后的时间
            let now = getCurrentTime()
            let photo = WorkPhoto(
                audioData: audioData,
                timestamp: now,
                location: locationManager.locationString,
                companyName: settings.currentCompany
            )
            
            // 查找或创建公司
            let descriptor = FetchDescriptor<Company>()
            let companies = try modelContext.fetch(descriptor)
            
            let company: Company
            if let existingCompany = companies.first(where: { $0.name == settings.currentCompany }) {
                company = existingCompany
            } else {
                company = Company(name: settings.currentCompany)
                modelContext.insert(company)
            }
            
            company.photos.append(photo)
            try modelContext.save()
            
            showingSaveSuccess = true
            // 延迟一秒后关闭，给用户一个保存成功的反馈
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismiss()
                // 重置全局状态
                AppState.shared.shouldShowAudioRecorder = false
                // 切换到工作记录标签页
                AppState.shared.selectedTab = 0
            }
            
        } catch {
            print("保存录音失败: \(error)")
            showingSaveError = true
        }
        
        // 删除临时录音文件
        try? FileManager.default.removeItem(at: url)
    }
} 