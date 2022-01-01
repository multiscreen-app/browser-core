// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import WebKit
import Shared

private let log = Logger.browserLogger

class HtmlSelectReplace: TabContentScript {
    fileprivate weak var tab: Tab?

    required init(tab: Tab) {
        self.tab = tab
    }

    static func name() -> String {
        return "HtmlSelectReplace"
    }

    func scriptMessageHandlerName() -> String? {
        return "htmlSelectReplaceMessageHandler"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        guard let body = message.body as? [String: AnyObject] else {
            return
        }
        
        if UserScriptManager.isMessageHandlerTokenMissing(in: body) {
            log.debug("Missing required security token.")
            return
        }

        guard let res = body["data"] as? [String: AnyObject] else { return }
        let scriptUrl = res["scriptUrl"] as! String
        if let url = URL(string: scriptUrl) {
            do {
                let contents = try String(contentsOf: url)
                tab?.webView?.evaluateJavaScript(contents, completionHandler: nil)
                log.debug("\(tab?.title) JavaScript loaded")
            } catch {
                // contents could not be loaded
                log.warning("Unable to evaluate JavaScript")
            }
        } else {
            log.warning("Unable to load URL")
        }
    }

    static var isActivated: Bool {
        return true
    }
}
