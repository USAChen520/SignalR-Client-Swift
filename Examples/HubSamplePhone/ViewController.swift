//
//  ViewController.swift
//  HubSamplePhone
//
//  Created by Pawel Kadluczka on 2/11/18.
//  Copyright © 2018 Pawel Kadluczka. All rights reserved.
//

import UIKit
import SignalRClient

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    // Update the Url accordingly
//    private let serverUrl = "http://192.168.100.5:5000/chat"  // /chat or /chatLongPolling or /chatWebSockets
    
    private let serverUrl = "https://zdcr-test.esccall.com/hubs/notification"
    
    private let dispatchQueue = DispatchQueue(label: "hubsamplephone.queue.dispatcheueuq")

    private var chatHubConnection: HubConnection?
    private var chatHubConnectionDelegate: HubConnectionDelegate?
    private var name = ""
    private var messages: [String] = []
    private var reconnectAlert: UIAlertController?

    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var chatTableView: UITableView!
    @IBOutlet weak var msgTextField: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        self.chatTableView.delegate = self
        self.chatTableView.dataSource = self
        self.chatHubConnectionDelegate = ChatHubConnectionDelegate(controller: self)
        let buttn = UIButton(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        self.view.addSubview(buttn)
        buttn.backgroundColor = UIColor.red
        buttn.addTarget(self, action: #selector(didAction), for: UIControl.Event.touchUpInside)
    }
    @objc
    func didAction() {
        messages.removeAll()
        self.reConnect()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let alert = UIAlertController(title: "Enter your Name", message:"", preferredStyle: UIAlertController.Style.alert)
        let OKAction = UIAlertAction(title: "OK", style: .default) {[weak self] action in
            guard let self = self else { return }
            self.reConnect()
        }
        alert.addAction(OKAction)
        self.present(alert, animated: true)
    }
    
    public func reConnect() {
        self.name = "John Doe"
        
        self.chatHubConnection = HubConnectionBuilder(url: URL(string: self.serverUrl)!)
            .withHubConnectionDelegate(delegate: self.chatHubConnectionDelegate!)
            .withPermittedTransportTypes(.webSockets)
            .withHttpConnectionOptions(configureHttpOptions: { httpConnectionOptions in
                httpConnectionOptions.skipNegotiation = true
                httpConnectionOptions.accessTokenProvider = {
                    return "eyJhbGciOiJSUzI1NiIsImtpZCI6Ijk2YjM1ZDJiMjM0NjhhMjhhY2NkNTY0Yzg0ZDgyMmI1IiwidHlwIjoiSldUIn0.eyJuYmYiOjE2NzA0ODc4NTMsImV4cCI6MTY3MTA5MjY1MywiaXNzIjoiaHR0cDovL3EtemQtaWRlbnRpdHlzZXJ2ZXIuemRjaGF0cm9vbSIsImF1ZCI6WyJodHRwOi8vcS16ZC1pZGVudGl0eXNlcnZlci56ZGNoYXRyb29tL3Jlc291cmNlcyIsImFncCJdLCJjbGllbnRfaWQiOiJaZC5BR2FtZVBsYXRmb3JtLkFwaSIsInN1YiI6ImlvczEyMCIsImF1dGhfdGltZSI6MTY3MDQ4Nzg1MywiaWRwIjoibG9jYWwiLCJNZXJjaGFudElkIjoiOSIsIlNpZ25OYW1lIjoiaW9zMTIwIiwic2NvcGUiOlsiYWdwIiwib2ZmbGluZV9hY2Nlc3MiXSwiYW1yIjpbInBhc3N3b3JkIl19.e242alJ-eXvDP3XkswTx8S1Zj_QCh1EsIUMAMTMbeiBOvhUQMIXYeOF1K2AnbKArGw9A-U02vNmc9wfhOCUCg00rnit8nLYSCv4J3l7z84r8p4t0LBwwB5A4VKXiGO1KQPECqeevDV43ue0t6VGVpu89HqFL9wS4U_kygQkhvzms2feAJkjRxCxluNHaxFBGf0hzU3llsAttebB2G4h7_CdmqYLDz7S3bfHRnU5M2UrNtLIR4FRhljvtTMtmawlhyNfrfJ1Z2P-flxls9pjb8yOB82PF6ssy09jnjDw0sjgKxZ2dFPq-K4sOMrAH18Z9I8MyEhgGe0pRfajXr4fqyg"
                }
            }).withLogging(minLogLevel: .debug)
            .build()

        self.chatHubConnection!.on(method: "NewMessage", callback: {[weak self](user: String, message: String) in
            guard let self = self else { return }
            self.appendMessage(message: "\(user): \(message)")
        })
        self.chatHubConnection!.start()
    }
    

    override func viewWillDisappear(_ animated: Bool) {
        chatHubConnection?.stop()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    @IBAction func btnSend(_ sender: Any) {
        let message = msgTextField.text
        if message != "" {
            chatHubConnection?.invoke(method: "Broadcast", name, message) {[weak self] error in
                guard let self = self else { return }
                if let e = error {
                    self.appendMessage(message: "Error: \(e)")
                }
            }
            msgTextField.text = ""
        }
    }

    private func appendMessage(message: String) {
     
        DispatchQueue.main.async {
            

            self.messages.append(message)
            self.chatTableView.reloadData()
        }

        
    }

    fileprivate func connectionDidOpen() {
        toggleUI(isEnabled: true)
    }

    fileprivate func connectionDidFailToOpen(error: Error) {
        reConnect()
        blockUI(message: "Connection failed to start.", error: error)
    }

    fileprivate func connectionDidClose(error: Error?) {
        if let alert = reconnectAlert {
            alert.dismiss(animated: true, completion: nil)
        }
        reConnect()
        blockUI(message: "Connection is closed.", error: error)
    }

    fileprivate func connectionWillReconnect(error: Error?) {
        guard reconnectAlert == nil else {
            print("Alert already present. This is unexpected.")
            return
        }

        reconnectAlert = UIAlertController(title: "Reconnecting...", message: "Please wait", preferredStyle: .alert)
        self.present(reconnectAlert!, animated: true, completion: nil)
    }

    fileprivate func connectionDidReconnect() {
        reconnectAlert?.dismiss(animated: true, completion: nil)
        reconnectAlert = nil
    }

    func blockUI(message: String, error: Error?) {
        var message = message
        if let e = error {
            message.append(" Error: \(e)")
        }
        appendMessage(message: message)
        toggleUI(isEnabled: false)
    }

    func toggleUI(isEnabled: Bool) {
        sendButton.isEnabled = isEnabled
        msgTextField.isEnabled = isEnabled
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TextCell", for: indexPath)
        let row = indexPath.row
        cell.textLabel?.text = messages[row]
        return cell
    }
}

class ChatHubConnectionDelegate: HubConnectionDelegate {

    weak var controller: ViewController?

    init(controller: ViewController) {
        self.controller = controller
    }

    func connectionDidOpen(hubConnection: HubConnection) {
        controller?.connectionDidOpen()
    }

    func connectionDidFailToOpen(error: Error) {
        controller?.connectionDidFailToOpen(error: error)
    }

    func connectionDidClose(error: Error?) {
        controller?.connectionDidClose(error: error)
    }

    func connectionWillReconnect(error: Error) {
        controller?.connectionWillReconnect(error: error)
    }

    func connectionDidReconnect() {
        controller?.connectionDidReconnect()
    }
}
