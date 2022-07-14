//
//  TunnelIPCSession.swift
//  MullvadVPN
//
//  Created by pronebird on 16/09/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation
import NetworkExtension

extension TunnelIPC {
    /// Wrapper class around `NETunnelProviderSession` that provides convenient interface for
    /// interacting with the Packet Tunnel process.
    final class Session {
        typealias CompletionHandler<T> = (OperationCompletion<T, TunnelIPC.Error>) -> Void

        private let tunnel: Tunnel
        private let queue = DispatchQueue(label: "TunnelIPC.SessionQueue")
        private let operationQueue = AsyncOperationQueue()

        init(tunnel: Tunnel) {
            self.tunnel = tunnel
        }

        func reconnectTunnel(
            relaySelectorResult: RelaySelectorResult?,
            completionHandler: @escaping CompletionHandler<Void>
        ) -> Cancellable
        {
            let operation = RequestOperation(
                dispatchQueue: queue,
                tunnel: tunnel,
                request: .reconnectTunnel(relaySelectorResult),
                options: TunnelIPC.RequestOptions(),
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }

        func getTunnelStatus(completionHandler: @escaping CompletionHandler<PacketTunnelStatus>)
            -> Cancellable
        {
            let operation = RequestOperation(
                dispatchQueue: queue,
                tunnel: tunnel,
                request: .getTunnelStatus,
                options: TunnelIPC.RequestOptions(),
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }
    }
}
