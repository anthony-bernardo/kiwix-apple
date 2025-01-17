//
//  ArticleCell.swift
//  Kiwix
//
//  Created by Chris Li on 6/3/22.
//  Copyright © 2022 Chris Li. All rights reserved.
//

import SwiftUI

/// A rounded rect cell displaying preview of an article.
struct ArticleCell: View {
    @State var isHovering: Bool = false
    
    let title: String
    let snippet: NSAttributedString?
    let zimFile: ZimFile?
    let alwaysShowSnippet: Bool
    
    init(bookmark: Bookmark) {
        self.title = bookmark.title
        if let snippet = bookmark.snippet {
            self.snippet = NSAttributedString(string: snippet)
        } else {
            self.snippet = nil
        }
        self.zimFile = bookmark.zimFile
        self.alwaysShowSnippet = true
    }
    
    init(result: SearchResult, zimFile: ZimFile?) {
        self.title = result.title
        self.snippet = result.snippet
        self.zimFile = zimFile
        self.alwaysShowSnippet = false
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).fontWeight(.medium).lineLimit(1)
                Spacer().frame(height: 2)
                Group {
                    if let snippet = snippet {
                        Text(AttributedString(snippet)).lineLimit(4)
                    } else if alwaysShowSnippet {
                        Text("No snippet").foregroundColor(.secondary)
                    }
                }.font(.caption).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            Spacer()
            if let zimFile = zimFile, let category = Category(rawValue: zimFile.category) {
                Favicon(category: category, imageData: zimFile.faviconData, imageURL: zimFile.faviconURL)
                    .frame(height: 20)
            }
        }
        .foregroundColor(.primary)
        .padding(12)
        .modifier(CellBackground(isHovering: isHovering))
        .onHover { self.isHovering = $0 }
    }
}

struct ArticleCell_Previews: PreviewProvider {
    static let result: SearchResult = {
        let result = SearchResult(zimFileID: UUID(), path: "", title: "Article Title")!
        result.snippet = NSAttributedString(string:
            """
            Lorem ipsum dolor sit amet, consectetur adipiscing elit, \
            sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
            """
        )
        return result
    }()
    
    static var previews: some View {
        ArticleCell(result: ArticleCell_Previews.result, zimFile: nil)
            .frame(width: 500, height: 100)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
