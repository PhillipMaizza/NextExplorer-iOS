import Foundation
import Network
import os

/// Nudges iOS to show the Local Network permission alert while the user is still typing the
/// server address, rather than springing it on them the moment they tap "Test connection".
///
/// Opening a UDP socket to the limited-broadcast address and sending one datagram is enough
/// for the system to class the app as a local-network client and prompt. The datagram goes
/// nowhere useful — port 9 is discard — it exists only to touch the network.
enum LocalNetworkPrimer {
    private static let connection = OSAllocatedUnfairLock<NWConnection?>(initialState: nil)

    /// Safe to call repeatedly — only the first call does anything.
    static func prime() {
        connection.withLock { existing in
            guard existing == nil else { return }

            let parameters = NWParameters.udp
            parameters.includePeerToPeer = true
            let conn = NWConnection(
                host: "255.255.255.255",
                port: 9,
                using: parameters
            )
            existing = conn

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: Data([0]), completion: .contentProcessed { _ in tearDown() })
                case .failed, .cancelled:
                    tearDown()
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
        }
    }

    private static func tearDown() {
        connection.withLock { conn in
            conn?.cancel()
            conn = nil
        }
    }
}
