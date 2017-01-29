/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	Photo capture delegate.
 */

import AVFoundation
import Photos

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> ()
    
    private let capturingLivePhoto: (Bool) -> ()
    
    private let completed: (PhotoCaptureDelegate) -> ()
    
    private var photoData: Data? = nil
    
    var CapturedPhotoData: Data? {
        get {
            return photoData
        }
        set {
            photoData = newValue
        }
    }
    
    
    private var livePhotoCompanionMovieURL: URL? = nil
    
    init(with requestedPhotoSettings: AVCapturePhotoSettings, willCapturePhotoAnimation: @escaping () -> (), capturingLivePhoto: @escaping (Bool) -> (), completed: @escaping (PhotoCaptureDelegate) -> ()) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.capturingLivePhoto = capturingLivePhoto
        self.completed = completed
    }
    
    private func didFinish() {
        if let livePhotoCompanionMoviePath = livePhotoCompanionMovieURL?.path {
            if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
                do {
                    try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
                }
                catch {
                }
            }
        }
        
        completed(self)
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, willBeginCaptureForResolvedSettings resolvedSettings: AVCaptureResolvedPhotoSettings) {
        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
            capturingLivePhoto(true)
        }
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, willCapturePhotoForResolvedSettings resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        if let photoSampleBuffer = photoSampleBuffer {
            photoData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer)
        }
        else {
            return
        }
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        capturingLivePhoto(false)
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplay photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let _ = error {
            return
        }
        
        livePhotoCompanionMovieURL = outputFileURL
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishCaptureForResolvedSettings resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil {
            didFinish()
            return
        }
        
        guard let photoData = photoData else {
            didFinish()
            return
        }
        
        PHPhotoLibrary.requestAuthorization { [unowned self] status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({ [unowned self] in
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: photoData, options: nil)
                    
                    //performSegue(withIdentifier: "UsersVC", sender: ["videoURL": photoData])
                    
                    
                    if let livePhotoCompanionMovieURL = self.livePhotoCompanionMovieURL {
                        let livePhotoCompanionMovieFileResourceOptions = PHAssetResourceCreationOptions()
                        livePhotoCompanionMovieFileResourceOptions.shouldMoveFile = true
                        creationRequest.addResource(with: .pairedVideo, fileURL: livePhotoCompanionMovieURL, options: livePhotoCompanionMovieFileResourceOptions)
                    }
                    
                    }, completionHandler: { [unowned self] success, error in
                        if error != nil {
                        }
                        
                        self.didFinish()
                    }
                )
            }
            else {
                self.didFinish()
            }
        }
    }
}
