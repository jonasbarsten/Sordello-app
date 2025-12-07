//
//  Item.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
