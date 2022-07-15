//
//  Tunnel+IPC.swift
//  MullvadVPN
//
//  Created by pronebird on 16/09/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension Tunnel {
    typealias CompletionHandler<T> = (OperationCompletion<T, TunnelIPC.Error>) -> Void

    /// Shared operation queue used for IPC requests.
    private static let sharedOperationQueue = AsyncOperationQueue()

    /// Shared queue used by IPC operations.
    private static let sharedDispatchQueue = DispatchQueue(label: "TunnelIPC.SessionQueue")

    func reconnectTunnel(
        relaySelectorResult: RelaySelectorResult?,
        completionHandler: @escaping CompletionHandler<Void>
    ) -> Cancellable {
        let operation = TunnelIPC.RequestOperation(
            dispatchQueue: Self.sharedDispatchQueue,
            tunnel: self,
            request: .reconnectTunnel(relaySelectorResult),
            options: TunnelIPC.RequestOptions(),
            completionHandler: completionHandler
        )

        Self.sharedOperationQueue.addOperation(operation)

        return operation
    }

    func getTunnelStatus(completionHandler: @escaping CompletionHandler<PacketTunnelStatus>)
        -> Cancellable
    {
        let operation = TunnelIPC.RequestOperation(
            dispatchQueue: Self.sharedDispatchQueue,
            tunnel: self,
            request: .getTunnelStatus,
            options: TunnelIPC.RequestOptions(),
            completionHandler: completionHandler
        )

        Self.sharedOperationQueue.addOperation(operation)

        return operation
    }

}
