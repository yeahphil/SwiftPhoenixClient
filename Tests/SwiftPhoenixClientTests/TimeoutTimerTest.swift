//
//  TimeoutTimerTest.swift
//  SwiftPhoenixClientTests
//
//  Created by Phillip Kast on 1/9/25.
//  Copyright © 2025 SwiftPhoenixClient. All rights reserved.
//

import Testing
@testable import SwiftPhoenixClient

struct TimeoutTimerTest {
    let fakeClock = FakeTimerQueue()
    var timer: TimeoutTimer
    
    init() {
        fakeClock.reset()
        
        timer = TimeoutTimer()
        timer.queue = fakeClock
    }
    
    @Test func schedules_timeouts_rests_timer_and_schedules_another_timeout() {
        var callbackTimes: [Date] = []
        
        timer.callback = {
            callbackTimes.append(Date())
        }
        
        timer.timerCalculation = { tries in
            return tries > 2 ? 10.0 : [1.0, 2.0, 5.0][tries - 1]
        }
        
        timer.scheduleTimeout()
        fakeClock.tick(1100)
        #expect(timer.tries == 1)
        
        timer.scheduleTimeout()
        fakeClock.tick(2100)
        #expect(timer.tries == 2)
        
        timer.reset()
        timer.scheduleTimeout()
        fakeClock.tick(1100)
        #expect(timer.tries == 1)
    }
    
    @Test func timer_doesnt_start_if_no_interval_provided() {
        timer.scheduleTimeout()
        #expect(timer.workItem == nil)
    }
}
