//
//  NotificationNames.swift
//  
//
//  Created by Vincent Kwok on 23/11/22.
//

import Foundation

public extension NSNotification.Name {
    static let ready = Self("dk-ready")

    static let messageCreate = Self("dk-msg-create")
    
    static let messageReactAdd = Self("dk-msg-react-add")
}
