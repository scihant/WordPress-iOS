/// Extension on String containing the literals for the Giphy feature

 #warning("TODO: These strings need to be changed ")
extension String {
    // MARK: - Entry point: alert controller
    static var tenor: String {
        return NSLocalizedString("Tenor", comment: "One of the options when selecting More in the Post Editor's format bar")
    }

    // MARK: - Placeholder
    static var giphyPlaceholderTitle: String {
        return NSLocalizedString("Search to find GIFs to add to your Media Library!", comment: "Title for placeholder in Giphy picker")
    }

    static var giphyPlaceholderSubtitle: String {
        return NSLocalizedString("Powered by Giphy", comment: "Subtitle for placeholder in Giphy picker. `The company name 'Giphy' should always be written as it is.")
    }

    static var giphySearchNoResult: String {
        return NSLocalizedString("No media matching your search", comment: "Phrase to show when the user searches for GIFs but there are no result to show.")
    }

    static var giphySearchLoading: String {
        return NSLocalizedString("Loading GIFs...", comment: "Phrase to show when the user has searched for GIFs and they are being loaded.")
    }

}
