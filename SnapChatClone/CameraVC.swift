/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	View controller for camera interface.
 */

import UIKit
import AVFoundation
import Photos
import AVKit


class CameraVC: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    var outputURL: String = ""
    var CapturedPhotoData: Data? = nil
    var VideoMode: Bool = false
    
    @IBOutlet private weak var previewView: PreviewView!
    @IBOutlet weak var btnTakePhoto: UIButton!
    
    private var sessionRunningObserveContext = 0
    private var isSessionRunning = false
    private var inProgressLivePhotoCapturesCount = 0
    private var movieFileOutput: AVCaptureMovieFileOutput? = nil
    private var setupResult: SessionSetupResult = .success
    private var backgroundRecordingID: UIBackgroundTaskIdentifier? = nil
    
    var playerLayer: AVPlayerLayer? = nil
    var videoDeviceInput: AVCaptureDeviceInput!
    var RecordingImage: String = "video"
    var RecordingVideo: Bool = false
    
    
    
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil) // Communicate with the session and other session objects on this queue.
    
    @IBAction func TakePhoto() {
        capturePhoto()
    }
    
    
    @IBAction func btnStartRecording() {
        if RecordingVideo == true {
            RecordingVideo = false
        }
        else {
            RecordingVideo = true
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        
        // Set up the video preview view.
        previewView.session = session
        
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        sessionQueue.async { [unowned self] in
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("This Application doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "SnapClone", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { action in
                        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "SnapClone", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = deviceOrientation.videoOrientation, deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }
            
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    
    // Call this on the session queue.
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = AVCaptureSessionPresetPhoto
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera if available, otherwise default to a wide angle camera.
            if let dualCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInDualCamera, mediaType: AVMediaTypeVideo, position: .back) {
                defaultVideoDevice = dualCameraDevice
            }
            else if let backCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back) {
                // If the back dual camera is not available, default to the back wide angle camera.
                defaultVideoDevice = backCameraDevice
            }
            else if let frontCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .front) {
                // In some cases where users break their phones, the back wide angle camera is not available. In this case, we should default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    let statusBarOrientation = UIApplication.shared.statusBarOrientation
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if statusBarOrientation != .unknown {
                        if let videoOrientation = statusBarOrientation.videoOrientation {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation
                }
            }
            else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        }
        catch {
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add audio input.
        do {
            let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            }
        }
        catch {
        }
        
        // Add photo output.
        if session.canAddOutput(photoOutput)
        {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        }
        else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton)
    {
        sessionQueue.async { [unowned self] in
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
            else {
                
            }
        }
    }
    
    private enum CaptureMode: Int {
        case photo = 0
        case movie = 1
    }
    
    //@IBOutlet private weak var captureModeControl: UISegmentedControl!
    
    func toggleCaptureMode(isPhoto: Bool) {
        if isPhoto {
            //recordButton.isEnabled = false
            
            sessionQueue.async { [unowned self] in
                
                self.session.beginConfiguration()
                self.session.removeOutput(self.movieFileOutput)
                self.session.sessionPreset = AVCaptureSessionPresetPhoto
                self.session.commitConfiguration()
                
                self.movieFileOutput = nil
                
                if self.photoOutput.isLivePhotoCaptureSupported {
                    self.photoOutput.isLivePhotoCaptureEnabled = true
                    DispatchQueue.main.async {
                    }
                }
            }
        }
        else
        {
            sessionQueue.async { [unowned self] in
                let movieFileOutput = AVCaptureMovieFileOutput()
                
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.beginConfiguration()
                    self.session.addOutput(movieFileOutput)
                    self.session.sessionPreset = AVCaptureSessionPresetHigh
                    if let connection = movieFileOutput.connection(withMediaType: AVMediaTypeVideo) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    self.session.commitConfiguration()
                    
                    self.movieFileOutput = movieFileOutput
                    
                }
            }
        }
    }
    
    private let videoDeviceDiscoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera], mediaType: AVMediaTypeVideo, position: .unspecified)!
    
    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        sessionQueue.async { [unowned self] in
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice!.position
            
            let preferredPosition: AVCaptureDevicePosition
            let preferredDeviceType: AVCaptureDeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
                
            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInWideAngleCamera
            }
            
            let devices = self.videoDeviceDiscoverySession.devices!
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, look for a device with both the preferred position and device type. Otherwise, look for a device with only the preferred position.
            if let device = devices.filter({ $0.position == preferredPosition && $0.deviceType == preferredDeviceType }).first {
                newVideoDevice = device
            }
            else if let device = devices.filter({ $0.position == preferredPosition }).first {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: currentVideoDevice!)
                        
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    }
                    else {
                        self.session.addInput(self.videoDeviceInput);
                    }
                    
                    if let connection = self.movieFileOutput?.connection(withMediaType: AVMediaTypeVideo) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    
                    self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported;
                    
                    self.session.commitConfiguration()
                }
                catch {
                }
            }
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = self.previewView.videoPreviewLayer.captureDevicePointOfInterest(for: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureFocusMode, exposureMode: AVCaptureExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async { [unowned self] in
            if let device = self.videoDeviceInput.device {
                do {
                    try device.lockForConfiguration()
                    
                    if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusPointOfInterest = devicePoint
                        device.focusMode = focusMode
                    }
                    
                    if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                        device.exposurePointOfInterest = devicePoint
                        device.exposureMode = exposureMode
                    }
                    
                    device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                    device.unlockForConfiguration()
                }
                catch {
                }
            }
        }
    }
    
    // MARK: Capturing Photos
    
    
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64 : PhotoCaptureDelegate]()
    
    //@IBOutlet private weak var photoButton: UIButton!
    
    @IBAction private func capturePhoto() {
        
        toggleCaptureMode(isPhoto: true)
        
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection.videoOrientation
        
        sessionQueue.async {
            // Update the photo output's connection to match the video orientation of the video preview layer.
            if let photoOutputConnection = self.photoOutput.connection(withMediaType: AVMediaTypeVideo) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation
            }
            
            // Capture a JPEG photo with flash set to auto and high resolution photo enabled.
            let photoSettings = AVCapturePhotoSettings()
            if self.videoDeviceInput.device.position == .front {
                photoSettings.flashMode = .off
            } else {
                photoSettings.flashMode = .auto
            }
            
            let model = UIDevice.current.model
            
            if model.lowercased() == "ipad" {
                photoSettings.flashMode = .off
            }
            photoSettings.isHighResolutionPhotoEnabled = true
            if photoSettings.availablePreviewPhotoPixelFormatTypes.count > 0 {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String : photoSettings.availablePreviewPhotoPixelFormatTypes.first!]
            }
            // Use a separate object for the photo capture delegate to isolate each capture life cycle.
            let photoCaptureDelegate = PhotoCaptureDelegate(with: photoSettings, willCapturePhotoAnimation: {
                DispatchQueue.main.async { [unowned self] in
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) { [unowned self] in
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, capturingLivePhoto: { capturing in
                
                self.sessionQueue.async { [unowned self] in
                    if capturing {
                        self.inProgressLivePhotoCapturesCount += 1
                    }
                    else {
                        self.inProgressLivePhotoCapturesCount -= 1
                    }
                    
                    let inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount
                    DispatchQueue.main.async { [unowned self] in
                        if inProgressLivePhotoCapturesCount > 0 {
                            //self.capturingLivePhotoLabel.isHidden = false
                        }
                        else if inProgressLivePhotoCapturesCount == 0 {
                            //self.capturingLivePhotoLabel.isHidden = true
                        }
                    }
                }
            }, completed: { [unowned self] photoCaptureDelegate in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        
                        // Save the movie file to the photo library and cleanup.
                        //self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID].
                        //
                    }
                }
                
                self.sessionQueue.async { [unowned self] in
                    self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = nil
                    if let photodata = photoCaptureDelegate.CapturedPhotoData {
                        self.VideoMode = false
                        self.CapturedPhotoData = photoCaptureDelegate.CapturedPhotoData
                    }
                }
                }
            )
            
            self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = photoCaptureDelegate
            
            photoSettings.flashMode = .off
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureDelegate)
        }
    }
    
    private enum LivePhotoMode {
        case on
        case off
    }
    
    
    @IBAction private func toggleMovieRecording(_ recordButton: UIImageView) {
        toggleCaptureMode(isPhoto: false)
        
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection.videoOrientation
        
        sessionQueue.async { [unowned self] in
            if !(self.movieFileOutput?.isRecording)! {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieFileOutputConnection = self.movieFileOutput?.connection(withMediaType: AVMediaTypeVideo)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation
                
                // Start recording to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                self.movieFileOutput?.startRecording(toOutputFileURL: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            }
            else {
                self.movieFileOutput?.stopRecording()
            }
        }
    }
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
        // Enable the Record button to let the user stop the recording.
        DispatchQueue.main.async { [unowned self] in
            //self.recordButton.isEnabled = true
            //self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), for: [])
        }
    }
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        /*
         Note that currentBackgroundRecordingID is used to end the background task
         associated with this recording. This allows a new recording to be started,
         associated with a new UIBackgroundTaskIdentifier, once the movie file output's
         `isRecording` property is back to false — which happens sometime after this method
         returns.
         
         Note: Since we use a unique file path for each recording, a new recording will
         not overwrite a recording currently being saved.
         */
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                }
                catch {
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskInvalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            success = (((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success {
            //performSegue(withIdentifier: "UsersVC", sender: ["mediaURL": outputFileURL.absoluteString])
            VideoMode = true
            
            SetupCapturedVideoPreview(videoURL: outputFileURL.absoluteString)
        }
        else {
            
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async { [unowned self] in
        }
    }
    
    private func addObservers() {
        session.addObserver(self, forKeyPath: "running", options: .new, context: &sessionRunningObserveContext)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: Notification.Name("AVCaptureSessionRuntimeErrorNotification"), object: session)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sesrsionInterruptionEnded), name: Notification.Name("AVCaptureSessionInterruptionEndedNotification"), object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunningObserveContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &sessionRunningObserveContext {
            let newValue = change?[.newKey] as AnyObject?
            guard let isSessionRunning = newValue?.boolValue else { return }
            
            DispatchQueue.main.async { [unowned self] in
                //self.photoButton.isUserInteractionEnabled = isSessionRunning
            }
        }
        else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .autoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async { [unowned self] in
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
                else {
                    DispatchQueue.main.async { [unowned self] in
                        
                    }
                }
            }
        }
        else {
            
        }
    }
    
    func sessionWasInterrupted(notification: NSNotification) {
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reasonIntegerValue = userInfoValue.integerValue, let reason = AVCaptureSessionInterruptionReason(rawValue: reasonIntegerValue) {
            
            //var showResumeButton = false
            
            if reason == AVCaptureSessionInterruptionReason.audioDeviceInUseByAnotherClient || reason == AVCaptureSessionInterruptionReason.videoDeviceInUseByAnotherClient {
                //showResumeButton = true
            }
            else if reason == AVCaptureSessionInterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps {
                UIView.animate(withDuration: 0.25) { [unowned self] in
                }
            }
        }
    }
    
    func sesrsionInterruptionEnded(notification: NSNotification) {
        
    }
    
    func SetupCapturedVideoPreview(videoURL: String) {
        let videoURL = NSURL(string: videoURL)
        let player = AVPlayer(url: videoURL! as URL)
        
        playerLayer = AVPlayerLayer(player: player)
        self.view.layer.addSublayer(playerLayer!)
        player.isMuted = true
        player.play()
        
    }
    
    func RemoveCapturedVideoPreview() {
        toggleCaptureMode(isPhoto: true)
        playerLayer?.removeFromSuperlayer()
    }
    
}


