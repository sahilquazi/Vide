//
//  ContentView.swift
//  test-depth
//
//  Created by Ryan Du on 6/24/24.
//

import SwiftUI
import RealityKit
import AVKit
import Speech
import Combine

struct ContentView : View {
    @State var displayText = ""
    @StateObject private var speechRecognizer = SpeechRecognizer(gotResponse: {response in
        print("sending notif look \(response)")
        DispatchQueue.main.async {
        NotificationCenter.default.post(name: Notification.Name.gotGPTODResponse, object: response)
        }
    })
    
    // keys,door,window,trash_can,light_bulb,phone,marker,charger
    func handleResponse(_ value: String) -> String {
        switch value {
            case "#keys":
                return "🔑"
            case "#door":
                return "🚪"
            case "#window":
                return "🪟"
            case "#trash_can":
                return "🗑️"
            case "#light_bulb":
                return "💡"
            case "#phone":
                return "📱"
            case "#marker":
                return "🖊️"
            case "#charger":
                return "🔌"
            case "#bicycle":
                return "🚲"
            case "#car":
                return "🚗"
            case "#motorbike":
                return "🏍️"
            case "#aeroplane":
                return "✈️"
            case "#bus":
                return "🚌"
            case "#train":
                return "🚆"
            case "#truck":
                return "🚚"
            case "#boat":
                return "🛥️"
            case "#traffic_light":
                return "🚦"
            case "#fire_hydrant":
                return "🚒"
            case "#stop_sign":
                return "🛑"
            case "#parking_meter":
                return "🅿️"
            case "#bench":
                return "🪑"
            case "#backpack":
                return "🎒"
            case "#umbrella":
                return "☂️"
            case "#handbag":
                return "👜"
            case "#tie":
                return "👔"
            case "#suitcase":
                return "🧳"
            case "#frisbee":
                return "🥏"
            case "#skis":
                return "⛷️"
            case "#snowboard":
                return "🏂"
            case "#sports_ball":
                return "⚽"
            case "#kite":
                return "🪁"
            case "#baseball_bat":
                return "🏏"
            case "#baseball_glove":
                return "🥎"
            case "#skateboard":
                return "🛹"
            case "#surfboard":
                return "🏄"
            case "#tennis_racket":
                return "🎾"
            case "#bottle":
                return "🍾"
            case "#wine_glass":
                return "🍷"
            case "#cup":
                return "🍵"
            case "#fork":
                return "🍴"
            case "#knife":
                return "🔪"
            case "#spoon":
                return "🥄"
            case "#bowl":
                return "🥣"
            case "#banana":
                return "🍌"
            case "#apple":
                return "🍎"
            case "#sandwich":
                return "🥪"
            case "#orange":
                return "🍊"
            case "#broccoli":
                return "🥦"
            case "#carrot":
                return "🥕"
            case "#hot_dog":
                return "🌭"
            case "#pizza":
                return "🍕"
            case "#donut":
                return "🍩"
            case "#cake":
                return "🍰"
            case "#chair":
                return "🪑"
            case "#sofa":
                return "🛋️"
            case "#potted_plant":
                return "🪴"
            case "#bed":
                return "🛏️"
            case "#dining_table":
                return "🍽️"
            case "#toilet":
                return "🚽"
            case "#tv_monitor":
                return "📺"
            case "#laptop":
                return "💻"
            case "#mouse":
                return "🖱️"
            case "#remote":
                return "📺"
            case "#keyboard":
                return "⌨️"
            case "#cell_phone":
                return "📱"
            case "#microwave":
                return "🍲"
            case "#oven":
                return "🍳"
            case "#toaster":
                return "🍞"
            case "#sink":
                return "🚰"
            case "#refrigerator":
                return "🧊"
            case "#book":
                return "📚"
            case "#clock":
                return "🕰️"
            case "#vase":
                return "🏺"
            case "#scissors":
                return "✂️"
            case "#teddy_bear":
                return "🧸"
            case "#hair_drier":
                return "💇"
            case "#toothbrush":
                return "🪥"
            default:
                return "❓" // Default emoji if no match is found
        }
    }
    var didChange = PassthroughSubject<String, Never>()

    
    
    
    var body: some View {
        ZStack {
            ARViewContainer(didChange: didChange, speechRecognizer: speechRecognizer, textDisplayer: {text in
                displayText = text
                
            }).edgesIgnoringSafeArea(.all)
            VStack {
                Text(displayText)
                    .background(Color.white.opacity(0.2))
                    .padding()
                Spacer()
                
                Text(handleResponse(speechRecognizer.gptResponse))
                    .padding()
                
                Button(action: {
                    if !speechRecognizer.isRecording {
                        speechRecognizer.transcribe()
                    } else {
                        speechRecognizer.stopTranscribing()
                    }
                    
                    speechRecognizer.isRecording.toggle()
                }) {
                    Text(speechRecognizer.isRecording ? "Stop" : "Record")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 300, height: 100)
                        .background(speechRecognizer.isRecording ? Color.red : Color.blue)
                        .cornerRadius(20)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.gotGPTODResponse), perform: {object in
            
            guard let response = object.object as? String else {
                print("look got object: \(object)")
                print("look error getting string from gotGPTODResponse")
                return
            }
            print("look for object \(response.dropFirst())")
            self.didChange.send(String(response.dropFirst()))
        })
    }
}

extension Notification.Name {
    static let gotGPTODResponse = Notification.Name("GotGPTODResponse")
}

struct ARViewContainer: UIViewRepresentable {
    
    var didChange: PassthroughSubject<String, Never>
    var speechRecognizer: SpeechRecognizer
    @State var cancellable: AnyCancellable? = nil

    var textDisplayer: (String) -> ()
    
    func makeUIView(context: Context) -> ARView {
        
        let view = VideARView(textDisplayer: textDisplayer, speechRecognizer: speechRecognizer)
        
        DispatchQueue.main.async {
            // very important to capture it as a variable, otherwise it'll be short lived.
            self.cancellable = didChange.sink { (value) in
                print("looking Received: \(value)")
                
                // here you can do a switch case to know which method to call
                // on your UIKit class, example:
                // call your function!
                view.setObjectDetectionTarget(target: value)
            }
        }
        
        return view
        
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}

#Preview {
    ContentView()
}
