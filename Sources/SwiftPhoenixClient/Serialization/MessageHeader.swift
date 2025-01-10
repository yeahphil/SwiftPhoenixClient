//
//  MessageHeader.swift
//  SwiftPhoenixClient
//
//  Created by Phillip Kast on 1/10/25.
//  Copyright © 2025 SwiftPhoenixClient. All rights reserved.
//

import Foundation

/// All the fields in a Message except the payload
/// Inbound messages can't be handled without parsing these, but the payload is potentially large, and the expected `Decodable` type can't be determined without the header fields
struct MessageHeader: Codable {
    let joinRef: String?
    let ref: String?
    let topic: String
    let event: String
    let status: String?
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        joinRef = try? container.decode(String?.self)
        ref = try? container.decode(String?.self)
        topic = try container.decode(String.self)
        event = try container.decode(String.self)
        
        if event == ChannelEvent.reply {
            let wrapper = try container.decode(ResponseWrapper.self)
            status = wrapper.status
        } else {
            status = nil
        }
    }
    
    struct ResponseWrapper: Codable {
        let status: String
    }
}
