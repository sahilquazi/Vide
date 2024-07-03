//
//  HapticsManager.swift
//  test-depth
//
//  Created by Ryan Du on 6/26/24.
//

import Foundation
import SwiftUI
import CoreHaptics
import Combine
import RealityKit

class HapticsManager: ObservableObject {
    @Published var engine: CHHapticEngine?
    @Published var continuousPlayer: CHHapticAdvancedPatternPlayer?
    @Published var value = 0.1
    
    private let initialIntensity: Float = 1.0
    private let initialSharpness: Float = 0.1
    @Published private var engineNeedsStart = true
    @Published var proximityWarningOn = false
    
    
    func startEngine() {
        createAndStartHapticEngine()
        createContinuousHapticPlayer()
        
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [self] _ in
            if self.proximityWarningOn {
                self.playTactileHaptic(hapticIntensity: 0.95, hapticSharpness: 0.7)
            }
        }
        
    }

    
    func createAndStartHapticEngine() {
        // Create and configure a haptic engine.
        do {
            engine = try CHHapticEngine()
        } catch let error {
            fatalError("Engine Creation Error: \(error)")
        }
        
        
        // Mute audio to reduce latency for collision haptics.
        engine?.playsHapticsOnly = true
        
        // The stopped handler alerts you of engine stoppage.
        engine?.stoppedHandler = { reason in
            print("Stop Handler: The engine stopped for reason: \(reason.rawValue)")
            switch reason {
                case .audioSessionInterrupt:
                    print("Audio session interrupt")
                case .applicationSuspended:
                    print("Application suspended")
                case .idleTimeout:
                    print("Idle timeout")
                case .systemError:
                    print("System error")
                case .notifyWhenFinished:
                    print("Playback finished")
                case .gameControllerDisconnect:
                    print("Controller disconnected.")
                case .engineDestroyed:
                    print("Engine destroyed.")
                @unknown default:
                    print("Unknown error")
            }
        }
        
        
        // The reset handler provides an opportunity to restart the engine.
        engine?.resetHandler = {
            
            print("Reset Handler: Restarting the engine.")
            
            do {
                // Try restarting the engine.
                try self.engine?.start()
                
                // Indicate that the next time the app requires a haptic, the app doesn't need to call engine.start().
                self.engineNeedsStart = false
                // Recreate the continuous player.
                self.createContinuousHapticPlayer()
                
            } catch {
                print("Failed to start the engine")
            }
        }
        
        // Start the haptic engine for the first time.
        do {
            try self.engine?.start()
            try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
            
        } catch {
            print("Failed to start the engine: \(error)")
        }
        
        
    }
    
    /// - Tag: CreateContinuousPattern
    func createContinuousHapticPlayer() {
        // Create an intensity parameter:
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity,
                                               value: initialIntensity)
        
        // Create a sharpness parameter:
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness,
                                               value: initialSharpness)
        
        // Create a continuous event with a long duration from the parameters.
        let continuousEvent = CHHapticEvent(eventType: .hapticContinuous,
                                            parameters: [intensity, sharpness],
                                            relativeTime: 0,
                                            duration: 100)
        
        do {
            // Create a pattern from the continuous haptic event.
            let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
            
            // Create a player from the continuous haptic pattern.
            continuousPlayer = try engine?.makeAdvancedPlayer(with: pattern)
            print("made continuous Player: \(continuousPlayer)")
            
        } catch let error {
            print("Pattern Player Creation Error: \(error)")
        }
        
        continuousPlayer?.completionHandler = { [self] _ in
            DispatchQueue.main.async {
                print("continuous event completed --------------------------------------------------------------")
                
                // Restore original color.
                //                self.continuousPalette.backgroundColor = self.padColor
            }
            
            do {
                try self.continuousPlayer?.start(atTime: CHHapticTimeImmediate)
            } catch {
                print(error)
            }
        }
        
            do {
                // Begin playing continuous pattern.
                try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
            } catch let error {
                print("Error starting the continuous haptic player: \(error)")
            }
    }
    
    // MARK: Play haptics
    
    func playTactileHaptic(hapticIntensity: Float = 0.5, hapticSharpness: Float = 0.5) {
        do {
            
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: hapticIntensity)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: hapticSharpness)
            let sustained = CHHapticEventParameter(parameterID: .sustained, value: 1.0)
            
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness, sustained], relativeTime: 0, duration: 0.5)
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            
            engine?.notifyWhenPlayersFinished { error in
                return .stopEngine
            }
            
            
            try engine?.start()
            try player?.start(atTime: 0)
        } catch {
            print(error)
        }
    }
    
    func playSingleProximityWarn() {
        
    }
    
    func sendContinuousHaptic(value: Double) {
//        print("Attempting to play continuousHaptic with intensity \(value)")
        // Create dynamic parameters for the updated intensity & sharpness.
        let intensityParameter = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                          value: Float(value),
                                                          relativeTime: 0)
        
        let sharpnessParameter = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                                          value: 0.2,
                                                          relativeTime: 0)
        
        
        // Send dynamic parameters to the haptic player.
        do {
            guard let uContinuousPlayer = continuousPlayer else {
                print("No continuous player when updating values")
                return
            }
            try uContinuousPlayer.sendParameters([intensityParameter, sharpnessParameter],
                                                 atTime: 0)
        } catch let error {
            print("Dynamic Parameter Error: \(error)")
        }
        
        
    }
    
    
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

