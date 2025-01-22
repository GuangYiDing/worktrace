import Foundation

public enum WorkScheduleType: String, Codable {
    case doubleWeekend = "双休"
    case singleWeekend = "单休"
    case alternatingWeekend = "大小周"
    case custom = "自定义"
}

public struct WorkTime: Codable {
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    
    public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }
}

public struct CustomWeekendSettings: Codable {
    public var restDays: Set<Int> // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    
    public init(restDays: Set<Int> = [1, 7]) { // Default to Saturday and Sunday
        self.restDays = restDays
    }
} 