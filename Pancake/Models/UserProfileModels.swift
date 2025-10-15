import Foundation

// MARK: - User Profile Models

struct UserProfile: Codable, Identifiable {
    let id: UUID
    var personalInfo: PersonalInfo
    var musicPreferences: MusicPreferences
    var runningGoals: RunningGoals
    var createdAt: Date
    var lastUpdated: Date
    
    init(
        id: UUID = UUID(),
        personalInfo: PersonalInfo = PersonalInfo(),
        musicPreferences: MusicPreferences = MusicPreferences(),
        runningGoals: RunningGoals = RunningGoals(),
        createdAt: Date = Date(),
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.personalInfo = personalInfo
        self.musicPreferences = musicPreferences
        self.runningGoals = runningGoals
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
}

struct PersonalInfo: Codable, Equatable {
    var displayName: String
    var age: Int?
    var weight: Double? // in kg
    var height: Double? // in cm
    var gender: Gender?
    var fitnessLevel: FitnessLevel?
    var restingHeartRate: Int?
    var maxHeartRate: Int?
    
    init(
        displayName: String = "",
        age: Int? = nil,
        weight: Double? = nil,
        height: Double? = nil,
        gender: Gender? = nil,
        fitnessLevel: FitnessLevel? = nil,
        restingHeartRate: Int? = nil,
        maxHeartRate: Int? = nil
    ) {
        self.displayName = displayName
        self.age = age
        self.weight = weight
        self.height = height
        self.gender = gender
        self.fitnessLevel = fitnessLevel
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
    }
    
    var ageGroup: String {
        guard let age = age else { return "Unknown" }
        switch age {
        case 0..<18: return "Under 18"
        case 18..<25: return "18-24"
        case 25..<35: return "25-34"
        case 35..<45: return "35-44"
        case 45..<55: return "45-54"
        case 55..<65: return "55-64"
        default: return "65+"
        }
    }
}

struct RunningGoals: Codable, Equatable {
    var weeklyDistanceGoal: Double // in km
    var weeklyRunGoal: Int // number of runs
    var targetPace: TimeInterval // in seconds per km
    var preferredRunTime: String // morning, afternoon, evening
    var experienceLevel: ExperienceLevel
    
    init(
        weeklyDistanceGoal: Double = 0.0,
        weeklyRunGoal: Int = 0,
        targetPace: TimeInterval = 0.0,
        preferredRunTime: String = "morning",
        experienceLevel: ExperienceLevel = .beginner
    ) {
        self.weeklyDistanceGoal = weeklyDistanceGoal
        self.weeklyRunGoal = weeklyRunGoal
        self.targetPace = targetPace
        self.preferredRunTime = preferredRunTime
        self.experienceLevel = experienceLevel
    }
    
    enum ExperienceLevel: String, CaseIterable, Codable {
        case beginner = "beginner"
        case intermediate = "intermediate"
        case advanced = "advanced"
        case expert = "expert"
        
        var displayName: String {
            rawValue.capitalized
        }
        
        var description: String {
            switch self {
            case .beginner: return "New to running or returning after a break"
            case .intermediate: return "Regular runner, comfortable with 5K+"
            case .advanced: return "Experienced runner, training for races"
            case .expert: return "Elite runner, competitive athlete"
            }
        }
    }
}

// MARK: - Enums

enum Gender: String, CaseIterable, Codable {
    case male = "male"
    case female = "female"
    case other = "other"
    case preferNotToSay = "prefer_not_to_say"
    
    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

enum FitnessLevel: String, CaseIterable, Codable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case elite = "elite"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var description: String {
        switch self {
        case .beginner:
            return "New to running or returning after a break"
        case .intermediate:
            return "Regular runner with some experience"
        case .advanced:
            return "Experienced runner with good fitness"
        case .elite:
            return "Competitive runner with high fitness level"
        }
    }
}

enum PrimaryGoal: String, CaseIterable, Codable {
    case weightLoss = "weight_loss"
    case fitness = "fitness"
    case raceTraining = "race_training"
    case stressRelief = "stress_relief"
    case social = "social"
    case fun = "fun"
    
    var displayName: String {
        switch self {
        case .weightLoss: return "Weight Loss"
        case .fitness: return "General Fitness"
        case .raceTraining: return "Race Training"
        case .stressRelief: return "Stress Relief"
        case .social: return "Social"
        case .fun: return "Fun"
        }
    }
}
