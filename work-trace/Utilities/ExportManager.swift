import Foundation
import SwiftUI
import SwiftData
import ZIPFoundation

class ExportManager: ObservableObject {
    static let shared = ExportManager()
    
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var totalItems: Int = 0
    @Published var processedItems: Int = 0
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    func calculateTotalItems(modelContext: ModelContext, startDate: Date, endDate: Date) async {
        // Force a save of any pending changes
        try? modelContext.save()
        
        var descriptor = FetchDescriptor<Company>()
        descriptor.sortBy = [SortDescriptor(\Company.name)]
        
        guard let companies = try? modelContext.fetch(descriptor) else {
            await MainActor.run {
                totalItems = 0
            }
            return
        }
        
        var count = 0
        for company in companies {
            let photoDescriptor = FetchDescriptor<WorkPhoto>(
                sortBy: [SortDescriptor(\WorkPhoto.timestamp, order: .reverse)]
            )
            guard let photos = try? modelContext.fetch(photoDescriptor) else { continue }
            let companyPhotos = photos.filter { $0.companyName == company.name }
            count += companyPhotos.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }.count
        }
        
        await MainActor.run {
            totalItems = count
        }
    }
    
    func exportData(modelContext: ModelContext, startDate: Date, endDate: Date, exportType: String) async throws {
        await MainActor.run {
            isExporting = true
            exportProgress = 0
            processedItems = 0
        }
        
        // Force a save of any pending changes
        try? modelContext.save()
        
        var descriptor = FetchDescriptor<Company>()
        descriptor.sortBy = [SortDescriptor(\Company.name)]
        
        guard let companies = try? modelContext.fetch(descriptor) else {
            throw ExportError.fetchError
        }
        
        // Create a temporary directory to store the export
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = DateFormatter.localizedString(
            from: Date(), dateStyle: .short, timeStyle: .medium
        )
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: " ", with: "_")
        let exportDir = tempDir.appendingPathComponent("work-trace-export-\(UUID().uuidString)")
        let zipFile = tempDir.appendingPathComponent("work-trace-export-\(timestamp).zip")
        
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        
        for company in companies {
            let photoDescriptor = FetchDescriptor<WorkPhoto>(
                sortBy: [SortDescriptor(\WorkPhoto.timestamp, order: .reverse)]
            )
            
            guard let photos = try? modelContext.fetch(photoDescriptor) else { continue }
            
            let companyPhotos = photos.filter { $0.companyName == company.name }
            
            for photo in companyPhotos {
                if photo.timestamp >= startDate && photo.timestamp <= endDate {
                    if photo.fileType == .audio {
                        try await exportAudio(photo: photo, to: exportDir, exportType: exportType)
                    } else {
                        try await exportImage(photo: photo, company: company, to: exportDir, exportType: exportType)
                    }
                    
                    await MainActor.run {
                        processedItems += 1
                        exportProgress = Double(processedItems) / Double(totalItems)
                    }
                }
            }
        }
        
        if exportType == "压缩包📦" {
            try FileManager.default.zipItem(at: exportDir, to: zipFile)
            await shareFile(at: zipFile)
            
            // Clean up after 60 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                try? FileManager.default.removeItem(at: exportDir)
                try? FileManager.default.removeItem(at: zipFile)
            }
        } else {
            await shareFile(at: exportDir)
            
            // Clean up after 60 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                try? FileManager.default.removeItem(at: exportDir)
            }
        }
        
        await MainActor.run {
            isExporting = false
        }
    }
    
    private func exportAudio(photo: WorkPhoto, to directory: URL, exportType: String) async throws {
        if let audioData = photo.audioData {
            let calendar = Calendar.current
            let timestamp = photo.timestamp
            
            // Adjust timestamp for ZIP export by adding system timezone offset
            let adjustedTimestamp = exportType == "压缩包📦" ? timestamp.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT())) : timestamp
            
            let year = calendar.component(.year, from: adjustedTimestamp)
            let month = calendar.component(.month, from: adjustedTimestamp)
            
            // Create year and month folders
            let yearFolder = directory.appendingPathComponent("\(year)年")
            let monthFolder = yearFolder.appendingPathComponent(String(format: "%02d月", month))
            
            try FileManager.default.createDirectory(at: monthFolder, withIntermediateDirectories: true)
            
            let safeTitle = photo.title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            var audioFile = monthFolder.appendingPathComponent("\(safeTitle).m4a")
            try audioData.write(to: audioFile)
            
            // Set creation and modification dates with adjusted timestamp
            var resourceValues = URLResourceValues()
            resourceValues.creationDate = adjustedTimestamp
            resourceValues.contentModificationDate = adjustedTimestamp
            try audioFile.setResourceValues(resourceValues)
        }
    }
    
    private func exportImage(photo: WorkPhoto, company: Company, to directory: URL, exportType: String) async throws {
        if let image = UIImage(data: photo.imageData) {
            let calendar = Calendar.current
            let timestamp = photo.timestamp
            
            // Adjust timestamp for ZIP export by adding system timezone offset
            let adjustedTimestamp = exportType == "压缩包📦" ? timestamp.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT())) : timestamp
            
            let year = calendar.component(.year, from: adjustedTimestamp)
            let month = calendar.component(.month, from: adjustedTimestamp)
            
            // Create year and month folders
            let yearFolder = directory.appendingPathComponent("\(year)年")
            let monthFolder = yearFolder.appendingPathComponent(String(format: "%02d月", month))
            
            try FileManager.default.createDirectory(at: monthFolder, withIntermediateDirectories: true)
            
            let watermarkText = """
                公司：\(company.name)
                时间：\(dateFormatter.string(from: photo.timestamp))
                类型：\(photo.tag.rawValue)
                位置：\(photo.location ?? "未知位置")
                """
            
            if let watermarkedImage = WatermarkManager.shared.addWatermark(to: image, text: watermarkText) {
                let safeTitle = photo.title
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: "\\", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                var imageFile = monthFolder.appendingPathComponent("\(safeTitle).jpg")
                if let jpegData = watermarkedImage.jpegData(compressionQuality: 0.8) {
                    try jpegData.write(to: imageFile)
                    
                    // Set creation and modification dates with adjusted timestamp
                    var resourceValues = URLResourceValues()
                    resourceValues.creationDate = adjustedTimestamp
                    resourceValues.contentModificationDate = adjustedTimestamp
                    try imageFile.setResourceValues(resourceValues)
                }
            }
        }
    }
    
    private func shareFile(at url: URL) async {
        await MainActor.run {
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                rootVC.present(activityVC, animated: true)
            }
        }
    }
}

enum ExportError: Error {
    case fetchError
    case exportError
} 