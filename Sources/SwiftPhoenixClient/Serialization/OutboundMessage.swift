//
//  OutboundMessage.swift
//  SwiftPhoenixClient
//
//  Created by Daniel Rees on 10/28/24.
//  Copyright © 2024 SwiftPhoenixClient. All rights reserved.
//

///
/// Represents a `Message` that can be encoded to a String and pushed to the
/// Server with the format
///
///     "[join_ref, ref, topic, event, payload]"
///
struct OutboundMessage {
    let joinRef: String?
    let ref: String?
    let topic: String
    let event: String
    let payload: [String: Any]
    
    func toJSONObject() -> [Any] {
        [joinRef as Any, ref as Any, topic, event, payload]
    }
}
