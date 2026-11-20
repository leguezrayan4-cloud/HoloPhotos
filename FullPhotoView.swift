import AVKit
import Photos
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct PhotoViewer: View {
    let assets: [PHAsset]
    @ObservedObject var library: PhotoLibrary
    @State private var currentIndex: Int
    @State private var favoriteIDs: Set<String> = []
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showInfo = false
    @State private var showAlbumPicker = false
    @State private var showDelete = false
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    init(assets: [PHAsset], library: PhotoLibrary, startIndex: Int) {
        self.assets = assets
        self.library = library
        let safe = min(max(startIndex, 0), max(assets.count - 1, 0))
        _currentIndex = State(initialValue: safe)
    }

    private var currentAsset: PHAsset? {
        assets.indices.contains(currentIndex) ? assets[currentIndex] : nil
    }

    private var isFavorite: Bool {
        guard let id = currentAsset?.localIdentifier else { return false }
        return favoriteIDs.contains(id)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                    PhotoPage(asset: asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("\(currentIndex + 1) sur \(assets.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.backward")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button { prepareShare() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(currentAsset?.mediaType != .image)

                    Spacer()

                    Button { toggleFavorite() } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                    }

                    Spacer()

                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                    }

                    Spacer()

                    Menu {
                        Button { copyCurrent() } label: {
                            Label("Copier", systemImage: "doc.on.doc")
                        }
                        .disabled(currentAsset?.mediaType != .image)

                        Button { duplicateCurrent() } label: {
                            Label("Dupliquer", systemImage: "plus.square.on.square")
                        }
                        .disabled(currentAsset?.mediaType != .image)

                        Button { showAlbumPicker = true } label: {
                            Label("Ajouter à un album", systemImage: "rectangle.stack.badge.plus")
                        }

                        Button { hideCurrent() } label: {
                            Label("Masquer", systemImage: "eye.slash")
                        }

                        Button {
                            showEdit = true
                        } label: {
                            Label("Retoucher", systemImage: "slider.horizontal.3")
                        }
                        .disabled(currentAsset?.mediaType != .image)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Spacer()

                    Button(role: .destructive) { showDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .onAppear {
            favoriteIDs = Set(assets.filter { $0.isFavorite }.map { $0.localIdentifier })
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showInfo) {
            if let asset = currentAsset {
                PhotoInfoView(asset: asset)
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            if let asset = currentAsset {
                AlbumPicker(library: library, assets: [asset]) {}
            }
        }
        .fullScreenCover(isPresented: $showEdit) {
            if let asset = currentAsset {
                PhotoEditView(asset: asset, library: library) {
                    showEdit = false
                }
            }
        }
        .confirmationDialog("Supprimer cet élément ?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let asset = currentAsset {
                    library.delete([asset]) { dismiss() }
                }
            }
        } message: {
            Text("Il ira dans « Supprimés récemment » pendant 30 jours.")
        }
    }

    private func toggleFavorite() {
        guard let asset = currentAsset else { return }
        let newValue = !isFavorite
        if newValue {
            favoriteIDs.insert(asset.localIdentifier)
        } else {
            favoriteIDs.remove(asset.localIdentifier)
        }
        library.setFavorite(asset, newValue)
    }

    private func prepareShare() {
        guard let asset = currentAsset else { return }
        library.loadImages([asset]) { images in
            shareItems = images
            showShare = true
        }
    }

    private func copyCurrent() {
        guard let asset = currentAsset else { return }
        library.loadImages([asset]) { images in
            UIPasteboard.general.images = images
        }
    }

    private func duplicateCurrent() {
        guard let asset = currentAsset else { return }
        library.duplicate([asset]) {}
    }

    private func hideCurrent() {
        guard let asset = currentAsset else { return }
        library.hide([asset]) { dismiss() }
    }
}

// Une page = une photo ou une vidéo, avec zoom pour les photos
struct PhotoPage: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        Group {
            if asset.mediaType == .video {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView()
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom * pinch)
                    .gesture(
                        MagnificationGesture()
                            .updating($pinch) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                zoom = min(max(zoom * value, 1), 4)
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            zoom = 1
                        }
                    }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
    }

    private func load() {
        if asset.mediaType == .video {
            guard player == nil else { return }
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard let item else { return }
                DispatchQueue.main.async {
                    player = AVPlayer(playerItem: item)
                }
            }
        } else {
            guard image == nil else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { result, _ in
                if let result {
                    DispatchQueue.main.async {
                        image = result
                    }
                }
            }
        }
    }
}

// MARK: - Retouches (luminosité, rotation, recadrage simple)

struct PhotoEditView: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibrary
    let onDone: () -> Void

    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var brightness: Double = 0
    @State private var rotation: Angle = .zero
    @State private var cropScale: CGFloat = 1
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(rotation)
                        .scaleEffect(cropScale)
                        .clipped()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(spacing: 16) {
                    // Luminosité
                    HStack {
                        Image(systemName: "sun.min")
                        Slider(value: $brightness, in: -0.5...0.5, step: 0.01)
                            .onChange(of: brightness) { _, _ in applyFilters() }
                        Image(systemName: "sun.max")
                    }

                    // Rotation
                    HStack(spacing: 20) {
                        Button {
                            withAnimation {
                                rotation -= .degrees(90)
                            }
                            applyFilters()
                        } label: {
                            Label("−90°", systemImage: "rotate.left")
                        }

                        Button {
                            withAnimation {
                                rotation += .degrees(90)
                            }
                            applyFilters()
                        } label: {
                            Label("+90°", systemImage: "rotate.right")
                        }

                        Button {
                            withAnimation {
                                cropScale = cropScale == 1 ? 0.85 : 1
                            }
                        } label: {
                            Label(cropScale == 1 ? "Recadrer" : "Annuler crop", systemImage: "crop")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Retoucher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss(); onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        save()
                    }
                    .disabled(preview == nil || saving)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    original = result
                    preview = result
                }
            }
        }
    }

    private func applyFilters() {
        guard let original else { return }
        let ciImage = CIImage(image: original)
        guard var input = ciImage else { return }

        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.brightness = Float(brightness)
        if let output = filter.outputImage {
            input = output
        }

        // Rotation via transform
        let radians = CGFloat(rotation.radians)
        if abs(radians) > 0.01 {
            input = input.transformed(by: CGAffineTransform(rotationAngle: radians))
        }

        let context = CIContext()
        if let cg = context.createCGImage(input, from: input.extent) {
            preview = UIImage(cgImage: cg)
        }
    }

    private func save() {
        guard let image = preview else { return }
        saving = true
        // On applique aussi le scale de crop approximatif
        let final: UIImage
        if cropScale < 1 {
            let size = image.size
            let cropW = size.width * cropScale
            let cropH = size.height * cropScale
            let rect = CGRect(
                x: (size.width - cropW) / 2,
                y: (size.height - cropH) / 2,
                width: cropW,
                height: cropH
            )
            if let cg = image.cgImage?.cropping(to: rect) {
                final = UIImage(cgImage: cg)
            } else {
                final = image
            }
        } else {
            final = image
        }

        library.saveEditedImage(final, replacing: asset) {
            saving = false
            dismiss()
            onDone()
        }
    }
}

struct PhotoInfoView: View {
    let asset: PHAsset

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Date") {
                    Text(asset.creationDate?.formatted(date: .long, time: .shortened) ?? "Inconnue")
                }
                LabeledContent("Dimensions") {
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                }
                if asset.mediaType == .video {
                    LabeledContent("Durée") {
                        Text(String(format: "%.0f s", asset.duration))
                    }
                }
                if let location = asset.location {
                    LabeledContent("Position") {
                        Text(String(format: "%.4f, %.4f",
                                    location.coordinate.latitude,
                                    location.coordinate.longitude))
                    }
                }
            }
            .navigationTitle("Infos")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
