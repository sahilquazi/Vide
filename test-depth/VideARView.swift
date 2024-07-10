import CoreHaptics
import Foundation
import UIKit
import ARKit
import RealityKit
import SwiftUI
import Vision
import VisionKit
import CoreVideo
import Combine
import CoreML

@available(iOS 16.0, *)
class VideARView: ARView, ARSessionDelegate {
    
    var hapticsManager = HapticsManager()
    
    required init(frame frameRect: CGRect) {
        
        super.init(frame: frameRect)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        try? hapticsManager.continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        self.session.pause()
        print("SESSION WAS INTERRUPTED")
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        try? hapticsManager.continuousPlayer?.start(atTime: CHHapticTimeImmediate)
//        self.session.star
        print("SESSION INTERRUPTED ENDED")
    }
    
    required dynamic init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(textDisplayer: @escaping ((String) -> ()), speechRecognizer: SpeechRecognizer) {
        self.init(frame: UIScreen.main.bounds)
        self.textDisplayer = textDisplayer
        self.speechRecognizer = speechRecognizer
        configure()
        
        session.delegate = self
    }
    
    // MARK: Variables
    var handActionClassifierQueue = [MLMultiArray]()
    var frameCounter = 0
    var queueSamplingCounter = 0
    var queueSamplingCount = 25
    var queueSize = 30
    var handActionConfidenceThreshold = 0.5
    var viewportSize: CGSize!
    var lookingForObject: String? = nil
    var objectDetectionAnchor: AnchorEntity? = nil
    var textDisplayer: ((String) -> ())?
    var currentCentralDistance: Float = 9999.9
    var speechRecognizer: SpeechRecognizer?
    
    var objDetectionModeOn = false
    
    lazy var objectDetectionRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: YOLOv3_model().model)
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                self?.processDetections(for: request, error: error)
            }
            return request
        } catch {
            fatalError("Failed to load Vision ML model.")
        }
    }()
    
    
    func turnOffObjDetectionMode() {
        self.objDetectionModeOn = false
        textDisplayer?("")
        
    }
    
    func processDetections(for request: VNRequest, error: Error?) {
        guard error == nil else {
            print("Object detection error: \(error!.localizedDescription)")
            return
        }
        
        guard let results = request.results else { return }
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation,
                  let topLabelObservation = objectObservation.labels.first,
                  topLabelObservation.confidence > 0.7
            else { continue }
            
            guard let currentFrame = self.session.currentFrame else { continue }
            
            // Get the affine transform to convert between normalized image coordinates and view coordinates
            guard let fromCameraImageToViewTransform = self.session.currentFrame?.displayTransform(for: .portrait, viewportSize: self.viewportSize) else {
                print("No camera image transform available.")
                return
            }
            // The observation's bounding box in normalized image coordinates
            let boundingBox = objectObservation.boundingBox
            // Transform the latter into normalized view coordinates
            let viewNormalizedBoundingBox = boundingBox.applying(fromCameraImageToViewTransform)
            // The affine transform for view coordinates
            let t = CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height)
            // Scale up to view coordinates
            let viewBoundingBox = viewNormalizedBoundingBox.applying(t)
            
            let midPoint = CGPoint(x: viewBoundingBox.midX, y: viewBoundingBox.midY)
            
            let results = self.hitTest(midPoint, types: .featurePoint)
            guard let result = results.first else { continue }
            
            print("Found object detection result \(topLabelObservation)")
            
            let pointer = PointerFingerEntity(color: UIColor(Color(.yellow).opacity(0.4)))
            pointer.move(to: result.worldTransform, relativeTo: nil)
            self.scene.addAnchor(pointer)
            
            if let lookingForObjectU = lookingForObject {
                if topLabelObservation.identifier == lookingForObjectU {
                    objectDetectionAnchor = AnchorEntity()
                    objectDetectionAnchor?.move(to: result.worldTransform, relativeTo: nil)
                    textDisplayer?("Locked on and looking for object")
                    self.speechRecognizer?.speak("In sight")
                    lookingForObject = nil
                }
            }
        }
    }
    
    var beginSub: Cancellable?
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
  
        
        if objDetectionModeOn {
            runObjectDetection(session: session, frame: frame)
            self.hapticsManager.proximityWarningOn = false
//            try? self.hapticsManager.continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
            print("being objective")
        } else {
            print("being passive")
            passiveSpatialAwareness(session: session, frame: frame)
        }
    }
    
    func passiveSpatialAwareness(session: ARSession, frame: ARFrame) {
        // Perform a raycast from the center of the screen
        let ray = self.raycast(from: CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY), allowing: .estimatedPlane, alignment: .any)
        
        // Filter the raycast results
        
        if let rayFirstRes = ray.first {
            let anchorPosition = rayFirstRes.worldTransform.columns.3
            let cameraPosition = self.cameraTransform.matrix.columns.3
            
            // Calculate the vector from the camera to the anchor
            let cameraToAnchor = cameraPosition - anchorPosition
            
            // Calculate the scalar distance
            self.currentCentralDistance = length(cameraToAnchor)
//            print("Distance from raycast: \(self.currentCentralDistance)")
            // and here’s just the scalar distance
            let linearizedValue = 0.9 -  Double(self.currentCentralDistance.normalize(from: 0...3, to: 0...0.9))
            print("raycast: \(self.currentCentralDistance), linearized: \(linearizedValue), normalize: \(normalizeValue(linearizedValue))")
            self.hapticsManager.sendContinuousHaptic(value: (linearizedValue))
            
            if (self.currentCentralDistance < 0.5) {
                print("sending proximity warn")
                self.hapticsManager.proximityWarningOn = true
            } else {
                self.hapticsManager.proximityWarningOn = false
            }
            
        }
    }
    
    func runObjectDetection(session: ARSession, frame: ARFrame) {
        if frameCounter % 30 == 0 && lookingForObject != nil {
            if let sceneDepth = frame.sceneDepth {
                // Optional: process sceneDepth
            }
            do {
                let pixelBuffer = frame.capturedImage
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([objectDetectionRequest])
            } catch {
                assertionFailure("Object Detection Request failed: \(error)")
            }
        }
        
        if objectDetectionAnchor != nil {
            if let selfTransform = session.currentFrame?.camera.transform {
                let cameraAnchor = Entity()
                cameraAnchor.move(to: self.cameraTransform, relativeTo: nil)
                
                objectDetectionAnchor?.look(at: cameraAnchor.position, from: objectDetectionAnchor!.position, relativeTo: nil)
                guard let camPointObjRot = objectDetectionAnchor?.transformMatrix(relativeTo: nil).eulerAngles else {
                    print("No camera point object rotation")
                    return
                }
                
                guard let cameraCurrentRot = self.session.currentFrame?.camera.eulerAngles else {
                    print("No camera rotation")
                    return
                }
                
                let linearizedValue = (abs(Double(diffInRads(camPointObjRot.y, cameraCurrentRot.y))) + abs(Double(diffInRads(camPointObjRot.x, cameraCurrentRot.x)))).normalize(from: 0.0...(Double.pi + Double.pi / 2), to: 0.0...1.0)
                self.hapticsManager.sendContinuousHaptic(value: normalizeValue(linearizedValue))
            }
        }
    }
    
    public func setObjectDetectionTarget(target: String) {
        self.speechRecognizer?.speak("looking for \(target)")
        self.lookingForObject = target
        self.objDetectionModeOn = true
        
    }
    
    func configure() {
        self.viewportSize = UIScreen.main.bounds.size
        
        hapticsManager.startEngine()
        let config = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        } else {
            print("A requested frame semantic from ARKit is unsupported.")
        }
        
        config.planeDetection = [.horizontal, .vertical]
        
        // Remove as many rendering options as possible to keep lightweight
        self.renderOptions = .disableMotionBlur
        self.renderOptions.insert(.disableDepthOfField)
        self.renderOptions.insert(.disableMotionBlur)
        self.renderOptions.insert(.disableHDR)
        self.renderOptions.insert(.disableAREnvironmentLighting)
        self.renderOptions.insert(.disableGroundingShadows)
        
        session.run(config)
    }
    
    private func createPlaneEntity(anchor: ARPlaneAnchor) -> AnchorEntity {
        let plane = MeshResource.generatePlane(width: Float(CGFloat(anchor.extent.x)), depth: Float(CGFloat(anchor.extent.z)))
        var material = UnlitMaterial()
            material.color = .init(tint: .yellow.withAlphaComponent(0.5))
        let planeModel = ModelEntity(mesh: plane, materials: [material])
        planeModel.position = SIMD3(anchor.center.x, 0, anchor.center.z)
        planeModel.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        
        let planeAnchorEntity = AnchorEntity(anchor: anchor)
        planeAnchorEntity.addChild(planeModel)
        
        return planeAnchorEntity
    }
}

func normalizeValue(_ value: Double) -> Double {
    // Ensure value is within the range [0, 1]
    let clampedValue = max(0, min(1, value))
    // Apply the exponential transformation
    return pow(clampedValue, 3)
}

extension simd_float4x4 {
    var eulerAngles: simd_float3 {
        simd_float3(
            x: asin(-self[2][1]),
            y: atan2(self[2][0], self[2][2]),
            z: atan2(self[0][1], self[1][1])
        )
    }
}

func diffInRads(_ rad1: Float, _ rad2: Float) -> Float {
    var diff = rad1 - rad2
    while diff > .pi {
        diff -= 2 * .pi
    }
    while diff < -.pi {
        diff += 2 * .pi
    }
    return diff
}

extension FloatingPoint {
    func normalize(from: ClosedRange<Self>, to: ClosedRange<Self>) -> Self {
        return (self - from.lowerBound) / (from.upperBound - from.lowerBound) * (to.upperBound - to.lowerBound) + to.lowerBound
    }
}

