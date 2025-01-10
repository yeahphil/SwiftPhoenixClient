// Copyright (c) 2021 David Stump <david@davidstump.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

/// Alias for a JSON dictionary [String: Any]
public typealias Payload = [String: Any]

/// Alias for a function returning an optional JSON dictionary (`Payload?`)
public typealias PayloadClosure = () -> Payload?

/// Struct that gathers callbacks assigned to the Socket
struct StateChangeCallbacks {
    let open: SynchronizedArray<(ref: String, callback: ((URLResponse?) -> Void))> = .init()
    let close: SynchronizedArray<(ref: String, callback: ((URLSessionWebSocketTask.CloseCode, String?) -> Void))> = .init()
    let error: SynchronizedArray<(ref: String, callback: ((Error, URLResponse?) -> Void))> = .init()
    let message: SynchronizedArray<(ref: String, callback: ((Message) -> Void))> = .init()
}


/// ## Socket Connection
/// A single connection is established to the server and
/// channels are multiplexed over the connection.
/// Connect to the server using the `Socket` class:
///
/// ```swift
/// let socket = new Socket("/socket", paramsClosure: { ["userToken": "123" ] })
/// socket.connect()
/// ```
///
/// The `Socket` constructor takes the mount point of the socket,
/// the authentication params, as well as options that can be found in
/// the Socket docs, such as configuring the heartbeat.
public class Socket: PhoenixTransportDelegate {
    
    
    //----------------------------------------------------------------------
    // MARK: - Public Attributes
    //----------------------------------------------------------------------
    /// The string WebSocket endpoint (ie `"ws://example.com/socket"`,
    /// `"wss://example.com"`, etc.) That was passed to the Socket during
    /// initialization. The URL endpoint will be modified by the Socket to
    /// include `"/websocket"` if missing.
    public let endPoint: String
        
    /// Custom headers to be added to the socket connection request
    public var headers: [String : Any] = [:]
    
    /// Resolves to return the `paramsClosure` result at the time of calling.
    /// If the `Socket` was created with static params, then those will be
    /// returned every time.
    public var params: Payload? {
        return self.paramsClosure?()
    }
    
    /// The optional params closure used to get params when connecting. Must
    /// be set when initializing the Socket.
    public let paramsClosure: PayloadClosure?
    
    /// The WebSocket transport. Default behavior is to provide a
    /// URLSessionWebsocketTask. See README for alternatives.
    private let transport: ((URL) -> PhoenixTransport)
    
    /// Phoenix serializer version, defaults to "2.0.0"
    public var vsn: String = Defaults.vsn
    
    /// Serializer used to encode/decode between the clienet and the server.
    public var serializer: Serializer = PhoenixSerializer()
    
    /// Customize how payloads are encoded before being sent to the server
    public var encoder: PayloadEncoder = PhoenixPayloadEncoder()
    
    /// Customize how payloads are decoded when being received from the server
    public var decoder: PayloadDecoder = PhoenixPayloadDecoder()
    
    /// Timeout to use when opening connections
    public var timeout: TimeInterval = Defaults.timeoutInterval
    
    /// Interval between sending a heartbeat
    public var heartbeatInterval: TimeInterval = Defaults.heartbeatInterval
    
    /// The maximum amount of time which the system may delay heartbeats in order to optimize power usage
    public var heartbeatLeeway: DispatchTimeInterval = Defaults.heartbeatLeeway
    
    /// Interval between socket reconnect attempts, in seconds
    public var reconnectAfter: SteppedBackoff = Defaults.reconnectSteppedBackOff
    
    /// Interval between channel rejoin attempts, in seconds
    public var rejoinAfter: SteppedBackoff = Defaults.rejoinSteppedBackOff
    
    // TODO: The docs do not match the functionality
    /// The optional function for specialized logging, ie:
    ///
    ///     socket.logger = { (kind, msg, data) in
    ///         // some custom logging
    ///     }
    ///
    public var logger: ((String) -> Void)?
    
    /// Disables heartbeats from being sent. Default is false.
    public var skipHeartbeat: Bool = false
        
    
    //----------------------------------------------------------------------
    // MARK: - Private Attributes
    //----------------------------------------------------------------------
    /// Callbacks for socket state changes
    let stateChangeCallbacks: StateChangeCallbacks = StateChangeCallbacks()
    
    /// Collection on channels created for the Socket
    public internal(set) var channels: [Channel] = []
    
    /// Buffers messages that need to be sent once the socket has connected. It is an array
    /// of tuples, with the ref of the message to send and the callback that will send the message.
    let sendBuffer = SynchronizedArray<(ref: String?, callback: () throws -> ())>()
    
    /// Ref counter for messages
    var ref: UInt64 = UInt64.min // 0 (max: 18,446,744,073,709,551,615)
    
    /// Timer that triggers sending new Heartbeat messages
    var heartbeatTimer: HeartbeatTimer?
    
    /// Ref counter for the last heartbeat that was sent
    var pendingHeartbeatRef: String?
    
    /// Timer to use when attempting to reconnect
    var reconnectTimer: TimeoutTimer
    
    /// Close status
    var closeStatus: URLSessionWebSocketTask.CloseCode? = nil
    
    /// The connection to the server
    var connection: PhoenixTransport? = nil
    
    
    //----------------------------------------------------------------------
    // MARK: - Initialization
    //----------------------------------------------------------------------
    public convenience init(_ endPoint: String, params: Payload? = nil) {
        self.init(endPoint: endPoint,
                  transport: { url in return URLSessionTransport(url: url) },
                  params: { params })
    }
    
    public convenience init(_ endPoint: String, params: PayloadClosure?) {
        self.init(endPoint: endPoint,
                  transport: { url in return URLSessionTransport(url: url) },
                  params: params)
    }
    
    
    public init(endPoint: String,
                transport: @escaping ((URL) -> PhoenixTransport),
                params: PayloadClosure? = nil) {
        self.transport = transport
        self.paramsClosure = params
        self.endPoint = endPoint
        
        self.reconnectTimer = TimeoutTimer()
        self.reconnectTimer.callback = { [weak self] in
            guard let self else { return }

            self.logItems("Socket attempting to reconnect")
            self.teardown(reason: "reconnection") { self.connect() }
        }
        self.reconnectTimer.timerCalculation = { [weak self] tries in
            guard let self else { return 5.0 }
            
            let interval = self.reconnectAfter(tries)
            self.logItems("Socket reconnecting in \(interval)s")
            return interval
        }
    }
    
    deinit {
        reconnectTimer.reset()
    }
    
    //----------------------------------------------------------------------
    // MARK: - Public
    //----------------------------------------------------------------------
    /// - return: The socket protocol, wss or ws
    public var websocketProtocol: String? {
        return endPointUrl.scheme
    }
    
    /// The fully qualified socket URL
    public var endPointUrl: URL {
        guard
            let url = URL(string: self.endPoint),
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { fatalError("Malformed URL: \(self.endPoint)") }
        
        let wsScheme = switch urlComponents.scheme {
        case "wss": "wss"
        case "https": "wss"
        default: "ws"
        }
        
    // Override the scheme to always be `ws` or `wss`
        urlComponents.scheme = wsScheme
        
        // Ensure that the URL ends with "/websocket
        if !urlComponents.path.contains("/websocket") {
            // Do not duplicate '/' in the path
            if urlComponents.path.last != "/" {
                urlComponents.path.append("/")
            }
            
            // append 'websocket' to the path
            urlComponents.path.append("websocket")
            
        }
        
        urlComponents.queryItems = [URLQueryItem(name: "vsn", value: vsn)]
        
        // If there are parameters, append them to the URL
        if let params = self.params {
            urlComponents.queryItems?.append(contentsOf: params.map {
                URLQueryItem(name: $0.key, value: String(describing: $0.value))
            })
        }
        
        guard let qualifiedUrl = urlComponents.url else {
            fatalError("Malformed URL while adding parameters")
        }
        
        return qualifiedUrl
    }
    
    
    /// - return: True if the socket is connected
    public var isConnected: Bool {
        return self.connectionState == .open
    }
    
    /// - return: The state of the connect. [.connecting, .open, .closing, .closed]
    public var connectionState: PhoenixTransportReadyState {
        return self.connection?.readyState ?? .closed
    }
    
    /// Connects the Socket. The params passed to the Socket on initialization
    /// will be sent through the connection. If the Socket is already connected,
    /// then this call will be ignored.
    public func connect() {
        // Do not attempt to reconnect if the socket is currently connected
        guard !isConnected else { return }
        
        // Reset the close status when attempting to connect
        self.closeStatus = nil
        
        self.connection = self.transport(self.endPointUrl)
        self.connection?.delegate = self
                
        self.connection?.connect(with: self.headers)
    }
    
    /// Disconnects the socket
    ///
    /// - parameter code: Optional. Closing status code
    /// - parameter callback: Optional. Called when disconnected
    public func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure,
                           reason: String? = nil,
                           callback: (() -> Void)? = nil) {
        // The socket was closed cleanly by the User
        self.closeStatus = code
        
        // Reset any reconnects and teardown the socket connection
        self.reconnectTimer.reset()
        self.teardown(code: code, reason: reason, callback: callback)
    }
    
    internal func teardown(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: String? = nil, callback: (() -> Void)? = nil) {
        self.connection?.delegate = nil
        self.connection?.disconnect(code: code, reason: reason)
        self.connection = nil
        
        // The socket connection has been torndown, heartbeats are not needed
        self.heartbeatTimer?.stop()
        
        // Since the connection's delegate was nil'd out, inform all state
        // callbacks that the connection has closed
        self.stateChangeCallbacks.close.forEach({ $0.callback(code, reason) })
        callback?()
    }
    
    
    
    //----------------------------------------------------------------------
    // MARK: - Register Socket State Callbacks
    //----------------------------------------------------------------------
    
    /// Registers callbacks for connection open events. Does not handle retain
    /// cycles. Use `delegateOnOpen(to:)` for automatic handling of retain cycles.
    ///
    /// Example:
    ///
    ///     socket.onOpen() { [weak self] in
    ///         self?.print("Socket Connection Open")
    ///     }
    ///
    /// - parameter callback: Called when the Socket is opened
    @discardableResult
    public func onOpen(callback: @escaping () -> Void) -> String {
        onOpen { _ in callback() }
    }
    
    /// Registers callbacks for connection open events. Does not handle retain
    /// cycles. Use `delegateOnOpen(to:)` for automatic handling of retain cycles.
    ///
    /// Example:
    ///
    ///     socket.onOpen() { [weak self] response in
    ///         self?.print("Socket Connection Open")
    ///     }
    ///
    /// - parameter callback: Called when the Socket is opened
    @discardableResult
    public func onOpen(callback: @escaping (URLResponse?) -> Void) -> String {
        append(callback: callback, to: self.stateChangeCallbacks.open)
    }
    
    /// Registers callbacks for connection close events. Does not handle retain
    /// cycles. Use `delegateOnClose(_:)` for automatic handling of retain cycles.
    ///
    /// Example:
    ///
    ///     socket.onClose() { [weak self] in
    ///         self?.print("Socket Connection Close")
    ///     }
    ///
    /// - parameter callback: Called when the Socket is closed
    @discardableResult
    public func onClose(callback: @escaping () -> Void) -> String {
        onClose { _, _ in callback() }
    }
    
    /// Registers callbacks for connection close events.
    ///
    /// Example:
    ///
    ///     socket.onClose() { [weak self] code, reason in
    ///         self?.print("Socket Connection Close")
    ///     }
    ///
    /// - parameter callback: Called when the Socket is closed
    @discardableResult
    public func onClose(callback: @escaping (URLSessionWebSocketTask.CloseCode, String?) -> Void) -> String {
        append(callback: callback, to: self.stateChangeCallbacks.close)
    }
    
    /// Registers callbacks for connection error events.
    ///
    /// Example:
    ///
    ///     socket.onError() { [weak self] (error) in
    ///         self?.print("Socket Connection Error", error)
    ///     }
    ///
    /// - parameter callback: Called when the Socket errors
    @discardableResult
    public func onError(callback: @escaping (Error, URLResponse?) -> Void) -> String {
        append(callback: callback, to: self.stateChangeCallbacks.error)
    }
    
    /// Registers callbacks for connection message events.
    ///
    /// Example:
    ///
    ///     socket.onMessage() { [weak self] (message) in
    ///         self?.print("Socket Connection Message", message)
    ///     }
    ///
    /// - parameter callback: Called when the Socket receives a message event
    @discardableResult
    public func onMessage(callback: @escaping MessageHandler) -> String {
        append(callback: callback, to: self.stateChangeCallbacks.message)
    }
    
    private func append<T>(callback: T, to array: SynchronizedArray<(ref: String, callback: T)>) -> String {
        let ref = makeRef()
        array.append((ref, callback))
        return ref
    }
    
    /// Releases all stored callback hooks (onError, onOpen, onClose, etc.) You should
    /// call this method when you are finished when the Socket in order to release
    /// any references held by the socket.
    public func releaseCallbacks() {
        stateChangeCallbacks.open.removeAll()
        stateChangeCallbacks.close.removeAll()
        stateChangeCallbacks.error.removeAll()
        stateChangeCallbacks.message.removeAll()
    }
    
    
    
    //----------------------------------------------------------------------
    // MARK: - Channel Initialization
    //----------------------------------------------------------------------
    /// Initialize a new Channel
    ///
    /// Example:
    ///
    ///     let channel = socket.channel("rooms", params: ["user_id": "abc123"])
    ///
    /// - parameter topic: Topic of the channel
    /// - parameter params: Optional. Parameters for the channel
    /// - return: A new channel
    public func channel(_ topic: String,
                        params: [String: Any] = [:]) -> Channel {
        let channel = Channel(topic: topic, params: params, socket: self)
        self.channels.append(channel)
        
        return channel
    }
    
    /// Removes the Channel from the socket. This does not cause the channel to
    /// inform the server that it is leaving. You should call channel.leave()
    /// prior to removing the Channel.
    ///
    /// Example:
    ///
    ///     channel.leave()
    ///     socket.remove(channel)
    ///
    /// - parameter channel: Channel to remove
    public func remove(_ channel: Channel) {
        self.off(channel.stateChangeRefs)
        self.channels.removeAll(where: { $0.joinRef == channel.joinRef })
    }
    
    /// Removes `onOpen`, `onClose`, `onError,` and `onMessage` registrations.
    ///
    ///
    /// - Parameter refs: List of refs returned by calls to `onOpen`, `onClose`, etc
    public func off(_ refs: [String]) {
        self.stateChangeCallbacks.open.removeAll { refs.contains($0.ref) }
        self.stateChangeCallbacks.close.removeAll { refs.contains($0.ref) }
        self.stateChangeCallbacks.error.removeAll { refs.contains($0.ref) }
        self.stateChangeCallbacks.message.removeAll { refs.contains($0.ref) }
    }
    
    
    //----------------------------------------------------------------------
    // MARK: - Sending Data
    //----------------------------------------------------------------------
    /// Sends data through the Socket. This method is internal. Instead, you
    /// should call `push(_:, payload:, timeout:)` on the Channel you are
    /// sending an event to.
    ///
    /// - parameter topic:
    /// - parameter event:
    /// - parameter payload:
    /// - parameter ref: Optional. Defaults to nil
    /// - parameter joinRef: Optional. Defaults to nil
    internal func push(topic: String,
                       event: String,
                       payload: Data,
                       ref: String? = nil,
                       joinRef: String? = nil,
                       asBinary: Bool = false) {
        
        let callback: (() throws -> ()) = { [weak self] in
            guard let self else { return }
            
            let message = Message.message(
                joinRef: joinRef,
                ref: ref,
                topic: topic,
                event: event,
                payload: payload
            )

            if asBinary {
                let binary = serializer.binaryEncode(message: message)
                self.logItems("push", "Sending binary \(binary)" )
                self.connection?.send(data: binary)
                
            } else {
                let text = try serializer.encode(message: message)
                self.logItems("push", "Sending \(text)" )
                self.connection?.send(string: text)
            }
        }
        
        /// If the socket is connected, then execute the callback immediately.
        if isConnected {
            try? callback()
        } else {
            /// If the socket is not connected, add the push to a buffer which will
            /// be sent immediately upon connection.
            self.sendBuffer.append((ref: ref, callback: callback))
        }
    }
    
    /// - return: the next message ref, accounting for overflows
    public func makeRef() -> String {
        self.ref = (ref == UInt64.max) ? 0 : self.ref + 1
        return String(ref)
    }
    
    /// Logs the message. Override Socket.logger for specialized logging. noops by default
    ///
    /// - parameter items: List of items to be logged. Behaves just like debugPrint()
    func logItems(_ items: Any...) {
        let msg = items.map( { return String(describing: $0) } ).joined(separator: ", ")
        self.logger?("SwiftPhoenixClient: \(msg)")
    }
    
    //----------------------------------------------------------------------
    // MARK: - Connection Events
    //----------------------------------------------------------------------
    /// Called when the underlying Websocket connects to it's host
    internal func onConnectionOpen(response: URLResponse?) {
        self.logItems("transport", "Connected to \(endPoint)")
        
        // Reset the close status now that the socket has been connected
        self.closeStatus = nil
        
        // Send any messages that were waiting for a connection
        self.flushSendBuffer()
        
        // Reset how the socket tried to reconnect
        self.reconnectTimer.reset()
        
        // Restart the heartbeat timer
        self.resetHeartbeat()
        
        // Inform all onOpen callbacks that the Socket has opened
        self.stateChangeCallbacks.open.forEach({ $0.callback(response) })
    }
    
    internal func onConnectionClosed(code: URLSessionWebSocketTask.CloseCode, reason: String?) {
        self.logItems("transport", "close")
        
        // Send an error to all channels
        self.triggerChannelError()
        
        // Prevent the heartbeat from triggering if the
        self.heartbeatTimer?.stop()
        
        // Only attempt to reconnect if the socket did not close normally,
        // or if it was closed abnormally but on client side (e.g. due to heartbeat timeout)
        if (self.closeStatus == nil || self.closeStatus == .invalid) {
            self.reconnectTimer.scheduleTimeout()
        }
        
        self.stateChangeCallbacks.close.forEach({ $0.callback(code, reason) })
    }
    
    internal func onConnectionError(_ error: Error, response: URLResponse?) {
        self.logItems("transport", error, response ?? "")
        
        // Send an error to all channels
        self.triggerChannelError()
        
        // Inform any state callbacks of the error
        self.stateChangeCallbacks.error.forEach({ $0.callback(error, response) })
    }
    
    internal func onConnectionMessage(_ message: Message) {
        // Clear heartbeat ref, preventing a heartbeat timeout disconnect
        if message.ref == pendingHeartbeatRef { pendingHeartbeatRef = nil }
        
        // Dispatch the message to all channels that belong to the topic
        self.channels
            .filter( { $0.isMember(message) } )
            .forEach( { $0.trigger(message) } )
        
        // Inform all onMessage callbacks of the message
        self.stateChangeCallbacks.message.forEach({ $0.callback(message) })
    }
    
    /// Triggers an error event to all of the connected Channels
    internal func triggerChannelError() {
        self.channels.forEach { (channel) in
            // Only trigger a channel error if it is in an "opened" state
            if !(channel.isErrored || channel.isLeaving || channel.isClosed) {
                channel.trigger(event: ChannelEvent.error)
            }
        }
    }
    
    /// Send all messages that were buffered before the socket opened
    internal func flushSendBuffer() {
        guard isConnected else { return }
        self.sendBuffer.forEach( { try? $0.callback() } )
        self.sendBuffer.removeAll()
    }
    
    /// Removes an item from the sendBuffer with the matching ref
    internal func removeFromSendBuffer(ref: String) {
        self.sendBuffer.removeAll { $0.ref == ref }
    }

    
    // Leaves any channel that is open that has a duplicate topic
    internal func leaveOpenTopic(topic: String) {
        guard
            let dupe = self.channels.first(where: { $0.topic == topic && ($0.isJoined || $0.isJoining) })
        else { return }
        
        self.logItems("transport", "leaving duplicate topic: [\(topic)]" )
        dupe.leave()
    }
    
    //----------------------------------------------------------------------
    // MARK: - Heartbeat
    //----------------------------------------------------------------------
    internal func resetHeartbeat() {
        // Clear anything related to the heartbeat
        self.pendingHeartbeatRef = nil
        self.heartbeatTimer?.stop()
        
        // Do not start up the heartbeat timer if skipHeartbeat is true
        guard !skipHeartbeat else { return }
        
        self.heartbeatTimer = HeartbeatTimer(timeInterval: heartbeatInterval, leeway: heartbeatLeeway)
        self.heartbeatTimer?.start(eventHandler: { [weak self] in
            self?.sendHeartbeat()
        })
    }
    
    /// Sends a heartbeat payload to the phoenix servers
    @objc func sendHeartbeat() {
        // Do not send if the connection is closed
        guard isConnected else { return }
        
        
        // If there is a pending heartbeat ref, then the last heartbeat was
        // never acknowledged by the server. Close the connection and attempt
        // to reconnect.
        if let _ = self.pendingHeartbeatRef {
            self.pendingHeartbeatRef = nil
            self.logItems("transport",
                          "heartbeat timeout. Attempting to re-establish connection")
            
            // Close the socket manually, flagging the closure as abnormal. Do not use
            // `teardown` or `disconnect` as they will nil out the websocket delegate.
            self.abnormalClose("heartbeat timeout")
            
            return
        }
        
        // The last heartbeat was acknowledged by the server. Send another one
        self.pendingHeartbeatRef = self.makeRef()
        self.push(topic: "phoenix",
                  event: ChannelEvent.heartbeat,
                  payload: Defaults.emptyPayload,
                  ref: self.pendingHeartbeatRef)
    }
    
    internal func abnormalClose(_ reason: String) {
        self.closeStatus = .abnormalClosure
        
        /*
         We use NORMAL here since the client is the one determining to close the
         connection. However, we set to close status to abnormal so that
         the client knows that it should attempt to reconnect.
         
         If the server subsequently acknowledges with code 1000 (normal close),
         the socket will keep the `.abnormal` close status and trigger a reconnection.
         */
        self.connection?.disconnect(code: URLSessionWebSocketTask.CloseCode.normalClosure, reason: reason)
    }
    
    
    //----------------------------------------------------------------------
    // MARK: - TransportDelegate
    //----------------------------------------------------------------------
    public func onOpen(response: URLResponse?) {
        DispatchQueue.main.async {
            self.onConnectionOpen(response: response)
        }
    }
    
    public func onError(error: Error, response: URLResponse?) {
        DispatchQueue.main.async {
            self.onConnectionError(error, response: response)
        }
    }
    
    public func onMessage(data: Data) {
        guard let message = try? serializer.binaryDecode(data: data) else {
            self.logItems("receive: Unable to parse binary: \(data)")
            return
        }
        
        self.logItems("receive ", data)
        DispatchQueue.main.async { self.onConnectionMessage(message) }
    }
    
    public func onMessage(string: String) {
        let message: Message
        do {
            message = try serializer.decode(text: string)
        } catch {
            self.logItems("receive: Unable to parse JSON: \(error), \(string)")
            return
        }
        
        self.logItems("receive ", string)
        DispatchQueue.main.async { self.onConnectionMessage(message) }
    }

    public func onClose(code: URLSessionWebSocketTask.CloseCode, reason: String? = nil) {
        DispatchQueue.main.async {
            self.closeStatus = code
            self.onConnectionClosed(code: code, reason: reason)
        }
    }
}
