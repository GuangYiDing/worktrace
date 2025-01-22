import Foundation
import Network

@Observable
class NTPManager {
    static let shared = NTPManager()
    private let ntpServers = [
        "ntp1.aliyun.com",
        "ntp2.aliyun.com",
        "ntp3.aliyun.com",
        "ntp4.aliyun.com",
        "ntp5.aliyun.com",
        "ntp6.aliyun.com",
        "ntp7.aliyun.com",
        "ntp.ntsc.ac.cn"
    ]
    
    private let timeZone = TimeZone.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    private init() {}
    
    func checkTimeSync() async -> (isValid: Bool, serverTime: Date?) {
        for server in ntpServers {
            if let result = await checkNTPTime(server: server) {
                let timeDifference = abs(result.timeIntervalSince(Date()))
                let localTimeStr = dateFormatter.string(from: Date())
                let serverTimeStr = dateFormatter.string(from: result)
                
                print("System TimeZone: \(timeZone.identifier)")
                print("Local Time: \(localTimeStr)")
                print("Server Time: \(serverTimeStr)")
                print("Time Difference: \(timeDifference) seconds")
                
                if timeDifference > 30 {
                    return (false, result)
                }
                return (true, result)
            }
        }
        return (false, nil)
    }
    
    private func checkNTPTime(server: String) async -> Date? {
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.worktrace.ntp")
            
            queue.async {
                var timeInfo = timeval()
                let serverAddress = server
                
                guard let hostInfo = serverAddress.withCString({ cString -> UnsafeMutablePointer<hostent>? in
                    return gethostbyname(cString)
                }) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                var serverAddress_in = sockaddr_in()
                serverAddress_in.sin_family = sa_family_t(AF_INET)
                serverAddress_in.sin_port = UInt16(123).bigEndian
                
                memcpy(&serverAddress_in.sin_addr.s_addr, hostInfo.pointee.h_addr_list[0], 4)
                
                let sock = socket(AF_INET, SOCK_DGRAM, 0)
                if sock < 0 {
                    continuation.resume(returning: nil)
                    return
                }
                
                var ntpData = [UInt8](repeating: 0, count: 48)
                ntpData[0] = 0x1B
                
                let addr = withUnsafePointer(to: &serverAddress_in) {
                    UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self)
                }
                
                let result = sendto(sock, &ntpData, ntpData.count, 0, addr, socklen_t(MemoryLayout<sockaddr_in>.size))
                if result < 0 {
                    close(sock)
                    continuation.resume(returning: nil)
                    return
                }
                
                var tv = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                
                let length = recvfrom(sock, &ntpData, ntpData.count, 0, nil, nil)
                close(sock)
                
                if length < 0 {
                    continuation.resume(returning: nil)
                    return
                }
                
                let integerPart = UInt32(ntpData[40]) << 24 | UInt32(ntpData[41]) << 16 | UInt32(ntpData[42]) << 8 | UInt32(ntpData[43])
                let fractionalPart = UInt32(ntpData[44]) << 24 | UInt32(ntpData[45]) << 16 | UInt32(ntpData[46]) << 8 | UInt32(ntpData[47])
                
                let milliseconds = Double(integerPart) * 1000 + Double(fractionalPart) * 1000 / 0x100000000
                
                // NTP时间从1900年开始，需要加上这段时间差
                let timeInterval = (milliseconds / 1000.0) - 2208988800
                let date = Date(timeIntervalSince1970: timeInterval)
                
                continuation.resume(returning: date)
            }
        }
    }
} 