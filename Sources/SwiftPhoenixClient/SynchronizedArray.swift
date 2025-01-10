//
//  SynchronizedArray.swift
//  SwiftPhoenixClient
//
//  Created by Daniel Rees on 4/12/23.
//  Copyright © 2023 SwiftPhoenixClient. All rights reserved.
//

import Foundation

/// A thread-safe array.
public class SynchronizedArray<Element> {
    fileprivate let queue = DispatchQueue(label: "spc_sync_array", attributes: .concurrent)
    fileprivate var array: [Element]
    
    var count: Int {
        self.array.count
    }
    
    var isEmpty: Bool {
        self.array.isEmpty
    }
    
    public init(_ array: [Element] = []) {
        self.array = array
    }
    
    func append( _ newElement: Element) {
        queue.async(flags: .barrier) {
            self.array.append(newElement)
        }
    }
    
    func forEach(_ body: (Element) -> Void) {
        queue.sync { self.array }.forEach(body)
    }
    
    func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Element] {
        return try queue.sync { self.array }.filter(isIncluded)
    }
    
    func removeAll() {
        queue.async(flags: .barrier) {
            self.array.removeAll()
        }
    }
    
    func removeAll(where shouldBeRemoved: @escaping (Element) -> Bool) {
        queue.async(flags: .barrier) {
            self.array.removeAll(where: shouldBeRemoved)
        }
    }
}
