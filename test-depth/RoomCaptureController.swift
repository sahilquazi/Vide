import Foundation
import RoomPlan
import ARKit
import RealityKit
import Observation
import UIKit

@Observable
class RoomCaptureController: RoomCaptureViewDelegate, RoomCaptureSessionDelegate, ObservableObject {
    var roomCaptureView: RoomCaptureView
    var speechRecognizer = SpeechRecognizer(gotResponse: {a in
        print("aaaaa" + a)
    })
    var showExportButton = false
    var showShareSheet = false
    var exportUrl: URL?

    var sessionConfig: RoomCaptureSession.Configuration
    var finalResult: CapturedRoom?
    
    var oldObjects: [CapturedRoom.Object] = []

    init() {
        sessionConfig = RoomCaptureSession.Configuration()
        roomCaptureView = RoomCaptureView(frame: CGRect(x: 0, y: 0, width: 42, height: 42))
 

        roomCaptureView.captureSession.delegate = self

        roomCaptureView.delegate = self
        
      // Ensure roomCaptureView is fully initialized before this line
    }

    func startSession() {
        roomCaptureView.captureSession.run(configuration: sessionConfig)
    }

    func stopSession() {
        roomCaptureView.captureSession.stop()
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }
    
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        print("updated room capture with room: \(room.objects)")
        let newObjects = findNewObjects(oldList: oldObjects, newList: room.objects)
        for obj in newObjects {
            self.speechRecognizer.speak("\(obj.category)")
        }
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResult = processedResult
        printObjectDetails()
        updateBoundingBoxes()
    }

    func printObjectDetails() {
        guard let objects = finalResult?.objects else { return }
        for object in objects {
            print("Detected object: \(object.category)")
            
            
            
            
          //  let midPoint = CGPoint(x: viewBoundingBox.midX, y: viewBoundingBox.midY)
            
        //    let results = self.hitTest(midPoint, types: .featurePoint)
        //    guard let result = results.first else { continue }
            
            
            
            

            // Function to convert degrees to clock positions
            func degreesToClockPosition(_ degrees: Int) -> String {
                switch degrees {
                case 0, 360, -360:
                    return "12 o'clock"
                case 30...60:
                    return "1 o'clock"
                case 90...120:
                    return "3 o'clock"
                case 150...179, -179...(-150):
                    return "6 o'clock"
                case -120...(-90):
                    return "9 o'clock"
                case -60...(-30):
                    return "11 o'clock"
                default:
                    return "\(degrees) degrees"
                    self.speechRecognizer.speak("\(degrees) degrees")
                }
            }

            // Function to convert radians to degrees and determine clock position
            func radiansToClockPosition(_ radians: Double) -> String {
                let degrees = Int(round(radians * 180 / .pi))
                return degreesToClockPosition(degrees)
            }

            // Example usage:
            let camPointObjRotY = 0.0 // Example value for camPointObjRot.y (in radians)
            let camPointObjRotX = 0.0 // Example value for camPointObjRot.x (in radians)
// this wont be a camera point, only the AR point
            // Convert radians to clock positions
            let clockY = radiansToClockPosition(camPointObjRotY)
            let clockX = radiansToClockPosition(camPointObjRotX)

            // Print results
            print("Vertical position: \(clockY)")
            print("Horizontal position: \(clockX)")

            
            
            
            
        }
    }

    func updateBoundingBoxes() {
        guard let objects = finalResult?.objects else { return }
        
        var boxes: [(dimensions: simd_float3, transform: float4x4)] = []
        
        for object in objects {
            boxes.append((object.dimensions, object.transform))
        }
        

    }

    func export() {
        exportUrl = FileManager.default.temporaryDirectory.appendingPathComponent("scan.usdz")
        do {
            try finalResult?.export(to: exportUrl!)
        } catch {
            print("Error exporting usdz scan.")
            return
        }
        showShareSheet = true
    }

    required init?(coder: NSCoder) {
        fatalError("Not needed.")
    }

    func encode(with coder: NSCoder) {
        fatalError("Not needed.")
    }
    
    func drawBox(scene: Scene, dimensions: simd_float3, transform: float4x4, confidence: CapturedRoom.Confidence) {
        let boxMesh = MeshResource.generateBox(size: dimensions)
        let material = SimpleMaterial(color: .green, isMetallic: false)
        let model = ModelEntity(mesh: boxMesh, materials: [material])
        
        // Set position
    //    model.position = transform.translation
        
        // Calculate rotation
       // let rotationMatrix = simd_float3x3(transform.columns.0.xyz, transform.columns.1.xyz, transform.columns.2.xyz)
      //  let rotation = simd_quatf(matrix: rotationMatrix)
   //     model.orientation = rotation
        
     //   let anchor = AnchorEntity(world: transform.translation)
        
        
        
        
        
        
        
       // anchor.addChild(model)
      //  scene.addAnchor(anchor)
    }
}

func findNewObjects(oldList: [CapturedRoom.Object], newList: [CapturedRoom.Object]) -> [CapturedRoom.Object] {
    // Create a set of identifiers from the oldList
    let oldIdentifiers = Set(oldList.map { $0.identifier })
    
    // Filter newList to find objects whose identifiers are not in oldIdentifiers
    let newObjects = newList.filter { !oldIdentifiers.contains($0.identifier) }
    
    return newObjects
}
