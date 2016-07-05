/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit

public typealias WKMagicHandler = (WKScriptMessage, WKMagicResponse) -> ()
public typealias WKMagicResponse = AnyObject? -> ()

class JSONSerializationError: ErrorType {}

public enum WKMagicBridgeScriptInjectionTime {
    case AtDocumentStart
    case AtDocumentEnd
}

public class WKMagicBridgeScript {
    let source: String
    let injectionTime: WKMagicBridgeScriptInjectionTime

    public init(source: String, injectionTime: WKMagicBridgeScriptInjectionTime) {
        self.source = source
        self.injectionTime = injectionTime
    }
}

// TODO: Allow multiple bridges?
public class WKMagicBridge: NSObject, WKScriptMessageHandler {
    let bundle = NSBundle(identifier: "com.thebnich.WKMagicBridge")!
    let secret = NSUUID().UUIDString
    let sharedSource: String
    let webView: WKWebView
    let isolatedContext: Bool

    public internal(set) var userScripts = [WKMagicBridgeScript]()
    var injectedScript: WKUserScript?

    var handlerMap = [String: WKMagicHandler]()
    var responseID = 0
    var responseMap = [Int: WKMagicResponse]()

    public init(webView: WKWebView, isolatedContext: Bool = true) {
        self.webView = webView
        self.isolatedContext = isolatedContext

        let shared = bundle.pathForResource("WKMagicBridge", ofType: "js")!
        sharedSource = try! String(contentsOfFile: shared)

        super.init()

        webView.configuration.userContentController.addScriptMessageHandler(self, name: "__wkutilsHandler__")
    }

    func rebuildScripts() {
        let startScripts = userScripts.flatMap { ($0.injectionTime == .AtDocumentStart) ? $0.source : nil }.joinWithSeparator("\n")
        let endScripts = userScripts.flatMap { ($0.injectionTime == .AtDocumentEnd) ? $0.source : nil }.joinWithSeparator("\n")

        let source =
            "(function () {\n" +
            "  'use strict';\n" +
            "  var __wksecret__ = '\(secret)';\n" +
            "  \(sharedSource)\n" +
            "  \(startScripts)\n" +
            "  document.addEventListener('DOMContentLoaded', function () {\n" +
            "    \(endScripts)\n" +
            "  }, false);\n" +
            (isolatedContext ? "" : "window.wkutils = wkutils;\n") +
            "}) ();"
        let newScript = WKUserScript(source: source, injectionTime: .AtDocumentStart, forMainFrameOnly: true)

        let controller = webView.configuration.userContentController
        let activeScripts = controller.userScripts
        controller.removeAllUserScripts()

        var added = false
        for script in activeScripts {
            if script === injectedScript {
                injectedScript = newScript
                controller.addUserScript(newScript)
                added = true
                continue
            }

            controller.addUserScript(script)
        }

        if !added {
            injectedScript = newScript
            controller.addUserScript(newScript)
        }
    }

    public func addUserScript(script: WKMagicBridgeScript) {
        userScripts.append(script)
        rebuildScripts()
    }

    public func removeUserScript(script: WKMagicBridgeScript) {
        guard let index = userScripts.indexOf({ $0 === script }) else { return }
        userScripts.removeAtIndex(index)
        rebuildScripts()
    }

    public func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        guard let body = message.body as? [String: AnyObject] else {
            print("Invalid message! \(message)")
            return
        }

        guard let key = body["secret"] as? String where key == secret else {
            print("Secret denied! \(message)")
            return
        }

        let data = body["data"]

        if let responseID = body["responseID"] as? Int {
            guard let sendResponse = responseMap[responseID] else {
                print("No response handler for response ID: \(responseID)")
                return
            }

            sendResponse(data)
            responseMap.removeValueForKey(responseID)
            return
        }

        guard let name = body["name"] as? String else {
            print("Invalid message! \(message)")
            return
        }

        if name == "__wkprint__" {
            if let message = data as? String {
                print(message)
            }
            return
        }

        if name == "__wkreset__" {
            print("Clearing callbacks")
            responseMap.removeAll()
            return
        }

        guard let ID = body["id"] as? Int else {
            assertionFailure("Invalid message! \(message)")
            return
        }

        if name == "__wkxhr__" {
            guard let data = body["data"],
                  let URLString = data["url"] as? String,
                  let URL = NSURL(string: URLString) else {
                print("Invalid message (XHR)")
                return
            }

            NSURLSession.sharedSession().dataTaskWithURL(URL) { data, response, error in
                let response = response as! NSHTTPURLResponse

                var responseData = [String: AnyObject]()
                responseData["status"] = response.statusCode
                responseData["mimeType"] = response.MIMEType

                let encoding: NSStringEncoding
                if let encodingName = response.textEncodingName {
                    let CFEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName)
                    encoding = CFStringConvertEncodingToNSStringEncoding(CFEncoding)
                } else {
                    encoding = NSISOLatin1StringEncoding
                }

                if let data = data,
                   let responseString = String(data: data, encoding: encoding) {
                    responseData["text"] = responseString
                }

                self.postResponse(ID, data: responseData)
            }.resume()

            return
        }

        guard let handler = handlerMap[name] else {
            print("No handler exists for name: \(name)")
            return
        }

        // TODO: Not message
        handler(message) { response in
            self.postResponse(ID, data: response)
        }
    }

    public func addHandler(withName name: String, handler: WKMagicHandler) {
        handlerMap[name] = handler
    }

    public func removeHandler(withName name: String) {
        handlerMap.removeValueForKey(name)
    }

    public func postMessage(handlerName name: String, data: AnyObject?, response: WKMagicResponse) {
        responseMap[responseID] = response

        var message = [String: AnyObject]()
        message["secret"] = secret
        message["id"] = responseID
        message["name"] = name
        message["data"] = data ?? NSNull()

        guard let JSON = toJSON(message) else { return }

        webView.evaluateJavaScript("__wkutils__.receiveMessage(\(JSON))", completionHandler: nil)

        responseID += 1
    }

    func postResponse(ID: Int, data: AnyObject?) {
        var message = [String: AnyObject]()
        message["secret"] = secret
        message["responseID"] = ID
        message["data"] = data ?? NSNull()

        guard let JSON = toJSON(message) else { return }

        webView.evaluateJavaScript("__wkutils__.receiveMessage(\(JSON))", completionHandler: nil)
    }

    func toJSON(object: [String: AnyObject]) -> String? {
        guard NSJSONSerialization.isValidJSONObject(object) else {
            print("Error: Data could not be serialized.")
            return nil
        }

        do {
            let data = try NSJSONSerialization.dataWithJSONObject(object, options: [])
            guard let JSON = String(data: data, encoding: NSUTF8StringEncoding) else {
                throw JSONSerializationError()
            }
            return JSON
        } catch {
            print("Error: Data could not be serialized.")
        }

        return nil
    }
}
