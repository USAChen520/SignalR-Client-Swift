//
//  WebsocketsTransport.swift
//  SignalRClient
//
//  Created by Pawel Kadluczka on 2/23/17.
//  Copyright © 2017 Pawel Kadluczka. All rights reserved.
//

import Foundation
import SocketRocket

extension WebsocketsTransport: SRWebSocketDelegate {
    public func webSocketDidOpen(_ webSocket: SRWebSocket) {
        print("Connected")
        delegate?.transportDidOpen()
    }
    public func webSocket(_ webSocket: SRWebSocket, didReceiveMessage message: Any) {
        if let msg = message as? String {
            delegate?.transportDidReceiveData(msg.data(using: .utf8)!)
        } else if let msg = message as? Data {
            delegate?.transportDidReceiveData(msg)
        }
    }
    public func webSocket(_ webSocket: SRWebSocket, didFailWithError error: Error) {
        
        if let nserror = error as? NSError {
            let dict = nserror.userInfo
            if let responseCode = dict["HTTPResponseStatusCode"] as? Int {
                delegate?.transportDidClose(SignalRError.webError(statusCode: responseCode))
                close()
                return
            }
        }
        delegate?.transportDidClose(error)
        close()
#if DEBUG
        print("webSocket_didFailWithError：\(error)")
#endif
    }
    public func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        delegate?.transportDidClose(SignalRError.connectionIsBeingClosed)
        close()
#if DEBUG
        print("webSocket_didCloseWithCode：\(code)")
#endif
    }
}

public class WebsocketsTransport: NSObject, Transport, URLSessionWebSocketDelegate {
    private let logger: Logger
    public var delegate: TransportDelegate?
    public let inherentKeepAlive = false
    var socket: SRWebSocket?
    init(logger: Logger) {
        self.logger = logger
    }
    
    public func start(url: URL, options: HttpConnectionOptions) {
        logger.log(logLevel: .info, message: "Starting WebSocket transport")
        var request = URLRequest(url: convertUrl(url: url))
        populateHeaders(headers: options.headers, request: &request)
        setAccessToken(accessTokenProvider: options.accessTokenProvider, request: &request)
        
        if self.socket != nil {
            self.close()
        }
        self.socket = SRWebSocket(urlRequest: request)
        self.socket!.delegate = self
        self.socket!.open()
    }

    public func send(data: Data, sendDidComplete: @escaping (Error?) -> Void) {
        
        if let socket = socket {
            do {
                try socket.send(data: data)
                sendDidComplete(nil)
            } catch  {
                sendDidComplete(error)
            }
        }
    }
    public func sendPing(data: Data, sendDidComplete: @escaping (Error?) -> Void) {
        if let socket = socket {
            do {
                try socket.sendPing(data)
                sendDidComplete(nil)
            } catch {
                sendDidComplete(error)
            }
        }
    }

    public func close() {
        socket?.delegate = nil
        socket?.close()
        socket = nil
    }

    private func convertUrl(url: URL) -> URL {
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if (components.scheme == "http") {
                components.scheme = "ws"
            } else if (components.scheme == "https") {
                components.scheme = "wss"
            }
            return components.url!
        }
        return url
    }

    @inline(__always) private func populateHeaders(headers: [String : String], request: inout URLRequest) {
        headers.forEach { (key, value) in
            request.addValue(value, forHTTPHeaderField: key)
        }
    }

    @inline(__always) private func setAccessToken(accessTokenProvider: () -> String?, request: inout URLRequest) {
        if let accessToken = accessTokenProvider() {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }
}

fileprivate enum WebSocketsTransportError: Error {
    case webSocketClosed(statusCode: Int, reason: String)
}
