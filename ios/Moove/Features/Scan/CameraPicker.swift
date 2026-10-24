import SwiftUI
import UIKit

/// System camera for one item photo. Returns a JPEG scaled to at most 1600 px
/// on the long edge (keeps vision calls cheap, per #4).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data?) -> Void
        init(onImage: @escaping (Data?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage((info[.originalImage] as? UIImage).flatMap { Self.jpeg($0, maxEdge: 1600) })
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }

        static func jpeg(_ image: UIImage, maxEdge: CGFloat) -> Data? {
            let scale = min(1, maxEdge / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format)
                .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                .jpegData(compressionQuality: 0.75)
        }
    }
}
