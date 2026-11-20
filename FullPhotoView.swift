import AVKit
import Photos
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum ViewerContext {
    case normal
    case album(PHAssetCollection)
    case hidden
    case trash
}

struct PhotoViewer: View {
    @ObservedObject var library: PhotoLibrary
    let context: ViewerContext
    @State private var items: [PHAsset]
    @State private var currentID: String?
    @State private var isZoomed = false
    @State private var favoriteIDs: Set<String> = []
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showInfo = false
    @State private var showAlbumPicker = false
    @State private var showDelete = false
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    init(assets: [PHAsset], library: PhotoLibrary, startIndex: Int, context: ViewerContext = .normal) {
        self.library = library
        self.context = context
        let safe = min(max(startIndex, 0), max(assets.count - 1, 0))
        _items = State(initialValue: assets)
        _currentID = State(initialValue: assets.indices.contains(safe) ? assets[safe].localIdentifier : nil)
    }

    private var isTrash: Bool {
        if case .trash = context { return true }
        return false
    }

    private var isHiddenContext: Bool {
        if case .hidden = context { return true }
        return false
    }

    private var currentAsset: PHAsset? {
        items.first { $0.localIdentifier == currentID }
    }

    private var currentIndex: Int {
        items.firstIndex { $0.localIdentifier == currentID } ?? 0
    }

    private var isFavorite: Bool {
        guard let id = currentAsset?.localIdentifier else { return false }
        return favoriteIDs.contains(id)
    }

    private var isPhoto: Bool {
        currentAsset?.mediaType == .image
    }

    var body: some View {
        NavigationStack {
            pager
                .background(Color(.systemBackground).ignoresSafeArea())
                .navigationTitle("\(currentIndex + 1) sur \(items.count)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.backward")
                        }
                    }
                    if !isTrash {
                        ToolbarItem(placement: .topBarTrailing) {
                            moreMenu
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        bottomButtons
                    }
                }
        }
        .onAppear {
            favoriteIDs = Set(items.filter { $0.isFavorite }.map { $0.localIdentifier })
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
                PhotoEditView(asset: asset, library: library) { saved in
                    showEdit = false
                    if saved { removeFromItems(asset) }
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $showDelete, titleVisibility: .visible) {
            deleteButtons
        } message: {
            Text(deleteMessage)
        }
    }

    // Défilement page par page : chaque photo s'arrête toujours pile au centre
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items, id: \.localIdentifier) { asset in
                    PhotoPage(asset: asset) { zoomed in
                        if asset.localIdentifier == currentID {
                            isZoomed = zoomed
                        }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .scrollDisabled(isZoomed)
        .onChange(of: currentID) { _, _ in
            isZoomed = false
        }
    }

    private var moreMenu: some View {
        Menu {
            Button { copyCurrent() } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
            .disabled(!isPhoto)

            Button { duplicateCurrent() } label: {
                Label("Dupliquer", systemImage: "plus.square.on.square")
            }
            .disabled(!isPhoto)

            Button { showAlbumPicker = true } label: {
                Label("Ajouter à un album", systemImage: "rectangle.stack.badge.plus")
            }

            if isHiddenContext {
                Button { unhideCurrent() } label: {
                    Label("Afficher", systemImage: "eye")
                }
            } else {
                Button { hideCurrent() } label: {
                    Label("Masquer", systemImage: "eye.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        if isTrash {
            Button { restoreCurrent() } label: {
                Label("Restaurer", systemImage: "arrow.uturn.backward")
            }
            Spacer()
            Button(role: .destructive) { showDelete = true } label: {
                Image(systemName: "trash")
            }
            .tint(.red)
        } else {
            Button { prepareShare() } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(!isPhoto)

            Spacer()

            Button { toggleFavorite() } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
            }

            Spacer()

            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
            }

            Spacer()

            Button { showEdit = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .disabled(!isPhoto)

            Spacer()

            Button(role: .destructive) { showDelete = true } label: {
                Image(systemName: "trash")
            }
            .tint(.red)
        }
    }

    // MARK: - Suppression

    private var deleteTitle: String {
        isTrash ? "Supprimer définitivement ?" : "Supprimer cet élément ?"
    }

    private var deleteMessage: String {
        if isTrash {
            return "Cet élément sera effacé de ta galerie. iOS te demandera de confirmer."
        }
        return TrashStore.deleteMessage
    }

    @ViewBuilder
    private var deleteButtons: some View {
        if isTrash {
            Button("Supprimer définitivement", role: .destructive) {
                deleteForeverCurrent()
            }
        } else {
            if case .album(let album) = context {
                Button("Supprimer de l'album") {
                    removeFromAlbumCurrent(album)
                }
            }
            Button("Supprimer", role: .destructive) {
                trashCurrent()
            }
        }
    }

    private func removeFromItems(_ asset: PHAsset) {
        guard let index = items.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        items.remove(at: index)
        if items.isEmpty {
            dismiss()
            return
        }
        currentID = items[min(index, items.count - 1)].localIdentifier
        isZoomed = false
    }

    private func trashCurrent() {
        guard let asset = currentAsset else { return }
        library.trash([asset]) {}
        removeFromItems(asset)
    }

    private func removeFromAlbumCurrent(_ album: PHAssetCollection) {
        guard let asset = currentAsset else { return }
        library.remove([asset], from: album) {}
        removeFromItems(asset)
    }

    private func restoreCurrent() {
        guard let asset = currentAsset else { return }
        library.restore([asset]) {}
        removeFromItems(asset)
    }

    private func deleteForeverCurrent() {
        guard let asset = currentAsset else { return }
        library.deletePermanently([asset]) { success in
            if success { removeFromItems(asset) }
        }
    }

    // MARK: - Autres actions

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
        library.hide([asset]) {}
        removeFromItems(asset)
    }

    private func unhideCurrent() {
        guard let asset = currentAsset else { return }
        library.unhide([asset]) {}
        removeFromItems(asset)
    }
}

// Une page = une photo ou une vidéo, avec zoom et déplacement pour les photos
struct PhotoPage: View {
    let asset: PHAsset
    var onZoomChange: (Bool) -> Void = { _ in }
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
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
                photoView(image)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onDisappear {
            player?.pause()
            resetZoom()
        }
    }

    private func photoView(_ image: UIImage) -> some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(min(max(zoom * pinch, 1), 5))
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .updating($pinch) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            zoom = min(max(zoom * value, 1), 5)
                            if zoom <= 1.01 {
                                resetZoom()
                            } else {
                                onZoomChange(true)
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoom > 1 else { return }
                            let maxX = geo.size.width * (zoom - 1) / 2
                            let maxY = geo.size.height * (zoom - 1) / 2
                            offset = CGSize(
                                width: min(max(lastOffset.width + value.translation.width, -maxX), maxX),
                                height: min(max(lastOffset.height + value.translation.height, -maxY), maxY)
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if zoom > 1 {
                            resetZoom()
                        } else {
                            zoom = 2.5
                            onZoomChange(true)
                        }
                    }
                }
        }
    }

    private func resetZoom() {
        zoom = 1
        offset = .zero
        lastOffset = .zero
        onZoomChange(false)
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
                targetSize: CGSize(width: 2048, height: 2048),
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
    let onDone: (Bool) -> Void

    @State private var working: UIImage?
    @State private var preview: UIImage?
    @State private var brightness: Double = 0
    @State private var quarterTurns = 0
    @State private var cropped = false
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    private static let ciContext = CIContext()

    private var hasChanges: Bool {
        brightness != 0 || ((quarterTurns % 4) + 4) % 4 != 0 || cropped
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "sun.min")
                        Slider(value: $brightness, in: -0.5...0.5, step: 0.01)
                            .onChange(of: brightness) { _, _ in applyFilters() }
                        Image(systemName: "sun.max")
                    }

                    HStack(spacing: 20) {
                        Button {
                            quarterTurns -= 1
                            applyFilters()
                        } label: {
                            Label("−90°", systemImage: "rotate.left")
                        }

                        Button {
                            quarterTurns += 1
                            applyFilters()
                        } label: {
                            Label("+90°", systemImage: "rotate.right")
                        }

                        Button {
                            cropped.toggle()
                            applyFilters()
                        } label: {
                            Label(cropped ? "Annuler crop" : "Recadrer", systemImage: "crop")
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
                    Button("Annuler") {
                        dismiss()
                        onDone(false)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(preview == nil || saving || !hasChanges)
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
            targetSize: CGSize(width: 1600, height: 1600),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result {
                DispatchQueue.main.async {
                    working = result
                    preview = result
                }
            }
        }
    }

    // Applique luminosité, rotation et recadrage (une seule fois chacun)
    private func render(_ base: UIImage) -> UIImage? {
        guard var input = CIImage(image: base) else { return nil }

        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.brightness = Float(brightness)
        if let output = filter.outputImage {
            input = output
        }

        let turns = ((quarterTurns % 4) + 4) % 4
        if turns != 0 {
            input = input.transformed(by: CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2))
        }
        input = input.transformed(by: CGAffineTransform(
            translationX: -input.extent.origin.x,
            y: -input.extent.origin.y
        ))

        if cropped {
            let extent = input.extent
            let width = extent.width * 0.85
            let height = extent.height * 0.85
            let rect = CGRect(
                x: extent.minX + (extent.width - width) / 2,
                y: extent.minY + (extent.height - height) / 2,
                width: width,
                height: height
            )
            input = input.cropped(to: rect)
        }

        guard let cg = Self.ciContext.createCGImage(input, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func applyFilters() {
        guard let working, let output = render(working) else { return }
        preview = output
    }

    private func save() {
        saving = true
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                guard let result, let final = render(result) else {
                    saving = false
                    return
                }
                library.saveEditedImage(final, replacing: asset) {
                    saving = false
                    dismiss()
                    onDone(true)
                }
            }
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
