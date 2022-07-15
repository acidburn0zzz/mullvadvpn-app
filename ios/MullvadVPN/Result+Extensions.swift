//
//  Result+Extensions.swift
//  MullvadVPN
//
//  Created by pronebird on 15/03/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension Result {
    var value: Success? {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }

    var error: Failure? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}

extension Result {
    func flattenValue<T>() -> T? where Success == Optional<T> {
        switch self {
        case .success(let optional):
            return optional.flatMap { $0 }
        case .failure:
            return nil
        }
    }
}
