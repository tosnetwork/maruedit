#!/usr/bin/env swift
import AppKit
import CoreText
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate-help-pdf.swift INPUT.md OUTPUT.pdf\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let source = try String(contentsOf: input, encoding: .utf8)
let body = NSMutableAttributedString()
let regular = NSFont.systemFont(ofSize: 11.5)
let mono = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
let color = NSColor(calibratedWhite: 0.12, alpha: 1)

func append(_ text: String, font: NSFont, spacingBefore: CGFloat = 0,
            spacingAfter: CGFloat = 6, indent: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacingBefore = spacingBefore
    paragraph.paragraphSpacing = spacingAfter
    paragraph.lineSpacing = 2
    paragraph.firstLineHeadIndent = indent
    paragraph.headIndent = indent
    body.append(NSAttributedString(string: text + "\n", attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
    ]))
}

var paragraph: [String] = []
func flushParagraph() {
    guard !paragraph.isEmpty else { return }
    append(paragraph.joined(separator: " "), font: regular)
    paragraph.removeAll()
}

for rawLine in source.components(separatedBy: .newlines) {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    if line.isEmpty { flushParagraph(); continue }
    if line.hasPrefix("### ") {
        flushParagraph(); append(String(line.dropFirst(4)), font: .boldSystemFont(ofSize: 13), spacingBefore: 8)
    } else if line.hasPrefix("## ") {
        flushParagraph(); append(String(line.dropFirst(3)), font: .boldSystemFont(ofSize: 17), spacingBefore: 14, spacingAfter: 8)
    } else if line.hasPrefix("# ") {
        flushParagraph(); append(String(line.dropFirst(2)), font: .boldSystemFont(ofSize: 28), spacingAfter: 14)
    } else if line.hasPrefix("- ") {
        flushParagraph(); append("• " + String(line.dropFirst(2)), font: regular, spacingAfter: 3, indent: 14)
    } else if line.hasPrefix("~/") {
        flushParagraph(); append(line, font: mono, spacingBefore: 3, spacingAfter: 8, indent: 14)
    } else {
        paragraph.append(line)
    }
}
flushParagraph()

var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
guard let consumer = CGDataConsumer(url: output as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    throw NSError(domain: "MaruEditHelp", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Unable to create PDF context"])
}

let framesetter = CTFramesetterCreateWithAttributedString(body)
let textRect = CGRect(x: 58, y: 58, width: 479, height: 726)
func drawLabel(_ string: String, at point: CGPoint, in context: CGContext) {
    let value = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: 8),
        .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
    ])
    context.textPosition = point
    CTLineDraw(CTLineCreateWithAttributedString(value), context)
}
var location = 0
var page = 1
while location < body.length {
    context.beginPDFPage(nil)
    context.saveGState()
    drawLabel("MaruEdit User Manual", at: CGPoint(x: 58, y: 817), in: context)
    drawLabel("\(page)", at: CGPoint(x: 500, y: 30), in: context)
    let path = CGPath(rect: textRect, transform: nil)
    let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: location, length: 0), path, nil)
    CTFrameDraw(frame, context)
    let visible = CTFrameGetVisibleStringRange(frame)
    context.restoreGState()
    context.endPDFPage()
    guard visible.length > 0 else { break }
    location += visible.length
    page += 1
}
context.closePDF()
