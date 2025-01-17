//
//  PayloadDecoder.swift
//  SwiftPhoenixClient
//
//  Created by Daniel Rees on 10/28/24.
//  Copyright © 2024 SwiftPhoenixClient. All rights reserved.
//

import Foundation

///
/// Provides methods for decoding an inbound mesage into a Decodable
/// or a [String: Any].
///
public protocol PayloadDecoder {
    /// Decode `Any` from data
    /// The default implementation in `PhoenixPayloadDecoder` uses `JSONSerialization`.
    func decode(from data: Data) throws -> Any
    
    /// Decode a `Decodable` type from data
    /// The default implementation in `PhoenixPayloadDecoder` uses `JSONDecoder`.
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable
}

public class PhoenixPayloadDecoder: PayloadDecoder {
    public func decode(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }
    
    public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable {
        return try JSONDecoder().decode(type, from: data)
    }
}
