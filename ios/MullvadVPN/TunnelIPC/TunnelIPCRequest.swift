//
//  TunnelIPCRequest.swift
//  TunnelIPCRequest
//
//  Created by pronebird on 27/07/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension TunnelIPC {
    /// Enum describing actions that packet tunnel provider supports.
    enum Request: Codable, CustomStringConvertible {
        /// Request the tunnel to reconnect.
        /// The packet tunnel reconnects to the current relay when selector result is `nil`.
        case reconnectTunnel(RelaySelectorResult?)

        /// Request the tunnel status.
        case getTunnelStatus

        var description: String {
            switch self {
            case .reconnectTunnel:
                return "reconnectTunnel"
            case .getTunnelStatus:
                return "getTunnelStatus"
            }
        }
    }
}
