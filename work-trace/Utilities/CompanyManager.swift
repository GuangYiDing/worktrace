import Foundation
import SwiftData

class CompanyManager: ObservableObject {
    static let shared = CompanyManager()
    
    @Published var isLoading = false
    
    func updateCompanyName(_ newName: String, modelContext: ModelContext) async throws {
        // Don't proceed if the name is empty
        if newName.isEmpty {
            throw CompanyError.emptyName
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Perform database operations in the background
        try await Task {
            let descriptor = FetchDescriptor<Company>()
            let companies = try modelContext.fetch(descriptor)
            
            if let existingCompany = companies.first {
                print("更新第一个公司名称: \(newName)")
                // 原 company name 的照片也要一同修改成新名字
                let photoDescriptor = FetchDescriptor<WorkPhoto>(
                    sortBy: [SortDescriptor(\WorkPhoto.timestamp, order: .reverse)]
                )
                
                if let photos = try? modelContext.fetch(photoDescriptor) {
                    // 处理照片
                    let companyPhotos = photos.filter { $0.companyName == existingCompany.name }
                    print(" 原公司照片 总数: \(companyPhotos.count)")
                    for photo in companyPhotos {
                        photo.companyName = newName
                        print(" 原公司照片 新公司名: \(photo.companyName)")
                    }
                } else {
                    print("没有找到照片")
                }
                
                // Update the name of the first company
                existingCompany.name = newName
                
                // If there are any other companies (which shouldn't happen), delete them
                // companies.dropFirst().forEach { modelContext.delete($0) }
            } else {
                // If no company exists yet, create one
                let newCompany = Company(name: newName)
                modelContext.insert(newCompany)
                print("创建新公司: \(newName)")
            }
            
            try modelContext.save()
        }.value
    }
}

enum CompanyError: Error {
    case emptyName
    case updateFailed
} 