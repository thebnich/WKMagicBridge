/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import WebKit
import WKMagicBridge

class ViewController: UIViewController, WKNavigationDelegate {
    let webView = WKWebView()
    var bridge: WKMagicBridge!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.topAnchor.constraintEqualToAnchor(topLayoutGuide.bottomAnchor).active = true
        webView.leadingAnchor.constraintEqualToAnchor(view.leadingAnchor).active = true
        webView.trailingAnchor.constraintEqualToAnchor(view.trailingAnchor).active = true
        webView.bottomAnchor.constraintEqualToAnchor(view.bottomAnchor).active = true

        bridge = WKMagicBridge(webView: webView)
        setUpMagicBridge()

        webView.navigationDelegate = self
        webView.loadRequest(NSURLRequest(URL: NSURL(string: "https://www.mozilla.org")!))
    }

    func setUpMagicBridge() {
        let path = NSBundle.mainBundle().pathForResource("Sample", ofType: "js")!
        let source = try! String(contentsOfFile: path)
        let script = WKMagicBridgeScript(source: source, injectionTime: .AtDocumentEnd)
        bridge.addUserScript(script)
    }

    func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        print("Posting PageTitle message")
        bridge.postMessage(handlerName: "PageTitle", data: nil) { response in
            print("Page title response: \(response!)")
        }
    }
}

