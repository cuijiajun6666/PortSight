//
//  Item.swift
//  PortsightMac
//
//  Created by Chris Cui on 25/10/2026.
//

import Foundation
import SwiftData
import PortSightKit

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
