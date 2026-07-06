import SwiftUI
import SwiftData
import PhotosUI

struct PlayerProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let player: Player?

    @State private var name: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showDeleteConfirmation = false
    @State private var localization = LocalizationManager.shared

    private var isEditing: Bool { player != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section(localization.localized("player.sectionName")) {
                TextField(localization.localized("player.namePlaceholder"), text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
            }

            Section(localization.localized("player.sectionPhoto")) {
                HStack {
                    Spacer()
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        let initial = name.first.map(String.init) ?? "?"
                        Circle()
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .overlay {
                                Text(initial.uppercased())
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)

                // Resolved outside the picker label: PhotosPicker's label
                // closure is nonisolated in the iOS 18.5 SDK, so it can't
                // touch the main-actor LocalizationManager directly.
                let choosePhotoLabel = localization.localized("player.choosePhoto")
                PhotosPicker(
                    selection: $photoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(choosePhotoLabel, systemImage: "photo.on.rectangle")
                }

                if photoData != nil {
                    Button(localization.localized("player.removePhoto"), role: .destructive) {
                        photoData = nil
                        photoItem = nil
                    }
                }
            }

            if isEditing {
                Section {
                    Button(localization.localized("player.delete"), role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(isEditing ? localization.localized("player.editTitle") : localization.localized("player.newTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localization.localized("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(localization.localized("common.save")) { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear {
            if let player {
                name = player.name
                photoData = player.photoData
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    photoData = resizedImageData(from: data)
                }
            }
        }
        .alert(localization.localized("player.deleteAlert"), isPresented: $showDeleteConfirmation) {
            Button(localization.localized("player.delete"), role: .destructive) { deletePlayer() }
            Button(localization.localized("common.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: localization.localized("player.deleteMessage"), name))
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let player {
            player.name = trimmedName
            player.photoData = photoData
        } else {
            let newPlayer = Player()
            newPlayer.name = trimmedName
            newPlayer.photoData = photoData
            modelContext.insert(newPlayer)
        }

        dismiss()
    }

    private func deletePlayer() {
        if let player {
            modelContext.delete(player)
        }
        dismiss()
    }

    // MARK: - Image Resizing

    private func resizedImageData(from data: Data) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 200
        let size = uiImage.size
        let scale: CGFloat
        if size.width > size.height {
            scale = maxDimension / size.width
        } else {
            scale = maxDimension / size.height
        }

        if scale >= 1.0 {
            return uiImage.jpegData(compressionQuality: 0.7)
        }

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
