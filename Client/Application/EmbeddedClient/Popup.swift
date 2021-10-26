// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

public enum PopupSize {
    case fullscreen
    case large
    case medium
    case small
}

public protocol PopupConfiguration {
    
}

public struct PointSizeConfiguration: PopupConfiguration {
    public var point: CGPoint
    public var preferredSize: CGRect
}

public struct CenterConfiguration: PopupConfiguration {
    public var size: PopupSize = .medium
    public var preferredSize: CGSize? = nil
}
