//
//  ReconnectTunnelOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 10/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

class ReconnectTunnelOperation: ResultOperation<(), TunnelManager.Error> {
    private let interactor: TunnelInteractor
    private let selectNewRelay: Bool
    private var task: Cancellable?

    init(
        dispatchQueue: DispatchQueue,
        interactor: TunnelInteractor,
        selectNewRelay: Bool
    )
    {
        self.interactor = interactor
        self.selectNewRelay = selectNewRelay

        super.init(dispatchQueue: dispatchQueue)
    }

    override func main() {
        guard let tunnel = interactor.tunnel else {
            finish(completion: .failure(.unsetTunnel))
            return
        }

        var selectorResult: RelaySelectorResult?
        if selectNewRelay {
            guard let cachedRelays = RelayCache.Tracker.shared.getCachedRelays() else {
                finish(completion: .failure(.relayListUnavailable))
                return
            }

            do {
                selectorResult = try RelaySelector.evaluate(
                    relays: cachedRelays.relays,
                    constraints: interactor.settings.relayConstraints
                )
            } catch {
                finish(completion: .failure(.cannotSatisfyRelayConstraints))
                return
            }
        }

        let session = TunnelIPC.Session(tunnel: tunnel)

        task = session.reconnectTunnel(
            relaySelectorResult: selectorResult
        ) { [weak self] completion in
            self?.finish(completion: completion.mapError { .ipcError($0) })
        }
    }

    override func operationDidCancel() {
        task?.cancel()
        task = nil
    }
}
