//
//  HeartbeatTimerTest.swift
//  SwiftPhoenixClientTests
//
//  Created by Phillip Kast on 1/9/25.
//  Copyright © 2025 SwiftPhoenixClient. All rights reserved.
//

import Testing
@testable import SwiftPhoenixClient

struct HeartbeatTimerTest {
    let queue = DispatchQueue(label: "heartbeat.timer.spec")
    let timer: HeartbeatTimer
    
    init() {
        timer = HeartbeatTimer(timeInterval: 10, queue: queue)
    }
    
    @Test func is_valid_returns_false_if_not_started() {
        #expect(!timer.isValid)
    }
    
    @Test func is_valid_returns_true_if_started() {
        timer.start { /* no-op */ }
        #expect(timer.isValid)
    }
    
    @Test func is_valid_returns_false_if_has_been_stopped() {
        timer.start { /* no-op */ }
        timer.stop()
        #expect(!timer.isValid)
    }
    
    @Test func fire_calls_the_event_handler() {
        var timerCalled = 0
        timer.start { timerCalled += 1 }
        
        #expect(timerCalled == 0)
        
        timer.fire()
        
        #expect(timerCalled == 1)
    }
    
    @Test func fire_doesnt_call_the_event_handler_if_stopped() {
        var timerCalled = 0
        timer.start { timerCalled += 1 }
        
        #expect(timerCalled == 0)
        
        timer.stop()
        timer.fire()
        
        #expect(timerCalled == 0)
    }
    
    @Test func equatable_works() {
        let timerA = HeartbeatTimer(timeInterval: 10, queue: queue)
        let timerB = HeartbeatTimer(timeInterval: 10, queue: queue)
        
        #expect(timerA == timerA)
        #expect(timerA != timerB)
    }
}
