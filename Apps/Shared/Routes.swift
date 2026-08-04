import Foundation
import VocabKit

/// Navigation destinations shared by both frontends — identical page zoning.
enum Route: Hashable {
    case wordList(WordList)
    case wordDetail(word: String, context: [String])
    case settings
    case importWords
}
