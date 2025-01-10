////
////  URLSessionTransportSpec.swift
////  SwiftPhoenixClientTests
////
////  Created by Daniel Rees on 4/1/21.
////  Copyright © 2021 SwiftPhoenixClient. All rights reserved.
////


import Testing
@testable import SwiftPhoenixClient

struct URLSessionTransportTest {
    
    @Test func init_replaces_http_with_ws_protocols() {
        #expect(URLSessionTransport(url: URL(string:"http://localhost:4000/socket/websocket")!).url.absoluteString == "ws://localhost:4000/socket/websocket")
        #expect(URLSessionTransport(url: URL(string:"https://localhost:4000/socket/websocket")!).url.absoluteString == "wss://localhost:4000/socket/websocket")
        #expect(URLSessionTransport(url: URL(string:"ws://localhost:4000/socket/websocket")!).url.absoluteString == "ws://localhost:4000/socket/websocket")
        #expect(URLSessionTransport(url: URL(string:"wss://localhost:4000/socket/websocket")!).url.absoluteString == "wss://localhost:4000/socket/websocket")
    }
    
    @Test func init_accepts_an_override_for_configuration() {
        let configuration = URLSessionConfiguration.default
        #expect(URLSessionTransport(url: URL(string:"wss://localhost:4000")!, configuration: configuration).configuration == configuration)
    }
}
