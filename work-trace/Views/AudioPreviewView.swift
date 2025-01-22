import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

class AudioPlayer: NSObject, ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isFinished = false
    private var timer: Timer?

    override init() {
        super.init()
    }

    func setupAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            isFinished = false
            startTimer()
        } catch {
            print("音频播放器初始化失败: \(error)")
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0
            if self.currentTime >= self.duration {
                self.isFinished = true
            }
        }
    }

    func play() {
        audioPlayer?.play()
        isPlaying = true
        isFinished = false
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        isFinished = false
        timer?.invalidate()
        timer = nil
    }

    func replay() {
        audioPlayer?.currentTime = 0
        play()
    }

    deinit {
        stop()
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isFinished = true
        }
    }
}

struct AudioPreviewView: View {
    let photo: WorkPhoto
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var temporaryAudioURL: URL?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 EEEE HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    // 获取应用图标
    private var appIcon: Image {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let icon = scene.activationState == .foregroundActive ? UIImage(named: "AppIcon") : nil {
            return Image(uiImage: icon)
        }
        // 如果无法获取图标，返回默认图标
        return Image(systemName: "waveform")
    }

    private func createTemporaryAudioFile(from audioData: Data) -> URL? {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let safeTitle = photo.title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "\(safeTitle).m4a"
        let fileURL = temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try audioData.write(to: fileURL)
            return fileURL
        } catch {
            print("Error creating temporary audio file: \(error)")
            return nil
        }
    }

    private func cleanupTemporaryFile() {
        if let url = temporaryAudioURL {
            try? FileManager.default.removeItem(at: url)
            temporaryAudioURL = nil
        }
    }

    var body: some View {
        ZStack {
            // 背景
            Color.black.edgesIgnoringSafeArea(.all)

            // 主内容
            VStack(spacing: 0) {
                // 顶部工具栏
                HStack {
                    Button(action: {
                        audioPlayer.stop()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Spacer()

                    if let audioData = photo.audioData,
                       let audioURL = createTemporaryAudioFile(from: audioData) {
                        ShareLink(item: audioURL, preview: SharePreview(
                            "\(photo.title).m4a"
                        )) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .onDisappear {
                            cleanupTemporaryFile()
                        }
                    }
                }
                .padding()

                Spacer()

                // 中间的音频播放区域
                VStack(spacing: 32) {
                    // 波形动画效果
                    Image(systemName: "waveform")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.purple.opacity(audioPlayer.isPlaying ? 0.8 : 0.4))
                        .frame(width: 200, height: 200)
                        .animation(.easeInOut(duration: 0.3), value: audioPlayer.isPlaying)

                    // 进度条和控制区域
                    VStack(spacing: 16) {
                        // 自定义进度条
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // 背景条
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 4)
                                
                                // 进度条
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.purple, .purple.opacity(0.8)]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * CGFloat(audioPlayer.currentTime / max(audioPlayer.duration, 1)), height: 4)
                            }
                        }
                        .frame(height: 4)
                        
                        // 时间显示
                        HStack {
                            Text(formatTime(audioPlayer.currentTime))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(formatTime(audioPlayer.duration))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .font(.system(size: 13, weight: .regular))
                        
                        // 播放控制按钮
                        HStack(spacing: 20) {
                            // 播放/暂停按钮
                            Button(action: {
                                if audioPlayer.isPlaying {
                                    audioPlayer.pause()
                                } else {
                                    audioPlayer.play()
                                }
                            }) {
                                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(audioPlayer.isPlaying ? .white.opacity(0.3) : .white.opacity(0.8))
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // 重播按钮
                            if audioPlayer.isFinished {
                                Button(action: {
                                    audioPlayer.replay()
                                }) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .resizable()
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.top, 8)
                        .animation(.spring(duration: 0.3), value: audioPlayer.isFinished)
                    }
                    .padding(.horizontal, 40)
                }

                Spacer()

                // 底部信息栏
                VStack(spacing: 8) {
                    Text(photo.tag.rawValue)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(photo.tag.color.opacity(0.2))
                        .foregroundColor(photo.tag.color)
                        .clipShape(Capsule())

                    Text(Self.dateFormatter.string(from: photo.timestamp))
                        .font(.system(size: 14))
                        .foregroundColor(.white)

                    if let location = photo.location {
                        Text(location)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            if let audioData = photo.audioData {
                audioPlayer.setupAudio(data: audioData)
                // 自动播放
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    audioPlayer.play()
                }
            }
        }
        .onDisappear {
            audioPlayer.stop()
            cleanupTemporaryFile()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// 添加自定义按钮样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
