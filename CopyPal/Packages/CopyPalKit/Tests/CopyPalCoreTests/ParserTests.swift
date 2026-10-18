import Foundation
import Testing
@testable import CopyPalCore

struct ColorParserTests {
    @Test(arguments: [
        ("#FF8800", "#FF8800"),
        ("#f80", "#FF8800"),
        ("  #ff8800 ", "#FF8800"),
        ("#FF880080", "#FF880080"),
        ("#F808", "#FF880088"),
        ("rgb(255,136,0)", "#FF8800"),
        ("rgb(255, 136, 0)", "#FF8800"),
        ("RGB(255 136 0)", "#FF8800"),
        ("rgba(255, 136, 0, 0.5)", "#FF880080"),
        ("rgb(100%, 0%, 0%)", "#FF0000"),
        ("rgb(255 136 0 / 50%)", "#FF880080"),
        ("hsl(32, 100%, 50%)", "#FF8800"),
        ("hsl(0deg 100% 50%)", "#FF0000"),
        ("hsla(120, 100%, 25%, 1)", "#008000"),
        ("hsl(0, 0%, 50%)", "#808080"),
    ])
    func recognizes(input: String, hex: String) {
        #expect(ColorParser.parse(input)?.hex == hex)
    }

    @Test(arguments: [
        "", "#", "#GG0000", "#12345", "FF8800", "rgb(256, 0, 0)", "rgb(1, 2)", "rgb(1,2,3,4,5)",
        "hsl(10, 50, 50)", "hsl(10, 150%, 50%)", "rgba(0,0,0,2)", "Farbe #FF8800", "red", "#FF8800 und mehr",
    ])
    func rejects(input: String) {
        #expect(ColorParser.parse(input) == nil)
    }
}

struct LinkParserTests {
    @Test func splitsHostAndPath() throws {
        let link = try #require(LinkParser.parse("https://github.com/Luio111/Test-1/pull/2"))
        #expect(link.host == "github.com")
        #expect(link.path == "/Luio111/Test-1/pull/2")
    }

    @Test func dropsWWWAndRootPath() throws {
        let link = try #require(LinkParser.parse("http://www.Example.com/"))
        #expect(link.host == "example.com")
        #expect(link.path == "")
    }

    @Test func decodesPath() throws {
        #expect(LinkParser.parse("https://example.com/a%20b")?.path == "/a b")
    }

    @Test(arguments: [
        "example.com", "ftp://example.com", "https://", "hallo https://example.com", "https://example.com mehr",
        "mailto:a@b.de", "https://nohost", "",
    ])
    func rejects(input: String) {
        #expect(LinkParser.parse(input) == nil)
    }
}

struct TextFoldingTests {
    @Test func firstLineSkipsEmptyLines() {
        #expect(TextFolding.firstLine(of: "\n\n   \n  Hallo  \nWelt") == "Hallo")
        #expect(TextFolding.firstLine(of: "") == "")
    }

    @Test func lineCount() {
        #expect(TextFolding.lineCount(of: "a") == 1)
        #expect(TextFolding.lineCount(of: "a\nb\nc") == 3)
        #expect(TextFolding.lineCount(of: "") == 1)
    }
}

struct LinkCleanerTests {
    @Test func removesTrackingParameters() {
        #expect(LinkCleaner.clean("https://example.com/a?utm_source=x&utm_medium=y&id=7") == "https://example.com/a?id=7")
        #expect(LinkCleaner.clean("https://shop.example.com/p?fbclid=abc") == "https://shop.example.com/p")
        #expect(LinkCleaner.clean("https://example.com/?gclid=1&q=caf%C3%A9") == "https://example.com/?q=caf%C3%A9")
    }

    @Test func keepsFragmentAndOtherParameters() {
        #expect(LinkCleaner.clean("https://example.com/doc?page=2&UTM_Campaign=z#section") == "https://example.com/doc?page=2#section")
    }

    @Test func untouchedWhenNothingToRemove() {
        #expect(LinkCleaner.clean("https://example.com/a?id=7") == nil)
        #expect(LinkCleaner.clean("https://example.com/a") == nil)
    }

    @Test func onlySingleLinks() {
        #expect(LinkCleaner.clean("Siehe https://example.com/?utm_source=x") == nil)
        #expect(LinkCleaner.clean("ftp://example.com/?utm_source=x") == nil)
        #expect(LinkCleaner.clean("  https://example.com/?utm_source=x \n") == "https://example.com/")
    }
}
