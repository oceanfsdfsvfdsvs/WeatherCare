//
//  RecipientFormSheet.swift
//  WeatherWhisper
//
//  添加/编辑关怀对象的表单
//

import SwiftUI
import PhotosUI
import CoreLocation
import SwiftData

// MARK: - Current Location Helper

private enum LocationFetchError: LocalizedError {
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission is required. Please allow access in Settings."
        case .locationUnavailable:
            return "Unable to get current location. Please try again."
        }
    }
}

private final class CurrentLocationFetcher: NSObject, CLLocationManagerDelegate, ObservableObject {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            try await requestAuthorization()
        } else if status == .denied || status == .restricted {
            throw LocationFetchError.permissionDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func requestAuthorization() async throws {
        try await withCheckedThrowingContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authContinuation else { return }
        authContinuation = nil

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            continuation.resume()
        case .denied, .restricted:
            continuation.resume(throwing: LocationFetchError.permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            continuation.resume(throwing: LocationFetchError.permissionDenied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil

        if let location = locations.first {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: LocationFetchError.locationUnavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: error)
    }
}

/// Recipient 表单 Sheet
struct RecipientFormSheet: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Properties
    
    /// 保存回调
    let onSave: (Recipient) -> Void
    
    /// 编辑模式（可选，传入已有 Recipient）
    var existingRecipient: Recipient?
    
    // MARK: - State
    
    /// 昵称（必填）
    @State private var nickname: String = ""
    
    /// 头像图片
    @State private var avatarImage: UIImage?
    
    /// 相册选择的 Item
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    /// 城市名称
    @State private var cityName: String = ""

    /// 初始城市名称（用于判断是否需要重新地理编码）
    @State private var originalCityName: String = ""
    
    /// 纬度
    @State private var latitude: Double = 0
    
    /// 经度
    @State private var longitude: Double = 0

    
    /// 是否正在获取位置
    @State private var isLocating = false
    
    /// 是否正在保存（包含地理编码/写入）
    @State private var isSaving = false
    
    /// 错误信息
    @State private var errorMessage: String?

    /// 当前位置获取器
    @StateObject private var locationFetcher = CurrentLocationFetcher()
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // 头像选择
                Section {
                    HStack {
                        Spacer()
                        
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            avatarPreview
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                
                // 基本信息
                Section("Basic info") {
                    TextField("Name (required)", text: $nickname)
                }
                
                // 位置信息
                Section("Location") {
                    TextField("City", text: $cityName)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latitude: \(latitude, specifier: \"%.4f\")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Longitude: \(longitude, specifier: \"%.4f\")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: useCurrentLocation) {
                            if isLocating {
                                ProgressView()
                            } else {
                                Label("Use current location", systemImage: "location.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLocating)
                    }
                }
                
                // 错误信息
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingRecipient == nil ? "Add recipient" : "Edit recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { save() }) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isValid || isSaving || isLocating)
                }
            }
            .onAppear {
                if let recipient = existingRecipient {
                    nickname = recipient.nickname
                    cityName = recipient.cityName
                    latitude = recipient.latitude
                    longitude = recipient.longitude
                    originalCityName = recipient.cityName
                    // 加载已有头像
                    if let data = recipient.avatarData {
                        avatarImage = UIImage(data: data)
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                loadImage(from: newValue)
            }
        }
    }
    
    // MARK: - Views
    
    /// 头像预览视图
    @ViewBuilder
    private var avatarPreview: some View {
        ZStack {
            if let image = avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                // 显示首字母或相机图标
                if nickname.isEmpty {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(String(nickname.prefix(1)))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            
            // 编辑提示
            Circle()
                .stroke(.white.opacity(0.6), lineWidth: 3)
                .frame(width: 100, height: 100)
            
            // 小相机图标
            Image(systemName: "camera.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, .blue)
                .offset(x: 35, y: 35)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Computed Properties
    
    /// 表单是否有效（昵称必填 + 位置必填）
    private var isValid: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Actions
    
    /// 从相册加载图片
    private func loadImage(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    avatarImage = uiImage
                }
            }
        }
    }
    
    /// 使用当前位置
    private func useCurrentLocation() {
        isLocating = true
        errorMessage = nil

        Task {
            do {
                let location = try await locationFetcher.requestLocation()
                let displayName = (try? await reverseGeocodeLocation(location: location)) ?? "Current location"

                await MainActor.run {
                    latitude = location.coordinate.latitude
                    longitude = location.coordinate.longitude
                    cityName = displayName
                    originalCityName = displayName
                    isLocating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLocating = false
                }
            }
        }
    }
    
    /// 保存
    private func save() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityChanged = trimmedCity.caseInsensitiveCompare(originalCityName) != .orderedSame
        
        // 将头像图片转换为 Data（压缩以节省空间）
        let avatarData = avatarImage?.jpegData(compressionQuality: 0.8)
        
        isSaving = true
        errorMessage = nil

        Task {
            do {
                // 若经纬度缺失，则先对输入的城市/地址做地理编码
                if latitude == 0 || longitude == 0 || cityChanged {
                    let resolved = try await geocodeLocation(query: trimmedCity)
                    await MainActor.run {
                        cityName = resolved.displayName
                        latitude = resolved.latitude
                        longitude = resolved.longitude
                    }
                }

                await MainActor.run {
                    commitSave(
                        nickname: trimmedNickname,
                        cityName: cityName,
                        latitude: latitude,
                        longitude: longitude,
                        avatarData: avatarData
                    )
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    /// 地址/城市地理编码（将文本解析为经纬度）
    /// - Parameter query: 用户输入的城市名/地址
    /// - Returns: 解析后的展示名与经纬度
    private func geocodeLocation(query: String) async throws -> (displayName: String, latitude: Double, longitude: Double) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw NSError(domain: "RecipientFormSheet", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Please enter a city or address."
            ])
        }

        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(trimmed)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw NSError(domain: "RecipientFormSheet", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No matching location found. Please refine your input."
            ])
        }

        // 优先用 locality（城市），其次 administrativeArea（州/省），再到 name（地点名），最后回退用户输入
        let displayName = placemark.locality
        ?? placemark.administrativeArea
        ?? placemark.name
        ?? trimmed

        return (displayName: displayName, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// 反向地理编码（经纬度 -> 城市名称）
    /// - Parameter location: 当前位置
    /// - Returns: 展示名称
    private func reverseGeocodeLocation(location: CLLocation) async throws -> String {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            throw LocationFetchError.locationUnavailable
        }

        let displayName = placemark.locality
        ?? placemark.administrativeArea
        ?? placemark.name
        ?? "Current location"

        return displayName
    }

    /// 提交保存（写入/更新 Recipient，并触发回调）
    /// - Parameters:
    ///   - nickname: 昵称
    ///   - cityName: 城市名称（已解析/或用户输入）
    ///   - latitude: 纬度
    ///   - longitude: 经度
    ///   - avatarData: 头像数据（可选）
    private func commitSave(
        nickname: String,
        cityName: String,
        latitude: Double,
        longitude: Double,
        avatarData: Data?
    ) {
        let recipient: Recipient
        
        if let existing = existingRecipient {
            existing.update(
                nickname: nickname,
                avatarData: .some(avatarData), // 使用 .some 包装，表示要更新
                cityName: cityName,
                latitude: latitude,
                longitude: longitude
            )
            recipient = existing
        } else {
            recipient = Recipient(
                nickname: nickname,
                avatarData: avatarData,
                cityName: cityName,
                latitude: latitude,
                longitude: longitude
            )
        }
        
        // 1) 交给上层插入/处理（新增时会 insert 到 SwiftData）
        onSave(recipient)

        // 通知页面：该关怀人信息已更新（尤其是 location 变更时需要强制刷新天气/温度/卡片）
        NotificationCenter.default.post(
            name: .recipientUpdated,
            object: nil,
            userInfo: ["recipientId": recipient.id]
        )

        // 2) 立即同步 Widget 的“关怀人索引”（头像/昵称/location 等变更都能及时反映）
        syncWidgetRecipientsIndex()

        // 3) 若位置发生变化或新增关怀人：拉取一次最新天气并同步到 Widget（温度/图标及时更新）
        syncWidgetWeatherSnapshotIfPossible(for: recipient)
        dismiss()
    }

    /// 同步 Widget：关怀人索引（昵称/头像）
    /// - Note: 这里直接从 SwiftData 拉取最新 recipients，确保顺序与 Home/列表一致（updatedAt 倒序）
    private func syncWidgetRecipientsIndex() {
        let descriptor = FetchDescriptor<Recipient>(
            sortBy: [SortDescriptor(\Recipient.updatedAt, order: .reverse)]
        )
        if let recipients = try? modelContext.fetch(descriptor) {
            WidgetSyncService.syncRecipientsIndex(recipients: recipients)
        }
    }

    /// 同步 Widget：天气快照（温度/图标）
    /// - Parameter recipient: 关怀人
    /// - Note: 小组件“实时”能力受系统节流影响，但在 App 前台/刚保存时一般会很及时
    private func syncWidgetWeatherSnapshotIfPossible(for recipient: Recipient) {
        // 经纬度缺失时不拉天气（避免不必要的网络/错误）
        guard recipient.latitude != 0, recipient.longitude != 0 else { return }

        Task {
            do {
                let weather = try await WeatherProvider.shared.fetchWeather(for: recipient)
                let trigger = TriggerResolver.resolve(from: weather)
                await MainActor.run {
                    WidgetSyncService.syncWeather(recipient: recipient, weather: weather, triggerType: trigger)
                }
            } catch {
                // 天气拉取失败不阻塞保存；Widget 会继续显示上次数据/占位
                #if DEBUG
                print("[RecipientFormSheet] Widget weather sync failed: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RecipientFormSheet(onSave: { _ in })
}
