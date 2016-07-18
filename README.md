# WKMagicBridge
iOS web views do not support sandboxed environments for content scripts; injected scripts are executed in the same context as scripts running on the web page. This project experiments with creating a secure messaging layer between Swift and an arbitrary page in a `WKWebView`. "Secure" means that the page is not able to intercept or send messages in either direction.

Other useful features include the ability to create cross-origin HTTP requests and print to the Xcode console from content scripts.

**Warning: There are many land mines to be aware of when implementing page-side callback handlers (see below). The only way to securely communicate with the content script in an untrusted page is to not send sensitive data in the first place.**

Unfortunately, there are some fundamental issues that make such an implementation impractical for production code. The page can overwrite prototypes of objects in the window (i.e., `String.prototype.indexOf = function () { /* steal string contents */ };`), so even if we create a secure bridge that carefully avoids interference by the page, any client JavaScript using such an API will still be vulnerable.

That said, this messaging API can still be used to communicate with pages that you trust as an alternative to the built-in `evaluateJavaScript` and `postMessage` `WKWebView` APIs. Note, however, that there are several other existing (and more established) projects that already accomplish this.

### Usage

See the included `WKMagicBridgeSample` project for a full working demo.

Sample Swift-side code:
```
// Set up the bridge.
let bridge = WKMagicBridge(webView: webView)
let path = NSBundle.mainBundle().pathForResource("Sample", ofType: "js")!
let source = try! String(contentsOfFile: path)
let script = WKMagicBridgeScript(source: source, injectionTime: .AtDocumentEnd)
bridge.addUserScript(script)

// Send a message.
bridge.postMessage(handlerName: "PageTitle", data: nil) { response in
    print("Page title response: \(response!)")
}
```

Sample JS-side code:
```
wkutils.addHandler("PageTitle", function (message, sendResponse) {
  wkutils.print("Got PageTitle message!");
  sendResponse(document.title);
});
```

### Swift API
* `WKMagicBridge(webView: WKWebView, isolatedContext: Bool = true)`
  * Constructor. Set `isolatedContext` to `true` (default) to hide `wkutils` from the page window. Setting to `false` attaches `wkutils` to the document window, allowing scripts on the page to use it.
* `addUserScript(script: WKMagicBridgeScript)`
  * Adds a content script to the bridge, which will be executed at the beginning of every page load. This script will be executed in the `WKMagicBridge` closure, meaning it has access to the `wkutils` object.
* `removeUserScript(script: WKMagicBridgeScript)`
  * Removes a content script from the bridge.
* `addHandler(withName: String, handler: WKMagicHandler)`
  * Adds a handler to this bridge to receive messages from content scripts. Handler names must be unique; otherwise, existing handlers with the given name will be overridden.
* `removeHandler(withName: String)`
  * Removes a handler from this bridge.
* `postMessage(handlerName: String, data: AnyObject?, response: WKMagicResponse)`
  * Posts a message to JavaScript. A JavaScript-side handler must have been set up with the given `handlerName` to receive this message.

### JavaScript API
* `wkutils.addHandler(name, callback)`
  * Registers a handler to listen for messages from Swift. Handler names must be unique; otherwise, existing handlers with the given name will be overridden.
* `wkutils.postMessage(name, data, sendResponse)`
  * Posts a message to Swift. A Swift-side handler must have been set up with the given `handlerName` to receive this message.
* `wkutils.print(data)`
  * Prints the objects to the Xcode console. Useful for quick debugging without having to connect to the page using a remote debugger.
* `wkutils.xhr(request)`
  * Makes a cross-origin HTTP request. The `request` object must have the following signature:
    * `request.url`: The URL of the resource to fetch.
    * `request.complete(response)`: The callback function executed when the response is received.
  * The `response` object has the following signature:
    * `response.status`: The HTTP status code of the response.
    * `response.mimeType`: The MIME type of the response.
    * `response.text`: The body text of the response.
    * `response.data`: The response data, which will be:
      * A Document object if the MIME type is an XML/HTML document (null on parse failure).
      * A JavaScript object if the MIME type is a JSON object (null on parse failure).
      * A string equal to response.text for all other cases.
