import Foundation
 
 struct LocalModel: TranscriptionModel {
     let id = UUID()
     let name: String
     let displayName: String
     let size: String
     let supportedLanguages: [String: String]
     let description: String
     let speed: Double
     let accuracy: Double
     let ramUsage: Double
     let hash: String
     let provider: ModelProvider = .local
 
     var downloadURL: String {
         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
     }
 
     var filename: String {
         "\(name).bin"
     }
 
     var isMultilingualModel: Bool {
         supportedLanguages.count > 1
     }
 }
 
 enum PredefinedModels {
     static func getLanguageDictionary(isMultilingual: Bool, isLargeV3: Bool = false) -> [String:
         String]
     {
         if !isMultilingual {
             return ["en": "English"]
         } else if isLargeV3 {
             return allLanguages // Large v3 models support all languages including Cantonese
         } else {
             // Create a dictionary without Cantonese for non-Large v3 models
             var languagesWithoutCantonese = allLanguages
             languagesWithoutCantonese.removeValue(forKey: "yue")
             return languagesWithoutCantonese
         }
     }
 
     static let models: [any TranscriptionModel] = [
         // Local Models
         LocalModel(
             name: "ggml-tiny",
             displayName: "Tiny",
             size: "75 MiB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true),
             description: "Tiny model, fastest, least accurate, supports multiple languages",
             speed: 0.95,
             accuracy: 0.6,
             ramUsage: 0.3,
             hash: "bd577a113a864445d4c299885e0cb97d4ba92b5f"
         ),
         LocalModel(
             name: "ggml-tiny.en",
             displayName: "Tiny (English)",
             size: "75 MiB",
             supportedLanguages: getLanguageDictionary(isMultilingual: false),
             description: "Tiny model optimized for English, fastest, least accurate",
             speed: 0.95,
             accuracy: 0.65,
             ramUsage: 0.3,
             hash: "c78c86eb1a8faa21b369bcd33207cc90d64ae9df"
         ),
         LocalModel(
             name: "ggml-base.en",
             displayName: "Base (English)",
             size: "142 MiB",
             supportedLanguages: getLanguageDictionary(isMultilingual: false),
             description: "Base model optimized for English, good balance between speed and accuracy",
             speed: 0.8,
             accuracy: 0.75,
             ramUsage: 0.5,
             hash: "137c40403d78fd54d454da0f9bd998f78703390c"
         ),
         LocalModel(
             name: "ggml-large-v2",
             displayName: "Large v2",
             size: "2.9 GiB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true),
             description: "Large model v2, slower than Medium but more accurate, supports multiple languages",
             speed: 0.5,
             accuracy: 0.96,
             ramUsage: 3.8,
             hash: "0f4c8e30f21cf1769f637135f521436792c48186"
         ),
         LocalModel(
             name: "ggml-large-v3",
             displayName: "Large v3",
             size: "2.9 GiB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, isLargeV3: true),
             description: "Large model v3, very slow but most accurate, supports multiple languages",
             speed: 0.5,
             accuracy: 0.98,
             ramUsage: 3.9,
             hash: "ad82bf6a9043ceed055076d0fd39f5f186ff8062"
         ),
         LocalModel(
             name: "ggml-large-v3-turbo",
             displayName: "Large v3 Turbo",
             size: "1.5 GiB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, isLargeV3: true),
             description:
             "Large model v3 Turbo, faster than v3 with similar accuracy, supports multiple languages",
             speed: 0.7,
             accuracy: 0.97,
             ramUsage: 1.8,
             hash: "4af2b29d7ec73d781377bfd1758ca957a807e941"
         ),
         LocalModel(
             name: "ggml-large-v3-turbo-q5_0",
             displayName: "Large v3 Turbo (Quantized)",
             size: "547 MiB",
             supportedLanguages: getLanguageDictionary(isMultilingual: true, isLargeV3: true),
             description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
             speed: 0.7,
             accuracy: 0.96,
             ramUsage: 1.0,
             hash: "e050f7970618a659205450ad97eb95a18d69c9ee"
         ),
         
                 // Cloud Models
        CloudModel(
            name: "whisper-large-v3-turbo",
            displayName: "Whisper Large v3 Turbo (Groq)",
            description: "Groq's ultra-fast Whisper Large v3 Turbo model with lightning-speed inference",
            provider: .groq,
            speed: 0.65,
            accuracy: 0.96,
            isMultilingual: true,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, isLargeV3: true)
        ),
        CloudModel(
           name: "scribe_v1",
           displayName: "Scribe v1 (ElevenLabs)",
           description: "ElevenLabs' Scribe model for fast and accurate transcription.",
           provider: .elevenLabs,
           speed: 0.75,
           accuracy: 0.98,
           isMultilingual: true,
           supportedLanguages: getLanguageDictionary(isMultilingual: true, isLargeV3: true)
       ),

     ]
 
     static let allLanguages = [
         "auto": "Auto-detect",
         "af": "Afrikaans",
         "am": "Amharic",
         "ar": "Arabic",
         "as": "Assamese",
         "az": "Azerbaijani",
         "ba": "Bashkir",
         "be": "Belarusian",
         "bg": "Bulgarian",
         "bn": "Bengali",
         "bo": "Tibetan",
         "br": "Breton",
         "bs": "Bosnian",
         "ca": "Catalan",
         "cs": "Czech",
         "cy": "Welsh",
         "da": "Danish",
         "de": "German",
         "el": "Greek",
         "en": "English",
         "es": "Spanish",
         "et": "Estonian",
         "eu": "Basque",
         "fa": "Persian",
         "fi": "Finnish",
         "fo": "Faroese",
         "fr": "French",
         "gl": "Galician",
         "gu": "Gujarati",
         "ha": "Hausa",
         "haw": "Hawaiian",
         "he": "Hebrew",
         "hi": "Hindi",
         "hr": "Croatian",
         "ht": "Haitian Creole",
         "hu": "Hungarian",
         "hy": "Armenian",
         "id": "Indonesian",
         "is": "Icelandic",
         "it": "Italian",
         "ja": "Japanese",
         "jw": "Javanese",
         "ka": "Georgian",
         "kk": "Kazakh",
         "km": "Khmer",
         "kn": "Kannada",
         "ko": "Korean",
         "la": "Latin",
         "lb": "Luxembourgish",
         "ln": "Lingala",
         "lo": "Lao",
         "lt": "Lithuanian",
         "lv": "Latvian",
         "mg": "Malagasy",
         "mi": "Maori",
         "mk": "Macedonian",
         "ml": "Malayalam",
         "mn": "Mongolian",
         "mr": "Marathi",
         "ms": "Malay",
         "mt": "Maltese",
         "my": "Myanmar",
         "ne": "Nepali",
         "nl": "Dutch",
         "nn": "Norwegian Nynorsk",
         "no": "Norwegian",
         "oc": "Occitan",
         "pa": "Punjabi",
         "pl": "Polish",
         "ps": "Pashto",
         "pt": "Portuguese",
         "ro": "Romanian",
         "ru": "Russian",
         "sa": "Sanskrit",
         "sd": "Sindhi",
         "si": "Sinhala",
         "sk": "Slovak",
         "sl": "Slovenian",
         "sn": "Shona",
         "so": "Somali",
         "sq": "Albanian",
         "sr": "Serbian",
         "su": "Sundanese",
         "sv": "Swedish",
         "sw": "Swahili",
         "ta": "Tamil",
         "te": "Telugu",
         "tg": "Tajik",
         "th": "Thai",
         "tk": "Turkmen",
         "tl": "Tagalog",
         "tr": "Turkish",
         "tt": "Tatar",
         "uk": "Ukrainian",
         "ur": "Urdu",
         "uz": "Uzbek",
         "vi": "Vietnamese",
         "yi": "Yiddish",
         "yo": "Yoruba",
         "yue": "Cantonese",
         "zh": "Chinese",
     ]
 }