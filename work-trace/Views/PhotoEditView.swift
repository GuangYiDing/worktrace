import SwiftData
import SwiftUI

struct PhotoEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let photo: WorkPhoto

    @State private var customTitle: String
    @State private var selectedTag: WorkTag

    init(photo: WorkPhoto) {
        self.photo = photo
        // Initialize state variables
        _selectedTag = State(initialValue: photo.tag)
        _customTitle = State(initialValue: photo.customTitle ?? photo.title)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("记录信息")) {
                    HStack {
                        Text("标题")
                        TextField("标题", text: $customTitle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Picker("标签", selection: $selectedTag) {
                        if photo.fileType == .audio {
                            Text(WorkTag.audio.rawValue).tag(WorkTag.audio)
                        } else {
                            ForEach([WorkTag.checkIn, .checkOut, .overtime, .other], id: \.self) { tag in
                                Text(tag.rawValue).tag(tag)
                            }
                        }
                    }
                    .disabled(photo.fileType == .audio) // 如果是音频文件，禁用标签选择
                }

                Section {
                    Button("保存") {
                        saveChanges()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveChanges() {
        let oldTag = photo.tag
        photo.tag = selectedTag

        // If tag changed, reset the customTitle to let the default title show
        if oldTag != selectedTag {
            photo.customTitle = nil
            // Update the customTitle state if we're keeping the view open
            customTitle = photo.title
        } else if customTitle != photo.title {
            // Only save customTitle if it's different from the default title
            photo.customTitle = customTitle
        } else {
            photo.customTitle = nil
        }

        try? modelContext.save()
    }
}

#if DEBUG
    struct PhotoEditView_Previews: PreviewProvider {
        static var previews: some View {
            let photo = WorkPhoto(
                imageData: Data(),
                timestamp: Date(),
                location: "测试位置",
                companyName: "测试公司",
                tag: .other
            )
            return PhotoEditView(photo: photo)
        }
    }
#endif
