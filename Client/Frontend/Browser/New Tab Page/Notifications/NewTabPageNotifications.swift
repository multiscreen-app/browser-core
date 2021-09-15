// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveCore
import BraveShared

class NewTabPageNotifications {
    /// Different types of notifications can be presented to users.
    enum NotificationType {
        /// Notification to inform the user about branded images program.
//        case brandedImages(state: BrandedImageCalloutState)
        // MS comment out brave rewards placeholder
        case placeholder
    }
    
    
    func notificationToShow(isShowingBackgroundImage: Bool) -> NotificationType? {
        if !isShowingBackgroundImage {
            return nil
        }

        return .placeholder
    }
}
