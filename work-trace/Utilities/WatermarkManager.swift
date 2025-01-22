import UIKit

class WatermarkManager {
    static let shared = WatermarkManager()
    
     func addWatermark(to image: UIImage, text: String) -> UIImage? {
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
} 