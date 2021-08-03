//
//  Channel+Combine.swift
//  Channel+Combine
//
//  Created by Phillip Kast on 8/2/21.
//  Copyright © 2021 SwiftPhoenixClient. All rights reserved.
//

import Foundation
import Combine

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Channel {
    enum Errors: Error {
        case unknown
    }
    
    
    /// Provides a publisher that emits on channel events, like Channel.on() //
    /// Emits completion when the channel closes
    /// And, emits an error if the channel receives an error. This might not be correct -- it might be correct to match the Rx extension, which does no error handling,
    /// and require error handling on the socket rather than the channel -- this version will stop emitting events if the socket errors, even if it reconnects and would have continued.
    public func publisher(on event: String) -> AnyPublisher<Message, Error> {
        let subject = PassthroughSubject<Message, Error>()
        
        let refs = [
            on(event) {
                subject.send($0)
            },
            onClose { message in
                subject.send(completion: .finished)
            },
            onError { message in
                subject.send(completion: .failure(Errors.unknown))
            }
        ]
        
        return subject
            .handleEvents(receiveCancel: { [weak self] in
                for refId in refs {
                    self?.off(event, ref: refId)
                }
            })
            .eraseToAnyPublisher()
    }    
}
