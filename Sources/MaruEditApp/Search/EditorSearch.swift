import AppKit
import MaruEditCore

/// What a find/replace operation did, in the terms the Find Bar displays:
/// how many matches exist, which one is selected now, and whether the
/// pattern itself was rejected.
struct FindOutcome: Equatable {
    var totalMatches: Int = 0
    /// 1-based position of the currently selected match, or `nil` when the
    /// selection isn't on a match (nothing found, or the caret moved).
    var currentIndex: Int?
    /// Set only when the pattern could not be compiled; the Find Bar shows
    /// this instead of a count and keeps the user's input intact.
    var errorMessage: String?
    var replacementCount: Int = 0

    static let empty = FindOutcome()

    static func failure(_ message: String) -> FindOutcome {
        FindOutcome(errorMessage: message)
    }
}

enum SearchDirection {
    case next
    case previous
    /// Re-runs from the position the Find Bar was opened at rather than
    /// from the current selection, so a match found on keystroke N doesn't
    /// become the starting point for keystroke N+1 and walk the document
    /// forward as the user types.
    case incremental
}

/// Applies a `SearchQuery` to this editor's text view. All matching goes
/// through `SearchEngine` (ROADMAP.md M3-01/M3-02) — this file only
/// translates between "a match set" and "what the text view shows".
extension EditorViewController {

    private func scoped(_ query: SearchQuery) -> SearchQuery {
        guard let scope = searchScopeSelection, scope.length > 0 else { return query }
        var result = query
        result.scope = .selection(scope)
        return result
    }

    /// Match count and current position without changing the selection.
    func matchStatus(for query: SearchQuery) -> FindOutcome {
        let text = textView.string
        do {
            let matches = try SearchEngine.matches(for: scoped(query), in: text)
            return FindOutcome(
                totalMatches: matches.count,
                currentIndex: indexOfSelectedMatch(in: matches)
            )
        } catch let error as SearchError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func find(_ query: SearchQuery, direction: SearchDirection) -> FindOutcome {
        let text = textView.string
        let selection = textView.selectedRange()
        do {
            let query = scoped(query)
            let matches = try SearchEngine.matches(for: scoped(query), in: text)
            guard !matches.isEmpty else { return .empty }

            let target: SearchMatch?
            switch direction {
            case .next:
                target = try SearchEngine.nextMatch(for: query, in: text, from: NSMaxRange(selection))
            case .previous:
                target = try SearchEngine.previousMatch(for: query, in: text, from: selection.location)
            case .incremental:
                let anchor = incrementalSearchAnchor ?? selection.location
                target = try SearchEngine.nextMatch(for: query, in: text, from: anchor)
            }

            guard let match = target else {
                return FindOutcome(totalMatches: matches.count, currentIndex: nil)
            }
            select(match.range)
            return FindOutcome(
                totalMatches: matches.count,
                currentIndex: matches.firstIndex { $0.range == match.range }.map { $0 + 1 }
            )
        } catch let error as SearchError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Selects every match at once. Shared by the Find Bar's Select All and
    /// (from M4-02) the multi-cursor "Select All Occurrences" command, so
    /// both produce exactly the same set of ranges.
    @discardableResult
    func selectAllMatches(for query: SearchQuery) -> FindOutcome {
        do {
            let matches = try SearchEngine.matches(for: scoped(query), in: textView.string)
            guard !matches.isEmpty else { return .empty }
            let ranges = matches.map { NSValue(range: $0.range) }
            textView.setSelectedRanges(ranges, affinity: .downstream, stillSelecting: false)
            textView.scrollRangeToVisible(matches[0].range)
            return FindOutcome(totalMatches: matches.count, currentIndex: 1)
        } catch let error as SearchError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Replace (M3-03)

    /// Replaces the current selection when it is exactly a match, then
    /// moves to the next one. When the selection is not a match this only
    /// finds — the same "find first, then replace" behavior as the system
    /// find bar, so Replace never edits text the user cannot see selected.
    func replaceCurrent(_ query: SearchQuery) -> FindOutcome {
        let text = textView.string
        let selection = textView.selectedRange()
        do {
            let matches = try SearchEngine.matches(for: scoped(query), in: text)
            guard let current = matches.first(where: { $0.range == selection }) else {
                return find(query, direction: .next)
            }
            let replacement = SearchEngine.replacement(for: current, in: text, query: query)
            guard textView.shouldChangeText(in: current.range, replacementString: replacement) else {
                return matchStatus(for: query)
            }
            textView.textStorage?.replaceCharacters(in: current.range, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(
                location: current.range.location,
                length: (replacement as NSString).length
            ))

            var outcome = find(query, direction: .next)
            outcome.replacementCount = 1
            return outcome
        } catch let error as SearchError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Replaces every match in one edit, and therefore in one Undo step.
    ///
    /// Only the span from the first to the last match is rewritten, so
    /// unaffected text (and its highlighting) is left alone even in a large
    /// document.
    func replaceAll(_ query: SearchQuery) -> FindOutcome {
        var scoped = query
        // A selection that existed *before* the Find Bar opened means
        // "replace inside this"; the selection at the moment Replace All
        // is pressed is usually just the current match, which would make
        // Replace All silently replace exactly one occurrence.
        if let scope = searchScopeSelection, scope.length > 0 {
            scoped.scope = .selection(scope)
        }

        let text = textView.string
        do {
            let matches = try SearchEngine.matches(for: scoped, in: text)
            guard let first = matches.first, let last = matches.last else {
                return FindOutcome(totalMatches: 0)
            }
            let result = try SearchEngine.replacingAllMatches(of: scoped, in: text)
            guard let firstNew = result.replacedRanges.first,
                  let lastNew = result.replacedRanges.last else {
                return FindOutcome(totalMatches: 0)
            }

            let oldSpan = NSRange(
                location: first.range.location,
                length: NSMaxRange(last.range) - first.range.location
            )
            let newSpan = NSRange(
                location: firstNew.location,
                length: NSMaxRange(lastNew) - firstNew.location
            )
            let replacementText = (result.text as NSString).substring(with: newSpan)

            guard textView.shouldChangeText(in: oldSpan, replacementString: replacementText) else {
                return matchStatus(for: query)
            }
            textView.textStorage?.replaceCharacters(in: oldSpan, with: replacementText)
            textView.didChangeText()
            rehighlightEntireDocument()

            // Leave the caret after the last replacement rather than
            // selecting the whole rewritten span, which for a
            // document-wide replace would select nearly everything.
            textView.setSelectedRange(NSRange(location: NSMaxRange(lastNew), length: 0))
            searchScopeSelection = nil

            return FindOutcome(totalMatches: 0, replacementCount: result.replacementCount)
        } catch let error as SearchError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func select(_ range: NSRange) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    private func indexOfSelectedMatch(in matches: [SearchMatch]) -> Int? {
        let selection = textView.selectedRange()
        return matches.firstIndex { $0.range == selection }.map { $0 + 1 }
    }
}
