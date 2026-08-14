//
//  Item.swift
//  PortSight
//
//  Created by Chris Cui on 28/4/2026.
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
