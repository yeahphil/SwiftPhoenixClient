//
//  PayloadEncoder.swift
//  SwiftPhoenixClient
//
//  Created by Daniel Rees on 10/19/24.
//  Copyright © 2024 SwiftPhoenixClient. All rights reserved.
//

import Foundation

///
/// Provides methods for encoding Encodable and [String: Any]
/// payloads into an outbound message.
///
public protocol PayloadEncoder {
    func encode(any jsonObject: Any) throws -> Data

    func encode(_ encodable: Encodable) throws -> Data
}

public class PhoenixPayloadEncoder: PayloadEncoder {
    public func encode(any jsonObject: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject)
    }
    
    public func encode(_ encodable: any Encodable) throws -> Data {
        return try JSONEncoder().encode(encodable)
    }
    
}
