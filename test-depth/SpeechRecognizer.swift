import AVFoundation
import Foundation
import Speech
import SwiftUI

enum RecognizerError: Error {
    case nilRecognizer
    case notAuthorizedToRecognize
    case notPermittedToRecord
    case recognizerIsUnavailable
    
    var message: String {
        switch self {
            case .nilRecognizer: return "Can't initialize speech recognizer"
            case .notAuthorizedToRecognize: return "Not authorized to recognize speech"
            case .notPermittedToRecord: return "Not permitted to record audio"
            case .recognizerIsUnavailable: return "Recognizer is unavailable"
        }
    }
}

struct TaggerResponse: Decodable {
    let tag: String
}

/// A helper for transcribing speech to text using SFSpeechRecognizer and AVAudioEngine.
class SpeechRecognizer: ObservableObject {
    
    @Published var isRecording = false
    
    //tts
    @Published var speechSynthesizer: AVSpeechSynthesizer?
    @Published var transcript: String = ""
    @Published var gptResponse: String = ""
    
    var gotResponse: (String) -> ()
    
    func askGPT(_ message: String) async -> String {
        print("Asking GPT")
        
        
        print(message)
        
        
        do {
            let url = URL(string: "https://openai-express-production.up.railway.app/tag")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload = ["text": message]
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            let decoded = try JSONDecoder().decode(TaggerResponse.self, from: data)
            
            return decoded.tag
            
            //            let chat: [ChatMessage] = [
            //                ChatMessage(role: .system, content: "Your task is to take user input, and associate with a specific tag that best fits from the list of tags I give you. Do not deviate from the list, and if no matching tags are found, just respond with the error tag which is specified (#error). You must only respond with the tag and nothing else. A tag must be formatted to begin with a hashtag character which precedes the keyword. If the user gives an example of an object that is not the exact object, you must still give the relevant tags. For instance if someone says they are looking for the red door, you should give them the tag of #door. \nAVAILABLE KEYWORDS: keys\ndoor\nwindow\ntrash_can\nlight_bulb\nphone\nmarker\ncharger\nbicycle\ncar\nmotorbike\naeroplane\nbus\ntrain\ntruck\nboat\ntraffic_light\nfire_hydrant\nstop_sign\nparking_meter\nbench\nbackpack\numbrella\nhandbag\ntie\nsuitcase\nfrisbee\nskis\nsnowboard\nsports_ball\nkite\nbaseball_bat\nbaseball_glove\nskateboard\nsurfboard\ntennis_racket\nbottle\nwine_glass\ncup\nfork\nknife\nspoon\nbowl\nbanana\napple\nsandwich\norange\nbroccoli\ncarrot\nhot_dog\npizza\ndonut\ncake\nchair\nsofa\npottedplant\nbed\ndiningtable\ntoilet\ntvmonitor\nlaptop\nmouse\nremote\nkeyboard\ncell_phone\nmicrowave\noven\ntoaster\nsink\nrefrigerator\nbook\nclock\nvase\nscissors\nteddy_bear\nhair_drier\ntoothbrush\nerror"),
            //                ChatMessage(role: .user, content: message)
            //            ]
            //
            //            let chatParameters = ChatParameters(
            //                model: .gpt4,  // ID of the model to use.
            //                messages: chat  // A list of messages comprising the conversation so far.
            //            )
            //
            //            let chatCompletion = try await openAI.generateChatCompletion(
            //                parameters: chatParameters
            //            )
            //
            //            if let msg = chatCompletion.choices[0].message {
            //                let content = msg.content
            //                if content == nil {
            //                    return "No message found"
            //                }
            //                print("Sending content.")
            //                print(content!)
            //                return content!
            //            }
            
            
            
        } catch {
            // Insert your own error handling method here.
            print("Error")
            return "Error"
        }
        
        return "Finished"
    }
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    
    /// Reset the speech recognizer.
    func reset() {
        task?.cancel()
        audioEngine?.stop()
        audioEngine = nil
        request = nil
        task = nil
    }
    
    /**
     Begin transcribing audio.
     
     Creates a `SFSpeechRecognitionTask` that transcribes speech to text until you call `stopTranscribing()`.
     The resulting transcription is continuously written to the published `transcript` property.
     */
    func transcribe() {
        DispatchQueue(label: "Speech Recognizer Queue", qos: .background).async { [weak self] in
            guard let self = self, let recognizer = self.recognizer, recognizer.isAvailable else {
                self?.speakError(RecognizerError.recognizerIsUnavailable)
                return
            }
            
            do {
                let (audioEngine, request) = try Self.prepareEngine()
                self.audioEngine = audioEngine
                self.request = request
                
                self.task = recognizer.recognitionTask(with: request) { result, error in
                    let receivedFinalResult = result?.isFinal ?? false
                    let receivedError = error != nil // != nil mean there's error (true)
                    
                    if receivedFinalResult || receivedError {
                        audioEngine.stop()
                        audioEngine.inputNode.removeTap(onBus: 0)
                    }
                    
                    if let result = result {
                        self.setTranscription(result.bestTranscription.formattedString)
                    }
                }
            } catch {
                self.reset()
                self.speakError(error)
            }
        }
    }
    
    
    func speak(_ words: String) {
        
        if UserDefaults.standard.bool(forKey: "audioOn") {
            
            let audioSession = AVAudioSession() // 2) handle audio session first, before trying to read the text
            
            
            do {
                try audioSession.setCategory(.playback, mode: .default, options: .duckOthers)
                try audioSession.setActive(false)
            } catch let error {
                print("❓", error.localizedDescription)
            }
            
            speechSynthesizer = AVSpeechSynthesizer()
            
            let speechUtterance = AVSpeechUtterance(string: words)
            //        speechUtterance.prefersAssistiveTechnologySettings = true
            for voice in AVSpeechSynthesisVoice.speechVoices()
            {
                if voice.language == "en-US" {
                    
                    if voice.name == "Evan (Enhanced)" {
                        print("FOUND VOICE")
                        speechUtterance.voice = voice
                    }
                }
                
                
            }
            
            
            speechSynthesizer?.speak(speechUtterance)
        }
    }
    
    /// Stop transcribing audio.
    func stopTranscribing() {
        
        DispatchQueue.main.async{
            Task {
                self.gptResponse = await self.askGPT(self.transcript)
                self.gotResponse(self.gptResponse)
                self.reset()
            }
            
        }
    }
    
    private static func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        
        return (audioEngine, request)
    }
    
    private func setTranscription(_ message: String) {
        transcript = message
    }
    
    private func speakError(_ error: Error) {
        var errorMessage = ""
        if let error = error as? RecognizerError {
            errorMessage += error.message
        } else {
            errorMessage += error.localizedDescription
        }
        transcript = "<< \(errorMessage) >>"
    }
    
    
    init(gotResponse: @escaping (String) -> ()) {
        self.gotResponse = gotResponse
        recognizer = SFSpeechRecognizer()
        
        Task(priority: .background) {
            do {
                guard recognizer != nil else {
                    throw RecognizerError.nilRecognizer
                }
                guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
                    throw RecognizerError.notAuthorizedToRecognize
                }
                guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
                    throw RecognizerError.notPermittedToRecord
                }
            } catch {
                speakError(error)
            }
        }
    }
    
    deinit {
        reset()
    }
}


extension SFSpeechRecognizer {
    static func hasAuthorizationToRecognize() async -> Bool {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

extension AVAudioSession {
    func hasPermissionToRecord() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { authorized in
                continuation.resume(returning: authorized)
            }
        }
    }
}

