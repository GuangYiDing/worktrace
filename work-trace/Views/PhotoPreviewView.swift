import SwiftUI
import SwiftData
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct SharedPhoto: Transferable {
    let image: UIImage
    let title: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in
            guard let imageData = photo.image.jpegData(compressionQuality: 1.0) else {
                throw URLError(.badServerResponse)
            }
            return imageData
        }
        .suggestedFileName { photo in
            photo.title
        }
    }
}

public struct PhotoPreviewView: View {
    let photo: WorkPhoto
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var finalOffset: CGSize = .zero
    @State private var showControls = true
    @State private var isSharePresented = false
    @State private var cachedImage: UIImage?
    
    private var sharedPhoto: SharedPhoto? {
        guard let image = sharedImage else { return nil }
        return SharedPhoto(image: image, title: "\(photo.title).jpg")
    }
    
    private var sharedImage: UIImage? {
        guard let image = UIImage(data: photo.imageData) else { return nil }
        
        // 创建水印文本
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let watermarkText = """
        公司：\(photo.companyName)
        时间：\(dateFormatter.string(from: photo.timestamp))
        类型：\(photo.tag.rawValue)
        位置：\(photo.location ?? "未知位置")
        """
        
        return addWatermark(to: image, text: watermarkText)
    }
    
    private func addWatermark(to image: UIImage, text: String) -> UIImage? {
        let imageSize = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw the original image
        image.draw(in: CGRect(origin: .zero, size: imageSize))
        
        // 配置文字样式以计算所需空间
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineSpacing = 4 * scale
        
        let fontSize = min(imageSize.width * 0.035, 20.0) * scale
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        
        // 创建带图标的属性字符串
        let buildingIcon = "🏢"
        let clockIcon = "🕐"
        let tagIcon = "🏷️"
        let locationIcon = "📍"
        
        let components = text.components(separatedBy: "\n")
        var attributedText = NSMutableAttributedString()
        
        // 解析原始文本并添加图标
        for (index, line) in components.enumerated() {
            let icon: String
            let content = line.components(separatedBy: "：")[1]
            
            switch index {
            case 0: icon = buildingIcon
            case 1: icon = clockIcon
            case 2: icon = tagIcon
            case 3: icon = locationIcon
            default: icon = ""
            }
            
            let lineText = NSAttributedString(string: "\(icon) \(content)\n", attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ])
            attributedText.append(lineText)
        }
        
        // 计算文本实际需要的大小
        let textBounds = attributedText.boundingRect(
            with: CGSize(width: imageSize.width * 0.8, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        // 确保水印区域足够大以容纳所有文本
        let watermarkHeight = max(imageSize.height * 0.25, textBounds.height + (imageSize.height * 0.05))
        let watermarkWidth = max(imageSize.width * 0.7, textBounds.width + (imageSize.width * 0.05))
        
        // 计算文本绘制区域
        let padding = imageSize.width * 0.03
        let textRect = CGRect(
            x: imageSize.width - watermarkWidth + padding,
            y: imageSize.height - watermarkHeight + padding,
            width: watermarkWidth - (padding * 2),
            height: watermarkHeight - (padding * 2)
        )
        
        // 绘制文字
        attributedText.draw(in: textRect)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    public init(photo: WorkPhoto) {
        self.photo = photo
        // Pre-decode image data on initialization
        let imageData = photo.imageData
        let options = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ] as CFDictionary
        
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
            self._cachedImage = State(initialValue: UIImage(cgImage: cgImage))
        }
    }
    
    private var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geometry in
                if let uiImage = UIImage(data: photo.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .scaleEffect(currentScale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { scale in
                                        currentScale = finalScale * scale
                                    }
                                    .onEnded { scale in
                                        finalScale = currentScale
                                        if finalScale < 0.5 {
                                            withAnimation {
                                                currentScale = 0.5
                                                finalScale = 0.5
                                                offset = .zero
                                                finalOffset = .zero
                                            }
                                        } else if finalScale > 3.0 {
                                            withAnimation {
                                                currentScale = 3.0
                                                finalScale = 3.0
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        let newOffset = CGSize(
                                            width: finalOffset.width + value.translation.width,
                                            height: finalOffset.height + value.translation.height
                                        )
                                        let maxOffset = (currentScale - 1) * geometry.size.width / 2
                                        offset = CGSize(
                                            width: max(-maxOffset, min(maxOffset, newOffset.width)),
                                            height: max(-maxOffset, min(maxOffset, newOffset.height))
                                        )
                                    }
                                    .onEnded { value in
                                        finalOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if currentScale > 1.0 {
                                    currentScale = 1.0
                                    finalScale = 1.0
                                    offset = .zero
                                    finalOffset = .zero
                                } else {
                                    currentScale = 2.0
                                    finalScale = 2.0
                                }
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                }
            }
            
            if showControls {
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding(.leading)
                        
                        Spacer()
                        
                        if let sharedPhoto = sharedPhoto {
                            ShareLink(
                                item: sharedPhoto,
                                preview: SharePreview(
                                    "\(photo.title).jpg",
                                    image: Image(uiImage: sharedPhoto.image)
                                )
                            ) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.body.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(.trailing)
                        }
                    }
                    .padding(.top, 48)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                
                VStack(spacing: 4) {

                            Text(photo.tag.rawValue)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(photo.tag.color.opacity(0.2))
                            .foregroundColor(photo.tag.color)
                            .clipShape(Capsule())

                    Text(dateFormatter.string(from: photo.timestamp))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if let location = photo.location {
                            Text(location)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                        }
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.5),
                            .black.opacity(0.2),
                            .clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBar(hidden: true)
        .enableInjection()
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif
} 