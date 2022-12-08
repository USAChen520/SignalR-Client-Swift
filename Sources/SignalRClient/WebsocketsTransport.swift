//
//  WebsocketsTransport.swift
//  SignalRClient
//
//  Created by Pawel Kadluczka on 2/23/17.
//  Copyright © 2017 Pawel Kadluczka. All rights reserved.
//

import Foundation

@available(OSX 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public class WebsocketsTransport: NSObject, Transport, URLSessionWebSocketDelegate {
    private let logger: Logger
    private let dispatchQueue = DispatchQueue(label: "SignalR.webSocketTransport.queue")
    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?

    private var isTransportClosed = false

    public var delegate: TransportDelegate?
    public let inherentKeepAlive = false

    init(logger: Logger) {
        self.logger = logger
    }
    deinit {
        self.delegate = nil
        self.close()
        print("销毁 WebsocketsTransport")
    }

    public func start(url: URL, options: HttpConnectionOptions) {
        logger.log(logLevel: .info, message: "Starting WebSocket transport")

        guard let url = convertUrl(url: url) else {
            delegate?.transportDidClose(nil)
            return }
        var request = URLRequest(url: url)
        populateHeaders(headers: options.headers, request: &request)
        setAccessToken(accessTokenProvider: options.accessTokenProvider, request: &request)
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = urlSession!.webSocketTask(with: request)
        webSocketTask!.resume()
    }

    public func send(data: Data, sendDidComplete: @escaping (Error?) -> Void) {
        if let webSocketTask = webSocketTask {
            let message = URLSessionWebSocketTask.Message.data(data)
            webSocketTask.send(message, completionHandler: sendDidComplete)
        }
    }
    public func sendPing(data: Data, sendDidComplete: @escaping (Error?) -> Void) {
        if let webSocketTask = webSocketTask {
            webSocketTask.sendPing { error in
                sendDidComplete(error)
            }
        }
    }
//    public func sendPing(sendDidComplete: @escaping (Error?) -> Void) {
//
//    }

    public func close() {
        if urlSession != nil {
            urlSession!.finishTasksAndInvalidate()
            urlSession = nil
        }
        if webSocketTask != nil {
            webSocketTask!.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.log(logLevel: .info, message: "WebSocket open")
        delegate?.transportDidOpen()
        readMessage()
    }

    private func readMessage()  {
        webSocketTask?.receive {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                // This failure always occurs when the task is cancelled. If the code
                // is not normalClosure this is a real error.
                if self.webSocketTask?.closeCode != .normalClosure {
                    self.handleError(error: error)
                }
            case .success(let message):
                self.handleMessage(message: message)
                self.readMessage()
            }
        }
    }

    private func handleMessage(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            delegate?.transportDidReceiveData(text.data(using: .utf8)!)
        case .data(let data):
            delegate?.transportDidReceiveData(data)
        @unknown default:
            fatalError()
        }
    }

    private func handleError(error: Error) {
        logger.log(logLevel: .info, message: "WebSocket error. Error: \(error). Websocket status: \(webSocketTask?.state.rawValue ?? -1)")
        // This handler should not be called after the close event but we need to mark the transport as closed to prevent calling transportDidClose
        // on the delegate multiple times so we can as well add the check and log
        guard !markTransportClosed() else {
            logger.log(logLevel: .debug, message: "Transport already marked as closed - ignoring error. (handleError)")
            return
        }
        delegate?.transportDidClose(error)
        shutdownTransport()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else {
            // As per docs: "Error may be nil, which implies that no error occurred and this task is complete."
            return
        }

        guard !markTransportClosed() else {
            logger.log(logLevel: .debug, message: "Transport already marked as closed - ignoring error. (didCompleteWithError)")
            return
        }

        let statusCode = (webSocketTask?.response as? HTTPURLResponse)?.statusCode ?? -1
        logger.log(logLevel: .info, message: "Error starting webSocket. Error: \(error!), HttpStatusCode: \(statusCode), WebSocket closeCode: \(webSocketTask?.closeCode.rawValue ?? -1)")
        delegate?.transportDidClose(error)
        shutdownTransport()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var reasonString = ""
        if let reason = reason {
            reasonString = String(decoding: reason, as: UTF8.self)
        }
        logger.log(logLevel: .info, message: "WebSocket close. Code: \(closeCode.rawValue), reason: \(reasonString)")

        // the transport could have already been closed as a result of an error. In this case we should not call
        // transportDidClose again on the delegate.
        guard !markTransportClosed() else {
            logger.log(logLevel: .debug, message: "Transport already marked as closed due to an error - ignoring close. (didCloseWith)")
            return
        }

        if closeCode == .normalClosure {
            delegate?.transportDidClose(nil)
        } else {
            delegate?.transportDidClose(WebSocketsTransportError.webSocketClosed(statusCode: closeCode.rawValue, reason: reasonString))
        }
    }

    private func markTransportClosed() -> Bool {
        logger.log(logLevel: .debug, message: "Marking transport as closed.")
        var previousCloseStatus = false
        dispatchQueue.sync {
            previousCloseStatus = isTransportClosed
            isTransportClosed = true
        }
        return previousCloseStatus
    }

    private func shutdownTransport() {
        urlSession?.finishTasksAndInvalidate()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
    }

    private func convertUrl(url: URL?) -> URL? {
        guard let url = url else { return nil }
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
