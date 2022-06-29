//
//  ReloadTunnelOperation.swift
//  MullvadVPN
//
//  Created by pronebird on 10/12/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

class ReloadTunnelOperation: ResultOperation<(), TunnelManager.Error> {
    private let interactor: TunnelInteractor
    private var task: Cancellable?

    init(dispatchQueue: DispatchQueue, interactor: TunnelInteractor) {
        self.interactor = interactor

        super.init(dispatchQueue: dispatchQueue)
    }

    override func main() {
        guard let tunnel = interactor.tunnel else {
            finish(completion: .failure(.unsetTunnel))
            return
        }

        let session = TunnelIPC.Session(tunnel: tunnel)

        task = session.reloadTunnelSettings { [weak self] completion in
            guard let self = self else { return }

            self.finish(completion: completion.mapError { .ipcError($0) })
        }
    }

    override func operationDidCancel() {
        task?.cancel()
        task = nil
    }
}
