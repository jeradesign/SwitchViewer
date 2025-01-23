//
//  ViewController.swift
//  SwitchViewer
//
//  Created by John Brewer on 8/26/22.
//

import Cocoa
import AVFoundation

class ViewController: NSViewController {

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let layer = AVCaptureVideoPreviewLayer()
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    @objc dynamic var audioDeviceInput: AVCaptureDeviceInput!
    
    let audioOutput = AVCaptureAudioPreviewOutput()
    

    @IBOutlet private weak var previewView: NSView!
    
    // MARK: View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up the video preview view.
        
        layer.session = session
        previewView.layer = layer
        
        /*
         Check the video authorization status. Video access is required and audio
         access is optional. If the user denies audio access, AVCam won't
         record audio during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    print(changePrivacySetting)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    print(message)
                }
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        self.view.window?.isMovableByWindowBackground = true
    }
    
    override func viewWillDisappear() {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
        
        super.viewWillDisappear()
    }
    
    
    // MARK: Session Management
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
                
        var defaultVideoDevice: AVCaptureDevice?
        var defaultAudioDevice: AVCaptureDevice?
        
        // Add video input.
        do {
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            
            let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.externalUnknown, .builtInMicrophone], mediaType: nil, position: .unspecified)
            print(discoverySession.devices)

            for device in discoverySession.devices {
                print("---------------------------------------------")
                print("uniqueID = \(device.uniqueID)")
                print("modelID = \(device.modelID)")
                print("localizedName = \(device.localizedName)")
                print("manufacturer = \(device.manufacturer)")
                print("deviceType = \(device.deviceType)")
                print("hasMediaType(.audio) \(device.hasMediaType(.audio))")
                if device.localizedName.starts(with: "USB3. 0 capture") && device.hasMediaType(.video) {
                    defaultVideoDevice = device
                } else if device.localizedName.starts(with: "USB3. 0 capture") && device.hasMediaType(.audio) {
                    defaultAudioDevice = device
                }
            }
            
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
            guard let audioDevice = defaultAudioDevice else {
                print("Default audio device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
                self.audioDeviceInput = audioDeviceInput
                session.addOutput(audioOutput)
                audioOutput.volume = 1.0
            } else {
                print("Couldn't add audio device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
        } catch {
            print("Couldn't create device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    @IBAction private func resumeInterruptedSession(_ sender:NSView) {
        sessionQueue.async {
            /*
             The session might fail to start running, for example, if a phone or FaceTime call is still
             using audio or video. This failure is communicated by the session posting a
             runtime error notification. To avoid repeatedly failing to start the session,
             only try to restart the session in the error handler if you aren't
             trying to resume the session.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    print(message)
                }
            }
        }
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

