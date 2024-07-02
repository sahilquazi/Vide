//
//  VideARView.swift
//  test-depth
//
//  Created by Ryan Du on 6/24/24.
//


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
    
    required dynamic init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(textDisplayer: @escaping ((String)->())) {
        self.init(frame: UIScreen.main.bounds)
        self.textDisplayer = textDisplayer
        
        configure()
        
        session.delegate = self
    }
    
    //MARK: Variables
    var handActionClassifierQueue = [MLMultiArray]()
    var frameCounter = 0
    var queueSamplingCounter = 0
    var queueSamplingCount = 25
    var queueSize = 30
    var handActionConfidenceThreshold = 0.5
    var viewportSize: CGSize!
    var lookingForObject: String? = "keyboard"
    var objectDetectionAnchor: AnchorEntity? = nil
    var textDisplayer: ((String) -> ())?
    var currentCentralDistance: Float = 9999.9
    
    
    
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
    
    func processDetections(for request: VNRequest, error: Error?) {
        guard error == nil else {
            print("Object detection error: \(error!.localizedDescription)")
            return
        }
        
        guard let results = request.results else { return }
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation,
                  let topLabelObservation = objectObservation.labels.first,
//                  topLabelObservation.identifier == "remote",
                  topLabelObservation.confidence > 0.9
            else { continue }
            
            guard let currentFrame = self.session.currentFrame else { continue }
            
            // Get the affine transform to convert between normalized image coordinates and view coordinates
            guard let fromCameraImageToViewTransform = self.session.currentFrame?.displayTransform(for: .portrait, viewportSize: self.viewportSize) else {
                print("no camrea from image transform thing")
                return
            }
            // The observation's bounding box in normalized image coordinates
            let boundingBox = objectObservation.boundingBox
            // Transform the latter into normalized view coordinates
            let viewNormalizedBoundingBox = boundingBox.applying(fromCameraImageToViewTransform)
            // The affine transform for view coordinates
            let t = CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height)
            //             Scale up to view coordinates
            let viewBoundingBox = viewNormalizedBoundingBox.applying(t)
            
            let midPoint = CGPoint(x: viewBoundingBox.midX,
                                   y: viewBoundingBox.midY)
            
            let results = self.hitTest(midPoint, types: .featurePoint)
            guard let result = results.first else { continue }
            
            print("Found object detection result \(topLabelObservation)")
            
            let pointer = PointerFingerEntity(color: UIColor(Color(.yellow).opacity(0.4)))
            pointer.move(to: result.worldTransform, relativeTo: nil)
            self.scene.addAnchor(pointer)

            if let lookingForObjectU = lookingForObject{
                if topLabelObservation.identifier == lookingForObjectU {
                    // i have object anchor position
                    // i have camera position in space
                    // i figure out the required rotation
                    
                    // i determine the actual rotation
                    
                    // i subtract the two to get the offset
                    
                    // get offset
                    objectDetectionAnchor = AnchorEntity()
                    objectDetectionAnchor?.move(to: result.worldTransform, relativeTo: nil)
//                    objectDetectionAnchor?.look(at: self.cameraTransform.translation, from: self.cameraTransform.translation, relativeTo: nil)
                    textDisplayer?("Locked on and looking for object")
                    lookingForObject = nil
                    
                }
            } else {
                //            self.session.add(anchor: anchor)
            }
        }
    }
    
    var beginSub: Cancellable?
    
//    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
//        print("added ARAnchor \(anchors)")
//        print("latest anchor: \(anchors.first)")
//    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        // Perform a raycast from the center of the screen
        let ray = self.raycast(from: CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY), allowing: .existingPlaneInfinite, alignment: .vertical)
        
        // Filter the raycast results
        if let rayFirstRes = ray.first,
           let planeAnchor = rayFirstRes.anchor as? ARPlaneAnchor {
            
            // here’s a line connecting the two points, which might be useful for other things
            let cameraToAnchor = cameraPosition - anchorPosition
            // and here’s just the scalar distance
            self.currentCentralDistance = length(cameraToAnchor)
//            let linearizedValue = (abs(Double(diffInRads(camPointObjRot.y, cameraCurrentRot.y))) + abs(Double(diffInRads(camPointObjRot.x, cameraCurrentRot.x)))).normalize(from: 0.0...(Double.pi + Double.pi/2), to: 0.0...1.0)
//            self.hapticsManager.sendContinuousHaptic(value: normalizeValue(linearizedValue))
//            print("Distance from raycast: \(distance)")
            // Check if the plane is vertical and its extent is larger than 1 square meter
            let extent = planeAnchor.extent
            let area = extent.x * extent.y
            if area > 1.0 {
                print("Found suitable vertical plane: \(extent)")
                
                let anchorPosition = rayFirstRes.worldTransform.columns.3
                let cameraPosition = self.cameraTransform.matrix.columns.3
                
                // Calculate the vector from the camera to the anchor
                let cameraToAnchor = cameraPosition - anchorPosition
                
                // Calculate the scalar distance
                let distance = length(cameraToAnchor)
                print("Distance from raycast: \(distance)")
            }
        }
        
                
        frameCounter += 1
    
        if frameCounter % 30 == 0 && lookingForObject != nil{
            if let sceneDepth = frame.sceneDepth {
//                guard let uiimage = cvPixelBufferToUIImage(pixelBuffer: sceneDepth.depthMap) else {return}
//                UIImageWriteToSavedPhotosAlbum(uiimage, nil, nil, nil)
            }
            do {
                let pixelBuffer = frame.capturedImage
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([objectDetectionRequest])
                
            } catch {
                assertionFailure("Human Pose Request failed: \(error)")
            }
        }
        
        // if looking for an object (do path finding basics)
        if objectDetectionAnchor != nil{
            
            if let selfTransform = session.currentFrame?.camera.transform {
                
                let cameraAnchor = Entity()
                cameraAnchor.move(to: self.cameraTransform, relativeTo: nil)
//                print("camera transform \(quatToEulerAngles(self.cameraTransform.rotation))")
                
                objectDetectionAnchor?.look(at: cameraAnchor.position, from: objectDetectionAnchor!.position, relativeTo: nil)
//                var camPointObjRot = quatToEulerAngles(objectDetectionAnchor!.transform.rotation)
//                camPointObjRot.y = Float.pi * 2 - camPointObjRot.y
//                camPointObjRot.x = Float.pi / 2 - camPointObjRot.x
//                camPointObjRot.z =  Float.pi * 2 - camPointObjRot.z
                guard let camPointObjRot = objectDetectionAnchor?.transformMatrix(relativeTo: nil).eulerAngles else {
                    print("no cam point obj rot")
                    return
                }
//                print("camera rot supposed to be \(camPointObjRot.y)")
                
                // camPointObjRot is what rot is supposed to be
                
                // actual rotation
                guard let cameraCurrentRot = self.session.currentFrame?.camera.eulerAngles else {
                    print("NO CAMERA ROT")
                    return
                }
//                cameraAnchor.transform.rotation
//                print("actual cam rot \(cameraCurrentRot.y)")
                
//                let differenceInRot = camPointObjRot - cameraCurrentRo right heret
//                print("DifferenceInROt \(differenceInRot)")
                
//                self.hapticsManager.sendContinuousHaptic(value: (abs(Double(differenceInRot.x))+abs(Double(differenceInRot.y))+abs(Double(differenceInRot.z))).normalizeExponentially(from: 0.0...(4*Double.pi + Double.pi/2), to: 0.0...1.0))
                
                // x is pi/2
                // y is 2pi
                let linearizedValue = (abs(Double(diffInRads(camPointObjRot.y, cameraCurrentRot.y))) + abs(Double(diffInRads(camPointObjRot.x, cameraCurrentRot.x)))).normalize(from: 0.0...(Double.pi + Double.pi/2), to: 0.0...1.0)
                self.hapticsManager.sendContinuousHaptic(value: normalizeValue(linearizedValue))
                
                
                //            let po = vector_float3.init(objTransform.columns.3.x, objTransform.columns.3.y, objTransform.columns.3.z)
                //            let ps = vector_float3.init(selfTransform.columns.3.x, selfTransform.columns.3.y, selfTransform.columns.3.z wait, I don't remember if we need to change the name servers on let me know. How do you not remember where you from Ryan working right what is dictation? Yeah I don't know how to turn on what code this is OK I don't get it I don't even get really dictation I dictated to dictate fuck you speech texting you the word that you said the other day I did not say that we waited to test on that and it did not work I need I'm gonna try to extract the meter values from the code for that, but it's just that we're working into)
                //
                //            let angle_rad = vector_float3.angleBetweenPointsToHorizontalPlane(p1: po, p2: ps)
                //            print(objectDetectionAnchorU.t)
                
                
                
                // i have object anchor position
                //            objectDetectionAnchorU.transform
                
                
                //            let positionRelToCam = objectDetectionAnchorU.transformMatrix(relativeTo: cameraEntity)
                //            objectDetectionAnchorU.transform.
                //            print("Position Relative to Camera \(positionRelToCam)")
                // i figure out the required rotation
                
                
                // i determine the actual rotation
                //            print("Current rotation: \(cameraCurrentRot)")
                
                // i subtract the two to get the offset
                
                
                
                
                //            print("OFFSET ANGLE \(objectDetectionAnchorU.transform)")
                
            }
            
        }
    }
    
    
    
    func configure() {
            self.viewportSize = UIScreen.main.bounds.size
            
        hapticsManager.startEngine()
        let config = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        else {
            print("A requested frame semantic from ARKit is unsupported.")
        }
//        
                config.planeDetection = [.horizontal, .vertical]
        
        // remove as many rendering as possible to keep light weight
        self.renderOptions = .disableMotionBlur
        self.renderOptions.insert(.disableDepthOfField)
        self.renderOptions.insert(.disableMotionBlur)
        self.renderOptions.insert(.disableHDR)
        self.renderOptions.insert(.disableAREnvironmentLighting)
        self.renderOptions.insert(.disableGroundingShadows)
        
        // this line gives error
        //        self.debugOptions.insert(.showStatistics)

        session.run(config)
        
        
//        self.beginSub = self.scene.subscribe(
//            to: CollisionEvents.Began.self,
//            on: pointFingerEntity
//        ) { event in
//            //convert colision position into a position in SwiftUI and programatically interact, then force reload the view, also actually setup the position so it works.
//            guard let contactPoint = self.dashboardEntity?.convert(position: event.position, from: nil) else { return }
//            let x = Int(contactPoint.x*9000/3) + Int((self.dashboardCardGeo?.width ?? 0) / 2)
//            let y = Int(contactPoint.y*9000/3) * -1 + Int((self.dashboardCardGeo?.height ?? 0) / 2)
//            
//            let viewContactPoint = CGPoint(x: x, y: y)
//            guard self.dashboardCardGeo != nil else { return }
//            
//        }
        
    }
    
}

// emphasize difference between larger valuesr
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

// returns the diff of radians that range from 0 to 2pi so that the difference between 11pi/6 and 0 is not 11pi/6 but pi/6
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

func diffInRadsX(_ rad1: Float, _ rad2: Float) -> Float {
//    print("rad 1: \(rad1), rad2: \(rad2)")

    let pi = Float.pi
    var diff = (rad2 - rad1).truncatingRemainder(dividingBy: 2 * pi)
    
    if diff > pi / 2 {
        diff -= pi
    } else if diff < -pi / 2 {
        diff += pi
    }
//    print("diff in rads: \(diff)")
    return diff
}

func quatToEulerAngles(_ quat: simd_quatf) -> SIMD3<Float>{
    
    var angles = SIMD3<Float>();
    let qfloat = quat.vector
    
    // heading = x, attitude = y, bank = z
    
    let test = qfloat.x*qfloat.y + qfloat.z*qfloat.w;
    
    if (test > 0.499) { // singularity at north pole
        
        angles.x = 2 * atan2(qfloat.x,qfloat.w)
        angles.y = (.pi / 2)
        angles.z = 0
        return  angles
    }
    if (test < -0.499) { // singularity at south pole
        angles.x = -2 * atan2(qfloat.x,qfloat.w)
        angles.y = -(.pi / 2)
        angles.z = 0
        return angles
    }
    
    
    let sqx = qfloat.x*qfloat.x;
    let sqy = qfloat.y*qfloat.y;
    let sqz = qfloat.z*qfloat.z;
    angles.x = atan2(2*qfloat.y*qfloat.w-2*qfloat.x*qfloat.z , 1 - 2*sqy - 2*sqz)
    angles.y = asin(2*test)
    angles.z = atan2(2*qfloat.x*qfloat.w-2*qfloat.y*qfloat.z , 1 - 2*sqx - 2*sqz)
    
    return angles
}

extension vector_float3 {
    
    /// Returns the angle of a line defined by to points to a horizontal plane
    ///
    /// - Parameters:
    ///   - p1: p1 (vertice)
    ///   - p2: p2
    /// - Returns: angle to a horizontal crossing p1 in radians
    static func angleBetweenPointsToHorizontalPlane(p1:vector_float3, p2:vector_float3) -> Float {
        
        ///Point in 3d space on the same level of p1 but equal to p2
        let p2Hor = vector_float3.init(p2.x, p1.y, p2.z)
        
        let p1ToP2Norm = normalize(p2 - p1)
        let p1ToP2HorNorm = normalize(p2Hor - p1)
        
        let dotProduct = dot(p1ToP2Norm, p1ToP2HorNorm)
        
        let angle = acos(dotProduct)
        
        return angle
    }
}


//MARK: Toggle UI / Manipulate UI position
@available(iOS 16.0, *)
extension VideARView {
    
    
}

//MARK: Helpers
@available(iOS 16.0, *)
extension VideARView {
    
    //adapted from - https://stackoverflow.com/questions/44944581/how-to-transform-vision-framework-coordinate-system-into-arkit
    func convertFromCamera(_ point: CGPoint) -> CGPoint {
        let orientation = UIApplication.shared.statusBarOrientation
        
        switch orientation {
            case .portrait, .unknown:
                return CGPoint(x: point.y * self.frame.width, y: point.x * self.frame.height)
            case .landscapeLeft:
                return CGPoint(x: (1 - point.x) * self.frame.width, y: point.y * self.frame.height)
            case .landscapeRight:
                return CGPoint(x: point.x * self.frame.width, y: (1 - point.y) * self.frame.height)
            case .portraitUpsideDown:
                return CGPoint(x: (1 - point.y) * self.frame.width, y: (1 - point.x) * self.frame.height)
        }
    }
}

extension Double {
    func normalize(from input: ClosedRange<Self>, to output: ClosedRange<Self>) -> Self {
        let x = (output.upperBound - output.lowerBound) * (self - input.lowerBound)
        let y = (input.upperBound - input.lowerBound)
        return x / y + output.lowerBound
    }
    func normalizeExponentially(from input: ClosedRange<Self>, to output: ClosedRange<Self>) -> Double {
        // Define the original range based on the current value
        let originalMin = input.lowerBound
        let originalMax = input.upperBound
        
        // Calculate the scaling factor
        let scaleFactor = (output.upperBound - output.lowerBound) / (originalMax - originalMin)
        
        // Linearly transform the value
        let linearTransformedValue = (self - originalMin) * scaleFactor + output.lowerBound
        
        // Apply exponential transformation
        let exponentiatedValue = pow(linearTransformedValue, 0.5)
        
        return exponentiatedValue
    }
}



class PointerFingerEntity: Entity, HasAnchoring, HasCollision {
    
    var collisionSubs: [Cancellable] = []
    
    required init(color: UIColor) {
        super.init()
        
        self.components[CollisionComponent.self] = CollisionComponent(
            shapes: [.generateBox(size: [0.025,0.025,0.025])],
            mode: .default,
            filter: .sensor
        )
        
        self.components[ModelComponent.self] = ModelComponent(
            mesh: .generateSphere(radius: 0.005),
            materials: [UnlitMaterial(
                color: color)
            ]
        )
    }
    
    convenience init(color: UIColor, position: SIMD3<Float>) {
        self.init(color: color)
        self.position = position
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
}
