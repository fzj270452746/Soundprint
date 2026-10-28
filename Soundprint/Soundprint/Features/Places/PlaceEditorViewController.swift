//
//  PlaceEditorViewController.swift
//  Soundprint
//
//  新建/编辑地点。位置为可选项，只有在用户主动点击时才请求权限。
//

import MapKit
import UIKit

final class PlaceEditorViewController: SPViewController {
    enum Mode {
        case create
        case edit(PlaceEntity)
    }

    private let mode: Mode
    private let onSaved: (PlaceEntity, Bool) -> Void
    private let library = LibraryService.shared

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView(axis: .vertical, spacing: 16)
    private let bottomBar = UIView()
    private let saveButton = SPButton(title: "Save Place", symbol: "checkmark", style: .primary)
    private let nameField = SPTextFieldView(title: "Place Name", placeholder: "e.g. Home study, seaside promenade", isRequired: true)
    private let kindPicker = SPPlaceKindPicker()
    private let tagFlow = SPTagFlowView()
    private let noteView = SPTextView(title: "Notes About This Place", placeholder: "What sounds you hear here, and how they change through the day.", maxLength: 600)
    private let locationButton = SPButton(title: "Get Current Location", symbol: "location.fill", style: .secondary)
    private let coordinateLabel = UILabel()
    private let accuracyLabel = UILabel()
    private let mapView = MKMapView()
    private let mapContainer = UIView()
    private let precisionStack = UIStackView(axis: .horizontal, spacing: 7)
    private let tagSuggestionScroll = UIScrollView()
    private let tagSuggestionStack = UIStackView(axis: .horizontal, spacing: 7)

    private var precisionChips: [SPFilterChip] = []
    private var tags: [String] = []
    private var coordinate: Coordinate?
    private var accuracy: Double?
    private var precision: LocationPrecision = .none
    private var selectedKind: PlaceKind = .other
    private var isDirty = false
    private var isSaving = false

    init(mode: Mode, onSaved: @escaping (PlaceEntity, Bool) -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureFromMode()
        buildInterface()
        populate()
        mapView.delegate = self
        isModalInPresentation = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private var editingPlace: PlaceEntity? {
        if case let .edit(place) = mode { return place }
        return nil
    }

    private var isCreating: Bool { editingPlace == nil }

    // MARK: - 数据

    private func configureFromMode() {
        guard let place = editingPlace else {
            selectedKind = .other
            return
        }
        nameField.text = place.name
        selectedKind = place.kind
        tags = place.tags
        noteView.text = place.note ?? ""
        coordinate = place.coordinate
        precision = place.precision
        accuracy = nil
    }

    private func populate() {
        kindPicker.select(selectedKind, notify: false)
        tagFlow.tags = tags
        tagFlow.showsAddButton = true
        tagFlow.removable = true
        rebuildSuggestions()
        updateLocationUI(animated: false)
        updatePrecisionChips()
    }

    // MARK: - 界面

    private func buildInterface() {
        title = isCreating ? "New Place" : "Edit Place"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        buildBasicCard()
        buildTagsCard()
        buildNoteCard()
        buildLocationCard()

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = SPColor.paper
        let border = UIView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.backgroundColor = SPColor.hairline
        bottomBar.addSubview(border)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        bottomBar.addSubview(saveButton)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SPMetric.screenInset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SPMetric.screenInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * SPMetric.screenInset),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            border.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            border.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5),

            saveButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: SPMetric.screenInset),
            saveButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -SPMetric.screenInset),
            saveButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),
            saveButton.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])

        nameField.onTextChanged = { [weak self] _ in self?.markDirty() }
        noteView.onTextChanged = { [weak self] _ in self?.markDirty() }
        kindPicker.onChange = { [weak self] kind in
            self?.selectedKind = kind
            self?.markDirty()
        }
        tagFlow.onAdd = { [weak self] in self?.addTagPrompt() }
        tagFlow.onRemove = { [weak self] index in
            guard let self, self.tags.indices.contains(index) else { return }
            self.tags.remove(at: index)
            self.tagFlow.tags = self.tags
            self.rebuildSuggestions()
            self.markDirty()
        }
        locationButton.addTarget(self, action: #selector(locationTapped), for: .touchUpInside)
    }

    private func buildBasicCard() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 18)
        stack.addArrangedSubview(nameField)

        let kindLabel = UILabel()
        kindLabel.text = "Place Type"
        kindLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        kindLabel.textColor = SPColor.secondaryInk
        kindLabel.adjustsFontForContentSizeCategory = true
        let kindStack = UIStackView(axis: .vertical, spacing: 9)
        kindStack.addArrangedSubview(kindLabel)
        kindStack.addArrangedSubview(kindPicker)
        stack.addArrangedSubview(kindStack)
        card.addContent(stack, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
        contentStack.addArrangedSubview(card)
    }

    private func buildTagsCard() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 11)
        let titleLabel = UILabel()
        titleLabel.text = "Tags"
        titleLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true

        tagFlow.onAdd = { [weak self] in self?.addTagPrompt() }
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(tagFlow)

        let suggestionLabel = UILabel()
        suggestionLabel.text = "Commonly Used Tags"
        suggestionLabel.font = SPFont.text(10.5, weight: .medium, relativeTo: .caption2)
        suggestionLabel.textColor = SPColor.tertiaryInk
        suggestionLabel.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(suggestionLabel)

        tagSuggestionScroll.translatesAutoresizingMaskIntoConstraints = false
        tagSuggestionScroll.showsHorizontalScrollIndicator = false
        tagSuggestionStack.translatesAutoresizingMaskIntoConstraints = false
        tagSuggestionScroll.addSubview(tagSuggestionStack)
        NSLayoutConstraint.activate([
            tagSuggestionScroll.heightAnchor.constraint(equalToConstant: 30),
            tagSuggestionStack.leadingAnchor.constraint(equalTo: tagSuggestionScroll.contentLayoutGuide.leadingAnchor),
            tagSuggestionStack.trailingAnchor.constraint(equalTo: tagSuggestionScroll.contentLayoutGuide.trailingAnchor),
            tagSuggestionStack.topAnchor.constraint(equalTo: tagSuggestionScroll.contentLayoutGuide.topAnchor),
            tagSuggestionStack.bottomAnchor.constraint(equalTo: tagSuggestionScroll.contentLayoutGuide.bottomAnchor),
            tagSuggestionStack.heightAnchor.constraint(equalTo: tagSuggestionScroll.frameLayoutGuide.heightAnchor)
        ])
        stack.addArrangedSubview(tagSuggestionScroll)
        card.addContent(stack, insets: UIEdgeInsets(top: 17, left: 16, bottom: 17, right: 16))
        contentStack.addArrangedSubview(card)
    }

    private func buildNoteCard() {
        let card = SPCardView(style: .surface)
        card.addContent(noteView, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
        contentStack.addArrangedSubview(card)
    }

    private func buildLocationCard() {
        let card = SPCardView(style: .surface)
        let stack = UIStackView(axis: .vertical, spacing: 12)

        let header = UIStackView(axis: .horizontal, spacing: 10, alignment: .center)
        let titleStack = UIStackView(axis: .vertical, spacing: 2)
        let titleLabel = UILabel()
        titleLabel.text = "Location"
        titleLabel.font = SPFont.text(12, weight: .semibold, relativeTo: .caption1)
        titleLabel.textColor = SPColor.secondaryInk
        titleLabel.adjustsFontForContentSizeCategory = true
        let descriptionLabel = UILabel()
        descriptionLabel.text = "Optional. You can save a place without a location."
        descriptionLabel.font = SPFont.text(11, weight: .regular, relativeTo: .caption2)
        descriptionLabel.textColor = SPColor.tertiaryInk
        descriptionLabel.adjustsFontForContentSizeCategory = true
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(descriptionLabel)
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(UIView())
        let lock = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
        lock.tintColor = SPColor.moss
        header.addArrangedSubview(lock)
        stack.addArrangedSubview(header)

        for (index, precision) in LocationPrecision.allCases.enumerated() {
            let chip = SPFilterChip(title: precision.title)
            chip.tag = index
            chip.addTarget(self, action: #selector(precisionTapped(_:)), for: .touchUpInside)
            precisionChips.append(chip)
            precisionStack.addArrangedSubview(chip)
        }
        precisionStack.addArrangedSubview(UIView())
        stack.addArrangedSubview(precisionStack)

        coordinateLabel.font = SPFont.mono(12, weight: .medium, relativeTo: .subheadline)
        coordinateLabel.textColor = SPColor.ink
        coordinateLabel.numberOfLines = 0
        coordinateLabel.adjustsFontForContentSizeCategory = true
        accuracyLabel.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        accuracyLabel.textColor = SPColor.tertiaryInk
        accuracyLabel.adjustsFontForContentSizeCategory = true

        let coordStack = UIStackView(axis: .vertical, spacing: 3)
        coordStack.addArrangedSubview(coordinateLabel)
        coordStack.addArrangedSubview(accuracyLabel)
        stack.addArrangedSubview(coordStack)

        mapContainer.translatesAutoresizingMaskIntoConstraints = false
        mapContainer.layer.cornerRadius = 14
        mapContainer.layer.cornerCurve = .continuous
        mapContainer.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapContainer.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: mapContainer.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: mapContainer.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: mapContainer.bottomAnchor),
            mapContainer.heightAnchor.constraint(equalToConstant: 148)
        ])
        stack.addArrangedSubview(mapContainer)

        let mapButton = SPTextButton(title: "Open in Maps")
        mapButton.addTarget(self, action: #selector(openMapTapped), for: .touchUpInside)
        mapButton.contentHorizontalAlignment = .leading
        stack.addArrangedSubview(mapButton)

        locationButton.addTarget(self, action: #selector(locationTapped), for: .touchUpInside)
        stack.addArrangedSubview(locationButton)

        let note = UILabel()
        note.text = "Location data is stored only on this device. When sharing or exporting, you choose each time whether to include exact coordinates."
        note.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
        note.textColor = SPColor.tertiaryInk
        note.numberOfLines = 0
        note.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(note)

        card.addContent(stack, insets: UIEdgeInsets(top: 17, left: 16, bottom: 17, right: 16))
        contentStack.addArrangedSubview(card)
    }

    // MARK: - 标签

    private func rebuildSuggestions() {
        tagSuggestionStack.arrangedSubviews.forEach {
            tagSuggestionStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for tag in SPSuggestions.tags where !tags.contains(tag) {
            let chip = SPTagView(text: tag, symbol: "plus", color: SPColor.secondaryInk, background: SPColor.sunken)
            chip.onTap = { [weak self] in
                guard let self else { return }
                self.tags = TagCodec.cleanedTags(self.tags + [tag])
                self.tagFlow.tags = self.tags
                self.rebuildSuggestions()
                self.markDirty()
                SPHaptic.selection()
            }
            tagSuggestionStack.addArrangedSubview(chip)
        }
        if tagSuggestionStack.arrangedSubviews.isEmpty {
            let label = UILabel()
            label.text = "All Tags Added"
            label.font = SPFont.text(10.5, weight: .regular, relativeTo: .caption2)
            label.textColor = SPColor.tertiaryInk
            tagSuggestionStack.addArrangedSubview(label)
        }
    }

    private func addTagPrompt() {
        guard tags.count < 12 else {
            presentAlert(title: "Tag Limit Reached", message: "You can add up to 12 tags. Remove one before adding another.")
            return
        }
        let alert = UIAlertController(title: "Add Tag", message: "Enter up to 24 characters.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "e.g. Morning, quiet, waterside"
            field.font = SPFont.text(15)
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self, let value = alert?.textFields?.first?.text else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !self.tags.contains(trimmed) else { return }
            self.tags = TagCodec.cleanedTags(self.tags + [trimmed])
            self.tagFlow.tags = self.tags
            self.rebuildSuggestions()
            self.markDirty()
        })
        present(alert, animated: true)
    }

    // MARK: - 位置

    private func updatePrecisionChips() {
        for chip in precisionChips {
            let value = LocationPrecision.allCases[chip.tag]
            chip.selectedState = value == precision
        }
    }

    @objc private func precisionTapped(_ sender: SPFilterChip) {
        let value = LocationPrecision.allCases[sender.tag]
        precision = value
        if value == .none {
            coordinate = nil
            accuracy = nil
        }
        updatePrecisionChips()
        updateLocationUI(animated: true)
        markDirty()
        SPHaptic.selection()
    }

    @objc private func locationTapped() {
        locationButton.isEnabled = false
        locationButton.title = "Getting Current Location…"
        LocationService.shared.requestCurrentLocation { [weak self] result in
            guard let self else { return }
            self.locationButton.isEnabled = true
            self.locationButton.title = "Get Current Location"
            switch result {
            case .success(let location):
                self.coordinate = Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                self.accuracy = location.horizontalAccuracy
                self.precision = .precise
                self.updatePrecisionChips()
                self.updateLocationUI(animated: true)
                self.markDirty()
                SPHaptic.success()
            case .failure(let error):
                self.presentLocationError(error)
            }
        }
    }

    private func presentLocationError(_ error: LocationError) {
        let alert = UIAlertController(title: "Couldn't Get Location", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        if case .permissionDenied = error {
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        }
        present(alert, animated: true)
    }

    private func updateLocationUI(animated: Bool) {
        let hasCoordinate = coordinate != nil && precision != .none
        mapContainer.isHidden = !hasCoordinate
        coordinateLabel.isHidden = !hasCoordinate
        accuracyLabel.isHidden = !hasCoordinate

        if let coordinate {
            coordinateLabel.text = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
            if let accuracy {
                accuracyLabel.text = "Accuracy approx. \(Int(max(1, accuracy.rounded()))) m · \(precision == .approximate ? "Rounded to about 1 km when saved" : "Saved as exact coordinates")"
            } else if editingPlace != nil {
                accuracyLabel.text = precision.title
            }
            updateMap(coordinate: coordinate)
        } else {
            coordinateLabel.text = nil
            accuracyLabel.text = nil
        }
        if animated {
            UIView.animate(withDuration: 0.22) {
                self.view.layoutIfNeeded()
            }
        }
    }

    private func updateMap(coordinate: Coordinate) {
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        annotation.title = nameField.text.isEmpty ? "Recording Location" : nameField.text
        mapView.addAnnotation(annotation)
        let region = MKCoordinateRegion(
            center: annotation.coordinate,
            latitudinalMeters: precision == .approximate ? 2_400 : 500,
            longitudinalMeters: precision == .approximate ? 2_400 : 500
        )
        mapView.setRegion(region, animated: false)
    }

    @objc private func openMapTapped() {
        guard let coordinate else { return }
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = nameField.text.isEmpty ? "Soundprint Recording Location" : nameField.text
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    // MARK: - 保存

    @objc private func cancelTapped() {
        guard isDirty else {
            dismiss(animated: true)
            return
        }
        presentConfirm(
            title: "Discard Changes?",
            message: "Your unsaved changes will be lost.",
            destructiveTitle: "Discard"
        ) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @objc private func saveTapped() {
        guard !isSaving else { return }
        let name = nameField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            nameField.showError("Enter a name for this place.")
            scrollView.setContentOffset(.zero, animated: true)
            SPHaptic.error()
            return
        }
        nameField.showError(nil)
        isSaving = true
        saveButton.isEnabled = false

        let finalCoordinate = precision == .none ? nil : coordinate
        let draft = PlaceDraft(
            name: name,
            kind: selectedKind,
            note: noteView.text,
            tags: tags,
            coordinate: finalCoordinate,
            precision: finalCoordinate == nil ? .none : precision
        )

        do {
            let place: PlaceEntity
            let created: Bool
            if let editingPlace {
                place = try library.updatePlace(editingPlace, with: draft)
                created = false
            } else {
                place = try library.createPlace(draft)
                created = true
            }
            SPHaptic.success()
            dismiss(animated: true) { [onSaved] in
                onSaved(place, created)
            }
        } catch {
            isSaving = false
            saveButton.isEnabled = true
            presentError(error, title: "Couldn't Save")
        }
    }

    private func markDirty() {
        isDirty = true
    }
}

// MARK: - 地图

extension PlaceEditorViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        let identifier = "place-pin"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.markerTintColor = SPColor.accent
        view.glyphImage = UIImage(systemName: "waveform")
        view.displayPriority = .required
        return view
    }
}
