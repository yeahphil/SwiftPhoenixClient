//
//  CodableMessage.swift
//  SwiftPhoenixClient
//
//  Created by Phillip Kast on 1/10/25.
//  Copyright © 2025 SwiftPhoenixClient. All rights reserved.
//

import Foundation

public struct CodableMessage<T: Decodable>: Decodable {
    public let joinRef: String?
    public let ref: String?
    public let topic: String
    public let event: String
    public let payload: T
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        joinRef = try? container.decode(String?.self)
        ref = try? container.decode(String?.self)
        topic = try container.decode(String.self)
        event = try container.decode(String.self)
        payload = try container.decode(T.self)
    }
}
