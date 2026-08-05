import AppKit

extension EditorViewController {
    private func moveCursor(to location: Int) {
        let length = (textView.string as NSString).length
        let range = NSRange(location: min(max(0, location), length), length: 0)
        setSelections([range], primaryRange: range)
        textView.scrollRangeToVisible(range)
    }

    func moveToDocumentStart() { moveCursor(to: 0) }
    func moveToDocumentEnd() { moveCursor(to: (textView.string as NSString).length) }

    func moveToScreenStart() {
        moveCursor(to: visibleTextRange().location)
    }

    func moveToScreenEnd() {
        moveCursor(to: NSMaxRange(visibleTextRange()))
    }

    func moveToWordStart() {
        let length = (textView.string as NSString).length
        let caret = min(selectionSet.primaryRange.location, length)
        let location = caret > 0 ? caret - 1 : caret
        let range = textView.selectionRange(
            forProposedRange: NSRange(location: location, length: 0), granularity: .selectByWord)
        moveCursor(to: range.location)
    }

    func moveToWordEnd() {
        let location = selectionSet.primaryRange.location
        let range = textView.selectionRange(
            forProposedRange: NSRange(location: location, length: 0), granularity: .selectByWord)
        moveCursor(to: NSMaxRange(range))
    }

    func moveWordRightSalnen() {
        let text = textView.string as NSString
        var location = min(selectionSet.primaryRange.location, text.length)
        let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if location < text.length, let scalar = UnicodeScalar(text.character(at: location)),
           !wordCharacters.contains(scalar) {
            while location < text.length,
                  let value = UnicodeScalar(text.character(at: location)),
                  !wordCharacters.contains(value) { location += 1 }
        }
        while location < text.length,
              let scalar = UnicodeScalar(text.character(at: location)),
              wordCharacters.contains(scalar) { location += 1 }
        moveCursor(to: location)
    }

    func moveToLineStart() {
        guard let layout = textView.layoutManager else { moveToLogicalLineStart(); return }
        let length = (textView.string as NSString).length
        guard length > 0 else { return }
        let character = min(selectionSet.primaryRange.location, length - 1)
        let glyph = layout.glyphIndexForCharacter(at: character)
        var fragment = NSRange()
        _ = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragment)
        moveCursor(to: layout.characterIndexForGlyph(at: fragment.location))
    }

    func moveToLineEnd() {
        guard let layout = textView.layoutManager else { moveToLogicalLineEnd(); return }
        let length = (textView.string as NSString).length
        guard length > 0 else { return }
        let character = min(selectionSet.primaryRange.location, length - 1)
        let glyph = layout.glyphIndexForCharacter(at: character)
        var fragment = NSRange()
        _ = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragment)
        let characters = layout.characterRange(forGlyphRange: fragment, actualGlyphRange: nil)
        let end = visualContentEnd(for: characters)
        moveCursor(to: max(characters.location, end - 1))
    }

    func moveToLineEndAfterCharacter() {
        guard let layout = textView.layoutManager else { moveToLogicalLineEnd(); return }
        let length = (textView.string as NSString).length
        guard length > 0 else { return }
        let glyph = layout.glyphIndexForCharacter(at: min(selectionSet.primaryRange.location, length - 1))
        var fragment = NSRange()
        _ = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragment)
        let characters = layout.characterRange(forGlyphRange: fragment, actualGlyphRange: nil)
        moveCursor(to: visualContentEnd(for: characters))
    }

    func moveToLogicalLineStart() {
        let text = textView.string as NSString
        moveCursor(to: text.lineRange(for: NSRange(
            location: min(selectionSet.primaryRange.location, text.length), length: 0)).location)
    }

    func moveToLogicalLineEnd() {
        let text = textView.string as NSString
        let line = text.lineRange(for: NSRange(
            location: min(selectionSet.primaryRange.location, text.length), length: 0))
        var end = NSMaxRange(line)
        while end > line.location,
              let scalar = UnicodeScalar(text.character(at: end - 1)),
              CharacterSet.newlines.contains(scalar) { end -= 1 }
        moveCursor(to: end)
    }

    func movePage(forward: Bool) {
        if forward { textView.pageDown(nil) } else { textView.pageUp(nil) }
    }

    func moveHalfPage(forward: Bool) {
        let visible = visibleTextRange()
        let delta = max(1, visible.length / 2)
        let current = selectionSet.primaryRange.location
        moveCursor(to: current + (forward ? delta : -delta))
    }

    func scrollEditor(forward: Bool, preserveCursor: Bool) {
        guard let scroll = textView.enclosingScrollView else { return }
        let amount = max(12, textView.font?.pointSize ?? 12)
        if !preserveCursor {
            if forward { textView.moveDown(nil) } else { textView.moveUp(nil) }
        }
        let maximum = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
        let y = min(maximum, max(0, scroll.contentView.bounds.origin.y + (forward ? amount : -amount)))
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func moveToAdjacentTab(forward: Bool) {
        let text = textView.string as NSString
        let current = min(selectionSet.primaryRange.location, text.length)
        let line = text.lineRange(for: NSRange(location: current, length: 0))
        let tabWidth = max(1, document?.fileTypeProfile?.settings.tabWidth ?? appliedPreferences.tabWidth)
        let currentColumn = lineIndex.displayColumn(
            atUTF16Offset: current, in: textView.string, tabWidth: tabWidth)
        let targetColumn = forward
            ? ((currentColumn / tabWidth) + 1) * tabWidth
            : max(0, ((max(0, currentColumn - 1)) / tabWidth) * tabWidth)
        var candidate = line.location
        while candidate < NSMaxRange(line) {
            let column = lineIndex.displayColumn(
                atUTF16Offset: candidate, in: textView.string, tabWidth: tabWidth)
            if column >= targetColumn { break }
            candidate = NSMaxRange(text.rangeOfComposedCharacterSequence(at: candidate))
        }
        moveCursor(to: candidate)
    }

    func moveToMatchingBracket() {
        let text = textView.string as NSString
        guard text.length > 0 else { return }
        var location = min(selectionSet.primaryRange.location, text.length - 1)
        let pairs: [unichar: (unichar, Int)] = [
            40: (41, 1), 91: (93, 1), 123: (125, 1),
            41: (40, -1), 93: (91, -1), 125: (123, -1),
        ]
        if pairs[text.character(at: location)] == nil, location > 0 { location -= 1 }
        guard let (target, direction) = pairs[text.character(at: location)] else { return }
        let source = text.character(at: location)
        var depth = 1, cursor = location + direction
        while cursor >= 0 && cursor < text.length {
            let value = text.character(at: cursor)
            if value == source { depth += 1 }
            else if value == target {
                depth -= 1
                if depth == 0 { moveCursor(to: cursor); return }
            }
            cursor += direction
        }
    }

    func moveToBrace(opening: Bool) {
        let text = textView.string as NSString
        let current = min(selectionSet.primaryRange.location, text.length)
        let range = opening
            ? NSRange(location: 0, length: current)
            : NSRange(location: current, length: text.length - current)
        let found = text.range(of: opening ? "{" : "}", options: opening ? .backwards : [], range: range)
        if found.location != NSNotFound { moveCursor(to: found.location) }
    }

    func moveToMatchingTag() {
        let text = textView.string as NSString
        let current = min(selectionSet.primaryRange.location, text.length)
        let full = NSRange(location: 0, length: text.length)
        guard let regex = try? NSRegularExpression(pattern: #"</?([A-Za-z][\w:-]*)\b[^>]*>"#) else { return }
        let tags = regex.matches(in: text as String, range: full)
        guard let index = tags.lastIndex(where: { $0.range.location <= current }),
              tags[index].numberOfRanges > 1 else { return }
        let name = text.substring(with: tags[index].range(at: 1)).lowercased()
        let token = text.substring(with: tags[index].range)
        guard !token.hasSuffix("/>") else { return }
        let isClosing = token.hasPrefix("</")
        let candidates = isClosing
            ? Array(tags[..<index].reversed())
            : Array(tags[(index + 1)...])
        var depth = 1
        for match in candidates where match.numberOfRanges > 1 {
            guard text.substring(with: match.range(at: 1)).lowercased() == name else { continue }
            let candidate = text.substring(with: match.range)
            if candidate.hasSuffix("/>") { continue }
            let closes = candidate.hasPrefix("</")
            if closes == isClosing { depth += 1 } else { depth -= 1 }
            if depth == 0 { moveCursor(to: match.range.location); return }
        }
    }

    func moveToLastEditMark() {
        guard let offset = document?.editMarks.lastRecordedOffset else { return }
        moveCursor(to: offset)
    }

    func moveToPreviousCursorPosition() {
        guard let previous = cursorHistory.popLast() else { return }
        isRestoringCursorHistory = true
        moveCursor(to: previous)
        isRestoringCursorHistory = false
    }

    private func visibleTextRange() -> NSRange {
        guard let layout = textView.layoutManager, let container = textView.textContainer else {
            return NSRange(location: 0, length: (textView.string as NSString).length)
        }
        let glyphs = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        return layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    }

    private func visualContentEnd(for range: NSRange) -> Int {
        let text = textView.string as NSString
        var end = min(NSMaxRange(range), text.length)
        while end > range.location,
              let scalar = UnicodeScalar(text.character(at: end - 1)),
              CharacterSet.newlines.contains(scalar) { end -= 1 }
        return end
    }
}
