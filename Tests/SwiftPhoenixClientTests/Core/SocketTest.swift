//
//  SocketTest.swift
//  SwiftPhoenixClientTests
//
//  Created by Daniel Rees on 10/28/24.
//  Copyright © 2024 SwiftPhoenixClient. All rights reserved.
//

import Testing
@testable import SwiftPhoenixClient

struct SocketTest {
    
    @Test func constructor_sets_defaults() async throws {
        let socket = Socket("wss://localhost:4000/socket")
        
        #expect(socket.channels.count == 0)
        #expect(socket.sendBuffer.count == 0)
        #expect(socket.ref == 0)
        #expect(socket.endPoint == "wss://localhost:4000/socket")
        #expect(socket.stateChangeCallbacks.open.isEmpty)
        #expect(socket.stateChangeCallbacks.close.isEmpty)
        #expect(socket.stateChangeCallbacks.error.isEmpty)
        #expect(socket.stateChangeCallbacks.message.isEmpty)
        #expect(socket.timeout == Defaults.timeoutInterval)
        #expect(socket.heartbeatInterval == Defaults.heartbeatInterval)
    }
    
//    @Test func constructor_supports_closure_or_literal_params() async throws {
//        let socket = Socket("wss://localhost:4000/socket", params: ["one": "two"])
//        
//        let socket = Socket("wss://localhost:4000/socket", paramsClosure: { ["three": "four"] } )
//    }
    
}
