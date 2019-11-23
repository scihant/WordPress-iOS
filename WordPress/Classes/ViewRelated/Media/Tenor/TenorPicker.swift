import WPMediaPicker
import MobileCoreServices

protocol TenorPickerDelegate: AnyObject {
    func tenorPicker(_ picker: TenorPicker, didFinishPicking assets: [TenorMedia])
}

/// Presents the Tenor main interface
final class TenorPicker: NSObject {
    private lazy var dataSource: TenorDataSource = {
        return TenorDataSource(service: tenorService)
    }()

    private lazy var tenorService: TenorService = {
        return TenorService()
    }()

    /// Helps choosing the correct view controller for previewing a media asset
    ///
    private var mediaPreviewHelper: MediaPreviewHelper!

    weak var delegate: TenorPickerDelegate?
    private var blog: Blog?
    private var observerToken: NSObjectProtocol?

    private let searchHint = NoResultsViewController.controller()

    private var pickerOptions: WPMediaPickerOptions = {
        let options = WPMediaPickerOptions()
        options.showMostRecentFirst = true
        options.filter = [.all]
        options.allowCaptureOfMedia = false
        options.showSearchBar = true
        options.badgedUTTypes = [String(kUTTypeGIF)]
        options.preferredStatusBarStyle = .lightContent
        return options
    }()

    private lazy var picker: WPNavigationMediaPickerViewController = {
        let picker = WPNavigationMediaPickerViewController(options: pickerOptions)
        picker.delegate = self
        picker.startOnGroupSelector = false
        picker.showGroupSelector = false
        picker.dataSource = dataSource
        picker.cancelButtonTitle = .closePicker
        return picker
    }()

    func presentPicker(origin: UIViewController, blog: Blog) {
        NoResultsTenorConfiguration.configureAsIntro(searchHint)
        self.blog = blog

        origin.present(picker, animated: true) {
            self.picker.mediaPicker.searchBar?.becomeFirstResponder()
        }

        observeDataSource()
        trackAccess()
    }

    private func observeDataSource() {
        observerToken = dataSource.registerChangeObserverBlock { [weak self] (_, _, _, _, assets) in
            self?.updateHintView()
        }
        dataSource.onStartLoading = { [weak self] in
            NoResultsTenorConfiguration.configureAsLoading(self!.searchHint)
        }
        dataSource.onStopLoading = { [weak self] in
            self?.updateHintView()
        }
    }

    private func shouldShowNoResults() -> Bool {
        return dataSource.searchQuery.count > 0 && dataSource.numberOfAssets() == 0
    }

    private func updateHintView() {
        searchHint.removeFromView()
        if shouldShowNoResults() {
            NoResultsTenorConfiguration.configure(searchHint)
        } else {
            NoResultsTenorConfiguration.configureAsIntro(searchHint)
        }
    }

    deinit {
        if let token = observerToken {
            dataSource.unregisterChangeObserver(token)
        }
    }
}

extension TenorPicker: WPMediaPickerViewControllerDelegate {
    func mediaPickerController(_ picker: WPMediaPickerViewController, didFinishPicking assets: [WPMediaAsset]) {
        guard let assets = assets as? [TenorMedia] else {
            assertionFailure("assets should be of type `[TenorMedia]`")
            return
        }
        delegate?.tenorPicker(self, didFinishPicking: assets)
        picker.dismiss(animated: true)
        dataSource.clearSearch(notifyObservers: false)
        hideKeyboard(from: picker.searchBar)
    }

    func emptyViewController(forMediaPickerController picker: WPMediaPickerViewController) -> UIViewController? {
        return searchHint
    }

    func mediaPickerControllerDidEndLoadingData(_ picker: WPMediaPickerViewController) {
        if let searchBar = picker.searchBar {
            WPStyleGuide.configureSearchBar(searchBar)
        }
    }

    func mediaPickerControllerDidCancel(_ picker: WPMediaPickerViewController) {
        picker.dismiss(animated: true)
        dataSource.clearSearch(notifyObservers: false)
        hideKeyboard(from: picker.searchBar)
    }

    func mediaPickerController(_ picker: WPMediaPickerViewController, didSelect asset: WPMediaAsset) {
        hideKeyboard(from: picker.searchBar)
    }

    func mediaPickerController(_ picker: WPMediaPickerViewController, didDeselect asset: WPMediaAsset) {
        hideKeyboard(from: picker.searchBar)
    }

    func mediaPickerController(_ picker: WPMediaPickerViewController, previewViewControllerFor assets: [WPMediaAsset], selectedIndex selected: Int) -> UIViewController? {
        mediaPreviewHelper = MediaPreviewHelper(assets: assets)
        return mediaPreviewHelper.previewViewController(selectedIndex: selected)
    }

    private func hideKeyboard(from view: UIView?) {
        if let view = view, view.isFirstResponder {
            //Fix animation conflict between dismissing the keyboard and showing the accessory input view
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                view.resignFirstResponder()
            }
        }
    }
}

// MARK: - Tracks
extension TenorPicker {
    fileprivate func trackAccess() {
        #warning("TODO: Needs to be changed in WordpressShared")
        WPAnalytics.track(.giphyAccessed)
    }
}
