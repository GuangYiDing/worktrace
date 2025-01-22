import SwiftUI

struct TimeDisplayButton: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @State private var showingPicker = false
    @State private var tempHour: Int = 0
    @State private var tempMinute: Int = 0
    @State private var showingAlert = false
    let isEndTime: Bool
    let startHour: Int?
    let startMinute: Int?

    init(
        hour: Binding<Int>, minute: Binding<Int>, isEndTime: Bool = false, startHour: Int? = nil,
        startMinute: Int? = nil
    ) {
        self._hour = hour
        self._minute = minute
        self.isEndTime = isEndTime
        self.startHour = startHour
        self.startMinute = startMinute

        // Set default values for initial setup
        if hour.wrappedValue == 0 && minute.wrappedValue == 0 {
            if isEndTime {
                hour.wrappedValue = 17  // Default end time: 17:00
            } else {
                hour.wrappedValue = 9  // Default start time: 9:00
            }
            minute.wrappedValue = 0
        }
    }

    private func isValidTime() -> Bool {
        if !isEndTime { return true }
        guard let startH = startHour, let startM = startMinute else { return true }

        let startMinutes = startH * 60 + startM
        let endMinutes = tempHour * 60 + tempMinute
        return endMinutes > startMinutes
    }

    var body: some View {
        Button(action: {
            tempHour = hour
            tempMinute = minute
            showingPicker.toggle()
        }) {
            Text(String(format: "%02d:%02d", hour, minute))
                .foregroundColor(.blue)
        }
        .sheet(isPresented: $showingPicker) {
            NavigationView {
                Form {
                    HStack(spacing: 0) {
                        VStack {
                            Picker("点", selection: $tempHour) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour)").tag(hour)
                                }
                            }
                            #if os(iOS)
                                .pickerStyle(.wheel)
                            #else
                                .pickerStyle(.menu)
                            #endif
                            .labelsHidden()
                            .overlay(alignment: .center) {
                                Text("点")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .offset(x: 30)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        VStack {
                            Picker("分", selection: $tempMinute) {
                                ForEach(0..<60) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            #if os(iOS)
                                .pickerStyle(.wheel)
                            #else
                                .pickerStyle(.menu)
                            #endif
                            .labelsHidden()
                            .overlay(alignment: .center) {
                                Text("分")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .offset(x: 30)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .navigationTitle("选择打卡时间")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            if isValidTime() {
                                hour = tempHour
                                minute = tempMinute
                                showingPicker = false
                            } else {
                                showingAlert = true
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .alert("时间设置无效", isPresented: $showingAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("下班时间必须晚于上班时间，请重新设置")
            }
        }
    }
} 