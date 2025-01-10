//
//  SocketTest.swift
//  SwiftPhoenixClientTests
//
//  Created by Daniel Rees on 10/28/24.
//  Copyright © 2024 SwiftPhoenixClient. All rights reserved.
//

import Testing
@testable import SwiftPhoenixClient

@MainActor
@Suite("Socket tests") struct SocketConstructorTest {
    
    // MARK: -- constructor --
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
    
    @Test func constructor_supports_closure_or_literal_params() async throws {
        let literalSocket = Socket("wss://localhost:4000/socket", params: ["one": "two"])
        #expect(literalSocket.params?["one"] as? String == "two")
        
        var authToken = "abc123"
        let closureSocket = Socket("wss://localhost:4000/socket", params: { ["token": authToken] } )
        #expect(closureSocket.params?["token"] as? String == "abc123")
        
        authToken = "xyz987"
        #expect(closureSocket.params?["token"] as? String == "xyz987")
    }
    
    // MARK: -- websocketProtocol --
    @Test func websocketProtocol_returns_wss_when_given_https() async throws {
        let socket = Socket("https://example.com/")
        #expect(socket.websocketProtocol == "wss")
    }
    
    @Test func websocketProtocol_returns_wss_when_given_wss() async throws {
        let socket = Socket("wss://example.com/")
        #expect(socket.websocketProtocol == "wss")
    }
    
    @Test func websocketProtocol_returns_ws_when_given_http() async throws {
        let socket = Socket("http://example.com/")
        #expect(socket.websocketProtocol == "ws")
    }
    
    @Test func websocketProtocol_returns_ws_when_given_ws() async throws {
        let socket = Socket("ws://example.com/")
        #expect(socket.websocketProtocol == "ws")
    }
    
    @Test func websocketProtocol_returns_nil_if_there_is_no_schema() async throws {
        let socket = Socket("example.com/")
        #expect(socket.websocketProtocol == "ws")
    }
    
    // MARK: -- endPointUrl --
    @Test func endPointUrl_constructs_valid_url() async throws {
        // Full URL
        #expect(Socket("wss://example.com/websocket")
            .endPointUrl.absoluteString == "wss://example.com/websocket?vsn=2.0.0")
        
        // Appends `/websocket`
        #expect(Socket("https://example.com/chat")
            .endPointUrl.absoluteString == "wss://example.com/chat/websocket?vsn=2.0.0")
        
        // Appends `/websocket`, accounting for trailing `/`
        #expect(Socket("ws://example.com/chat/")
            .endPointUrl.absoluteString == "ws://example.com/chat/websocket?vsn=2.0.0")
        
        // Appends `params`
        #expect(Socket("http://example.com/chat", params: ["token": "abc123"])
            .endPointUrl.absoluteString == "ws://example.com/chat/websocket?vsn=2.0.0&token=abc123")
    }
    
}

@Suite("Socket tests") class SocketConnectionTest {
    var transportClosureCalls = 0
    
    var socket: Socket!
    var transport = MockTransport()
    
    func fakeTransport(url: URL) -> PhoenixTransport {
        self.transportClosureCalls += 1
        return transport
    }
    
    init() {
        socket = Socket(endPoint: "/socket", transport: fakeTransport(url:))
        socket.skipHeartbeat = true
    }
    
    @Test func connect_establishes_connection_with_endpoint() {
        socket.connect()
        #expect(socket.connection != nil)
        #expect(transportClosureCalls == 1)
    }
    
    @MainActor
    @Test func connect_sets_callbacks_for_connection() {
        var open = 0
        socket.onOpen { open += 1 }
        
        var close = 0
        socket.onClose { close += 1 }
        
        var lastError: (Error, URLResponse?)?
        socket.onError { (error, resp) in lastError = (error, resp) }
        
        var lastMessage: Message?
        socket.onMessage { (message) in lastMessage = message }
        
        socket.connect()
        
        transport.delegate?.onOpen(response: nil)
        #expect(open == 1)
        
        transport.delegate?.onClose(code: .normalClosure, reason: nil)
        #expect(close == 1)
        
        transport.delegate?.onError(error: TestError.stub, response: nil)
        #expect(lastError != nil)
        
        
        let payload = try! JSONEncoder().encode("hi there")
        
        let message = Message(
            joinRef: "2",
            ref: "6",
            topic: "topic",
            event: "event",
            payload: payload,
            status: nil
        )
        
        let str = try! PhoenixSerializer().encode(message: message)
        
        transport.delegate?.onMessage(string: str)
        #expect(lastMessage != nil)
//        print(String(data: lastMessage!.payload, encoding: .utf8))
        print(str)
        #expect(String(data: lastMessage!.payload, encoding: .utf8) == "hi there")
    }
    
}

class MockTransport: PhoenixTransport {
    var readyState: SwiftPhoenixClient.PhoenixTransportReadyState = .closed
    var delegate: (any PhoenixTransportDelegate)? = nil
    
    var connectCount = 0
    var disconnectCount = 0
    
    var sentData = [Data]()
    var sentStrings = [String]()
    
    func connect(with headers: [String : Any]) {
        connectCount += 1
    }
    
    func disconnect(code: URLSessionWebSocketTask.CloseCode, reason: String?) {
        disconnectCount += 1
    }
    
    func send(data: Data) {
        sentData.append(data)
    }
    
    func send(string: String) {
        sentStrings.append(string)
    }
}
