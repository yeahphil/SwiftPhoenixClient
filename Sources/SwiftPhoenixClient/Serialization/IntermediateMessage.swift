//
//  IntermediateDeserializedMessage.swift
//  SwiftPhoenixClient
//
//  Created by Daniel Rees on 9/13/24.
//  Copyright © 2024 SwiftPhoenixClient. All rights reserved.
//

///
/// Represents a string message received from the Server that has been deserialized
/// from the format
///
///     "[join_ref, ref, topic, event, payload]"
///
/// This is an intermediate representation, intended to be further converted into a `Message`
/// by the `Serializer` before being passed into the rest of the client.
///
struct IntermediateMessage {
    let joinRef: String?
    let ref: String?
    let topic: String
    let event: String
    let payload: Any
    
    init(joinRef: String?, ref: String?, topic: String, event: String, payload: [String: Any]) {
        self.joinRef = joinRef
        self.ref = ref
        self.topic = topic
        self.event = event
        self.payload = payload
    }
    
    /// Init from an array of `Any`. Expects "[join_ref, ref, topic, event, payload]"
    /// Suitable for passing JSONSerialization output to.
    init(_ array: [Any]) throws {
        joinRef = array[0] as? String
        ref = array[1] as? String
        guard let topic = array[2] as? String else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Expected String for topic, found \(type(of: array[2])): \(array[2])"
                )
            )
        }
        guard let event = array[3] as? String else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Expected String for event, found \(type(of: array[3])): \(array[3])"
                )
            )
        }
        
        let payload = array[4]
        
        self.topic = topic
        self.event = event
        self.payload = payload
    }
    
    func toJSONObject() -> [Any] {
        [joinRef as Any, ref as Any, topic, event, payload]
    }
}
