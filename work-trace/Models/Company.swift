import Foundation
import SwiftData
import SwiftUI

@Model
public final class Company {
    public var name: String
    @Relationship(deleteRule: .cascade) public var photos: [WorkPhoto]
    
    public init(name: String) {
        self.name = name
        self.photos = []
    }
}

public enum WorkTag: String, Codable {
    case checkIn = "上班打卡"
    case checkOut = "下班打卡"
    case overtime = "加班打卡"
    case audio = "录音文件"
    case other = "其他图片"
    
    public var color: Color {
        switch self {
        case .checkIn:
            return .blue
        case .checkOut:
            return .green
        case .overtime:
            return .orange
        case .audio:
            return .purple
        case .other:
            return .gray
        }
    }
}

public enum FileType: String, Codable {
    case image = "图片"
    case audio = "音频"
    case video = "视频"
    case file = "文件"
}

@Model
public final class WorkPhoto {
    public var imageData: Data
    public var audioData: Data?
    public var videoData: Data?
    public var fileData: Data?
    public var timestamp: Date
    public var location: String?
    public var companyName: String
    public var tag: WorkTag
    public var fileType: FileType
    public var customTitle: String?
    
    public var title: String {
        if let customTitle = customTitle {
            return customTitle
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        let timeString = formatter.string(from: timestamp)
        return "\(timeString)-\(tag.rawValue)"
    }
    
    public init(imageData: Data, timestamp: Date, location: String?, companyName: String, tag: WorkTag = .other, fileType: FileType = .image) {
        self.imageData = imageData
        self.timestamp = timestamp
        self.location = location
        self.companyName = companyName
        self.tag = tag
        self.fileType = fileType
        self.customTitle = nil
    }
    
    public init(audioData: Data, timestamp: Date, location: String?, companyName: String) {
        self.imageData = Data() // Empty data for placeholder
        self.audioData = audioData
        self.timestamp = timestamp
        self.location = location
        self.companyName = companyName
        self.tag = .audio
        self.fileType = .audio
        self.customTitle = nil
    }
} 
