//
//  TunnelManagerError.swift
//  TunnelManagerError
//
//  Created by pronebird on 07/09/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension TunnelManager {
    enum Error: ChainedError {
        case unsetTunnel
        case invalidDeviceState
        case deviceRevoked
        case relayListUnavailable
        case cannotSatisfyRelayConstraints
        case systemVPNError(Swift.Error)
        case settingsStoreError(Swift.Error)
        case restError(REST.Error)
        case ipcError(TunnelIPC.Error)

        var errorDescription: String? {
            switch self {
            case .unsetTunnel:
                return "Tunnel is unset."
            case .invalidDeviceState:
                return "Cannot complete the request in such device state."
            case .deviceRevoked:
                return "Device is revoked."
            case .relayListUnavailable:
                return "Relay list is unavailable."
            case .cannotSatisfyRelayConstraints:
                return "Cannot satisfy relay constraints."
            case .systemVPNError:
                return "System VPN error."
            case .settingsStoreError:
                return "Settings store error."
            case .restError:
                return "REST error."
            case .ipcError:
                return "IPC error"
            }
        }
    }
}
