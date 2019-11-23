import MobileCoreServices
import WPMediaPicker

/// Prepares the alert controller that will be presented when tapping the "+" button in Media Library
final class MediaLibraryMediaPickingCoordinator {
    private let stockPhotos = StockPhotosPicker()
    private var tenor = TenorPicker()
    private let cameraCapture = CameraCaptureCoordinator()
    private let mediaLibrary = MediaLibraryPicker()

    init(delegate: StockPhotosPickerDelegate & WPMediaPickerViewControllerDelegate & TenorPickerDelegate) {
        stockPhotos.delegate = delegate
        mediaLibrary.delegate = delegate
        tenor.delegate = delegate
    }

    func present(context: MediaPickingContext) {
        let origin = context.origin
        let blog = context.blog
        let fromView = context.view
        let buttonItem = context.barButtonItem

        let menuAlert = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertController.Style.actionSheet)

        if let quotaUsageDescription = blog.quotaUsageDescription {
            menuAlert.title = quotaUsageDescription
        }

        if WPMediaCapturePresenter.isCaptureAvailable() {
            menuAlert.addAction(cameraAction(origin: origin, blog: blog))
        }

        menuAlert.addAction(photoLibraryAction(origin: origin, blog: blog))

        if blog.supports(.stockPhotos) {
            menuAlert.addAction(freePhotoAction(origin: origin, blog: blog))
        }

        menuAlert.addAction(tenorAction(origin: origin, blog: blog))
        menuAlert.addAction(otherAppsAction(origin: origin, blog: blog))
        menuAlert.addAction(cancelAction())

        menuAlert.popoverPresentationController?.sourceView = fromView
        menuAlert.popoverPresentationController?.sourceRect = fromView.bounds
        menuAlert.popoverPresentationController?.barButtonItem = buttonItem

        origin.present(menuAlert, animated: true)
    }

    private func cameraAction(origin: UIViewController, blog: Blog) -> UIAlertAction {
        return UIAlertAction(title: .takePhotoOrVideo, style: .default, handler: { [weak self] action in
            self?.showCameraCapture(origin: origin, blog: blog)
        })
    }

    private func photoLibraryAction(origin: UIViewController, blog: Blog) -> UIAlertAction {
        return UIAlertAction(title: .importFromPhotoLibrary, style: .default, handler: { [weak self] action in
            self?.showMediaPicker(origin: origin, blog: blog)
        })
    }

    private func freePhotoAction(origin: UIViewController, blog: Blog) -> UIAlertAction {
        return UIAlertAction(title: .freePhotosLibrary, style: .default, handler: { [weak self] action in
            self?.showStockPhotos(origin: origin, blog: blog)
        })
    }


    private func tenorAction(origin: UIViewController, blog: Blog) -> UIAlertAction {
        return UIAlertAction(title: .tenor, style: .default, handler: { [weak self] action in
            self?.showGiphy(origin: origin, blog: blog)
        })
    }

    private func otherAppsAction(origin: UIViewController & UIDocumentPickerDelegate, blog: Blog) -> UIAlertAction {
        return UIAlertAction(title: .files, style: .default, handler: { [weak self] action in
            self?.showDocumentPicker(origin: origin, blog: blog)
        })
    }

    private func cancelAction() -> UIAlertAction {
        return UIAlertAction(title: .cancelMoreOptions, style: .cancel, handler: nil)
    }

    private func showCameraCapture(origin: UIViewController, blog: Blog) {
        cameraCapture.presentMediaCapture(origin: origin, blog: blog)
    }

    private func showStockPhotos(origin: UIViewController, blog: Blog) {
        stockPhotos.presentPicker(origin: origin, blog: blog)
    }

    private func showGiphy(origin: UIViewController, blog: Blog) {
        let delegate = tenor.delegate

        // Create a new TenorPicker each time so we don't save state
        tenor = TenorPicker()
        tenor.delegate = delegate

        tenor.presentPicker(origin: origin, blog: blog)
    }

    private func showDocumentPicker(origin: UIViewController & UIDocumentPickerDelegate, blog: Blog) {
        let docTypes = blog.allowedTypeIdentifiers
        let docPicker = UIDocumentPickerViewController(documentTypes: docTypes, in: .import)
        docPicker.delegate = origin
        docPicker.allowsMultipleSelection = true
        WPStyleGuide.configureDocumentPickerNavBarAppearance()
        origin.present(docPicker, animated: true)
    }

    private func showMediaPicker(origin: UIViewController, blog: Blog) {
        mediaLibrary.presentPicker(origin: origin, blog: blog)
    }
}
