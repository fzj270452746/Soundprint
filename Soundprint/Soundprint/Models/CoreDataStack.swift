//
//  CoreDataStack.swift
//  Soundprint
//
//  以代码构建 Core Data 模型，避免模型文件与代码漂移。音频文件独立存储。
//

import CoreData
import Foundation

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    private init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "Soundprint", managedObjectModel: model)

        let storeURL = StorageManager.shared.databaseDirectory.appendingPathComponent("Soundprint.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            assertionFailure("无法载入本地数据库：\(loadError)")
        }

        let context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        context.shouldDeleteInaccessibleFaults = true
    }

    func saveViewContext() throws {
        let context = container.viewContext
        guard context.hasChanges else { return }
        try context.save()
    }

    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            block(context)
        }
    }

    // MARK: - 模型

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let place = entity(named: "Place", objectType: PlaceEntity.self, attributes: [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("placeTypeRaw", .stringAttributeType),
            attr("note", .stringAttributeType, optional: true),
            attr("latitude", .doubleAttributeType),
            attr("longitude", .doubleAttributeType),
            attr("hasCoordinates", .booleanAttributeType),
            attr("locationPrecisionRaw", .stringAttributeType),
            attr("tagsData", .binaryDataAttributeType, optional: true),
            attr("createdAt", .dateAttributeType),
            attr("updatedAt", .dateAttributeType),
            attr("archivedAt", .dateAttributeType, optional: true)
        ])

        let recording = entity(named: "Recording", objectType: RecordingEntity.self, attributes: [
            attr("id", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("duration", .doubleAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("updatedAt", .dateAttributeType),
            attr("relativeAudioPath", .stringAttributeType),
            attr("fileSize", .integer64AttributeType),
            attr("audioFormat", .stringAttributeType),
            attr("sampleRate", .doubleAttributeType),
            attr("channelCount", .integer16AttributeType),
            attr("deviceModel", .stringAttributeType, optional: true),
            attr("note", .stringAttributeType, optional: true),
            attr("weather", .stringAttributeType, optional: true),
            attr("latitude", .doubleAttributeType),
            attr("longitude", .doubleAttributeType),
            attr("hasCoordinates", .booleanAttributeType),
            attr("waveformRelativePath", .stringAttributeType, optional: true),
            attr("analysisStatusRaw", .stringAttributeType),
            attr("tagsData", .binaryDataAttributeType, optional: true)
        ])

        let event = entity(named: "SoundEvent", objectType: SoundEventEntity.self, attributes: [
            attr("id", .UUIDAttributeType),
            attr("startTime", .doubleAttributeType),
            attr("endTime", .doubleAttributeType),
            attr("hasEndTime", .booleanAttributeType),
            attr("categoryRaw", .stringAttributeType),
            attr("title", .stringAttributeType),
            attr("note", .stringAttributeType, optional: true),
            attr("sourceRaw", .stringAttributeType),
            attr("confidence", .doubleAttributeType),
            attr("hasConfidence", .booleanAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("updatedAt", .dateAttributeType)
        ])

        let analysis = entity(named: "AudioAnalysis", objectType: AudioAnalysisEntity.self, attributes: [
            attr("id", .UUIDAttributeType),
            attr("algorithmVersion", .stringAttributeType),
            attr("windowSize", .integer32AttributeType),
            attr("hopSize", .integer32AttributeType),
            attr("peakValue", .doubleAttributeType),
            attr("rmsMean", .doubleAttributeType),
            attr("rmsDBFS", .doubleAttributeType),
            attr("bandLow", .doubleAttributeType),
            attr("bandMid", .doubleAttributeType),
            attr("bandHigh", .doubleAttributeType),
            attr("analysisRelativePath", .stringAttributeType),
            attr("spectrogramRelativePath", .stringAttributeType, optional: true),
            attr("createdAt", .dateAttributeType)
        ])

        // 关系
        let placeRecordings = relationship(
            name: "recordings",
            destination: recording,
            toMany: true,
            deleteRule: .cascadeDeleteRule
        )
        let recordingPlace = relationship(
            name: "place",
            destination: place,
            toMany: false,
            deleteRule: .nullifyDeleteRule
        )
        placeRecordings.inverseRelationship = recordingPlace
        recordingPlace.inverseRelationship = placeRecordings

        let recordingEvents = relationship(
            name: "events",
            destination: event,
            toMany: true,
            deleteRule: .cascadeDeleteRule
        )
        let eventRecording = relationship(
            name: "recording",
            destination: recording,
            toMany: false,
            deleteRule: .nullifyDeleteRule
        )
        recordingEvents.inverseRelationship = eventRecording
        eventRecording.inverseRelationship = recordingEvents

        let recordingAnalysis = relationship(
            name: "analysis",
            destination: analysis,
            toMany: false,
            deleteRule: .cascadeDeleteRule
        )
        let analysisRecording = relationship(
            name: "recording",
            destination: recording,
            toMany: false,
            deleteRule: .nullifyDeleteRule
        )
        recordingAnalysis.inverseRelationship = analysisRecording
        analysisRecording.inverseRelationship = recordingAnalysis

        place.properties = attributes(of: place) + [placeRecordings]
        recording.properties = attributes(of: recording) + [recordingPlace, recordingEvents, recordingAnalysis]
        event.properties = attributes(of: event) + [eventRecording]
        analysis.properties = attributes(of: analysis) + [analysisRecording]

        model.entities = [place, recording, event, analysis]
        return model
    }

    private static func entity<T: NSManagedObject>(
        named name: String,
        objectType: T.Type,
        attributes: [NSAttributeDescription]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(objectType)
        entity.properties = attributes
        return entity
    }

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }

    private static func relationship(
        name: String,
        destination: NSEntityDescription,
        toMany: Bool,
        deleteRule: NSDeleteRule
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.isOptional = true
        relationship.isOrdered = false
        relationship.minCount = 0
        relationship.maxCount = toMany ? 0 : 1
        relationship.deleteRule = deleteRule
        return relationship
    }

    private static func attributes(of entity: NSEntityDescription) -> [NSPropertyDescription] {
        entity.properties.filter { $0 is NSAttributeDescription }
    }
}
