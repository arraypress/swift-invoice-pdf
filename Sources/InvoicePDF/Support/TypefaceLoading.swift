//
//  TypefaceLoading.swift
//  InvoicePDF
//
//  Created by David Sherlock on 2026.
//
//  Reading a brand's font files off the disk. This is IO, which is not
//  work a value type should be doing — the model names the files, and
//  whoever renders comes here to load them.
//

import Foundation
import TextPDF

/// Loads the family a TypefaceFiles names.
enum TypefaceLoading {

    static func family(from files: TypefaceFiles) throws -> FontFamily {
        var loaded = FontFamily(name: files.name.isEmpty ? "Brand" : files.name)

        func add(_ path: String?, _ weight: FontFamily.Weight, italic: Bool = false) throws {
            guard let path, !path.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            loaded.add(try EmbeddedFont.load(url), weight: weight, italic: italic)
        }

        try add(files.regular, .regular)
        try add(files.medium, .medium)
        try add(files.semibold, .semibold)
        try add(files.bold, .bold)
        try add(files.italic, .regular, italic: true)

        return loaded
    }
}
