/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * This file is injected into a closure to provide an isolated context from the page.
 * Be careful not to leak this API to the page (e.g., by attaching it to an object
 * on the window), or else your app will be vulnerable to XSS attacks!
 */

var wkutils = (function () {
  var handlerMap = {};
  var responseID = 0;
  var responseMap = {};

  // The page may override window.webkit, so hold a reference here.
  var bridge = webkit.messageHandlers.__wkutilsHandler__;

  // Define an immutable property that we can call via evaluateJavaScript.
  // This property is exposed to the page, so we need to be careful not to leak
  // anything sensitive. We filter calls to receiveMessage() by our secret key
  // hidden from the page, so page-crafted calls will have no effect.
  Object.defineProperty(window, '__wkutils__', {
    value: Object.freeze({
      receiveMessage: function (message) {
        if (__wksecret__ !== message.secret) {
          wkutils.print('Invalid message (bad secret): ' + JSON.stringify(message));
          return;
        }

        if (message.responseID !== undefined) {
          var sendResponse = responseMap[message.responseID];
          if (!sendResponse) {
             wkutils.print('No response handler for response: ' + JSON.stringify(message));
             return;
          }

          sendResponse(message.data);
          delete responseMap[message.responseID];
          return;
        }

        if (message.id === undefined) {
          wkutils.print('Invalid message (no ID): ' + JSON.stringify(message));
          return;
        }

        var handler = handlerMap[message.name];
        if (!handler) {
          wkutils.print('No handler exists for message: ' + JSON.stringify(message));
          return;
        }

        handler(message.data, function (response) {
          bridge.postMessage({
            secret: __wksecret__,
            responseID: message.id,
            data: JSON.parse(JSON.stringify(response)),
          });
        });
      },
    })
  });

  // Clear the Swift response handler map on each pageshow. In JS, we have no
  // way to determine if the response callback has gone out of scope or is
  // still waiting to be executed, so we need a trigger to flush the map to
  // prevent memory leaks.
  addEventListener('pageshow', function () {
    bridge.postMessage({
      secret: __wksecret__,
      name: '__wkreset__',
    });
  }, false);

  return {
    /**
     * Registers a handler to listen for messages from Swift.
     * Handler names must be unique; otherwise, existing handlers with the
     * given name will be overridden.
     *
     * @param {string} name The unique name of the handler.
     * @param {function} callback Function to execute when a message is
     *   received with this handler name.
     */
    addHandler: function (name, callback) {
      handlerMap[name] = callback;
    },

    /**
     * Posts a message to Swift.
     *
     * @param {string} name The name of the handler that should handle this message.
     * @param {object} data (optional) The data to send to the handler.
     */
    postMessage: function (name, data, sendResponse) {
      wkutils.print('posting message');

      responseMap[responseID] = sendResponse;

      bridge.postMessage({
        secret: __wksecret__,
        name: name,
        data: JSON.parse(JSON.stringify(data)),
        id: responseID,
      });

      responseID++;
    },

    /**
     * Prints a message in the iOS console.
     *
     * @param {object} data The data to print to the console.
     */
    print: function (data) {
      var string = (typeof(data) === "string") ? data : JSON.stringify(data);
      bridge.postMessage({
        secret: __wksecret__,
        name: '__wkprint__',
        data: '[Console] ' + string,
      });
    },

    /**
     * Callback executed for HTTP requests.
     *
     * @callback XHRCallback
     * @param {object} response The response object.
     * @param {number} response.status The HTTP status code of the response.
     * @param {string} response.mimeType The MIME type of the response.
     * @param {string} response.text The body text of the response.
     * @param {object} response.data The response data, which will be:
     *   - A Document object if the MIME type is an XML/HTML document (null on parse failure).
     *   - A JavaScript object if the MIME type is a JSON object (null on parse failure).
     *   - A string equal to response.text for all other cases.
     */

    /**
     * Perform a cross-origin HTTP request.
     *
     * @param {object} request The request object.
     * @param {string} request.url The URL of the resource to fetch.
     * @param {XHRCallback} request.complete The callback executed when the response is received.
     */
    xhr: function (request) {
      var data = {
        url: request.url,
      };

      wkutils.postMessage("__wkxhr__", data, function (response) {
        response.data = response.text;

        if (response.mimeType) {
          try {
            if (/html|xml/.test(response.mimeType)) {
              response.data = new DOMParser().parseFromString(response.text, response.mimeType);
            } else if (/json/.test(response.mimeType)) {
              response.data = JSON.parse(response.text);
            }
          } catch (e) {
            response.data = null;
            wkutils.print("Could not parse response data: " + response.text);
          }
        }

        request.complete(response);
      });
    },
  };
}) ();
