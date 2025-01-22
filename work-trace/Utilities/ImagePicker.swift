import SwiftUI
import UIKit

extension UIImage {
    static func random() -> UIImage? {
        let urlString = String(
            format: "https://www.gravatar.com/avatar/%04x%04x%04x%04x?d=monsterid&s=480",
            arc4random(), arc4random(), arc4random(), arc4random()
        )
        guard let url = URL(string: urlString) else { return nil }
        guard let imageData = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: imageData)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    var autoDismiss: Bool = false

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        
        #if targetEnvironment(simulator)
        if sourceType == .camera {
            // 在模拟器中使用随机图片替代相机
            DispatchQueue.main.async {
                if let randomImage = UIImage.random() {
                    self.image = randomImage
                }
                picker.dismiss(animated: true)
            }
        }
        #endif
        
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.view.backgroundColor = .black
        if #available(iOS 11.0, *) {
            picker.view.subviews.first?.subviews.first?.backgroundColor = .black
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                 didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }

            if parent.autoDismiss {
                picker.dismiss(animated: true)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
} 