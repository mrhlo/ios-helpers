//
//  FirestoreService.swift
//

import Combine
import Foundation
import FirebaseFirestore

public protocol FirestoreServicing {
    func fetchSingleObject<T: FirestoreModel>(of model: T.Type, id: String) async throws -> T
    func fetchSingleObject<T>(of model: T.Type, secondaryID: String) async throws -> T where T : FirestoreModel
    func fetchObjects<T: FirestoreModel>(of model: T.Type, secondaryID: String?) async throws -> [T]
    func fetchObjects<T: FirestoreModel>(of model: T.Type, filter: [String: Any]) async throws -> [T]
    func saveSingleObject<T: FirestoreModel>(_ object: T, id: String) async throws
    func saveSingleObject<T: FirestoreModel>(_ object: T, id: String, individualFields: [String]?) async throws
    func saveSingleObject<T: FirestoreModel>(_ object: T, secondaryID: String?) async throws -> String
    func saveSingleObject<T: FirestoreModel>(_ object: T, secondaryID: String?, overrideExisting: Bool) async throws -> String
    func addObjects<T: FirestoreModel>(_ objects: [T], secondaryID: String?) async throws
    func deleteSingleObject<T: FirestoreModel>(_ object: T, id: String) async throws
    
    func listenToUpdates<T: FirestoreModel>(of model: T.Type) -> PassthroughSubject<[T], Never>
}

public func makeDefaultFirestoreService() -> FirestoreServicing {
    FirestoreService()
}

class FirestoreService: FirestoreServicing {
    private let firestore: Firestore
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        
        return dateFormatter
    }()
    
    private var listeners: [ListenerRegistration] = []
    private var publishers: [Any] = []
    
    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }
    
    
    func fetchSingleObject<T>(of model: T.Type, id: String) async throws -> T where T : FirestoreModel {
        let document = try await firestore.collection(T.collectionPath).document(id).getDocument()
        return try decode(T.self, from: document)
    }
    
    func fetchSingleObject<T>(of model: T.Type, secondaryID: String) async throws -> T where T : FirestoreModel {
        guard let object = try await fetchObjects(of: T.self, secondaryID: secondaryID).first else {
            throw FirestoreError.objectNotFound
        }
        
        return object
    }
    
    func fetchObjects<T>(of model: T.Type, secondaryID: String?) async throws -> [T] where T : FirestoreModel {
        var collectionReference: Query = firestore.collection(T.collectionPath)
        if let secondaryID {
            collectionReference = collectionReference.whereField(T.secondaryIDKey, isEqualTo: secondaryID)
        }
        
        return try await collectionReference.getDocuments().documents.compactMap {
            try? decode(T.self, from: $0)
        }
    }
    
    func fetchObjects<T>(of model: T.Type, filter: [String: Any]) async throws -> [T] where T : FirestoreModel {
        var collectionReference: Query = firestore.collection(T.collectionPath)
        
        
        for (key, value) in filter {
            collectionReference = collectionReference.whereField(key, isEqualTo: value)
        }
        
        return try await collectionReference.getDocuments().documents.map {
            try decode(T.self, from: $0)
        }
    }
    
    func saveSingleObject<T>(_ object: T, id: String) async throws where T : FirestoreModel {
        try await saveSingleObject(object, id: id, individualFields: nil)
    }
    
    func saveSingleObject<T: FirestoreModel>(_ object: T, id: String, individualFields: [String]?) async throws {
        // Encode the object to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(dateFormatter)

        let jsonData = try encoder.encode(object)
        
        guard var jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as? [String: Any] else {
            throw EncodingError.invalidValue(object, EncodingError.Context(codingPath: [], debugDescription: "Unable to convert object to JSON."))
        }

        let documentReference = firestore.collection(T.collectionPath).document(id)
        
        if let individualFields {
            jsonObject = jsonObject.filter {
                individualFields.contains($0.key)
            }
        }

        try await documentReference.setData(jsonObject, merge: true)
    }
    
    func saveSingleObject<T>(_ object: T, secondaryID: String?) async throws -> String where T : FirestoreModel, T: Encodable {
        try await saveSingleObject(object, secondaryID: secondaryID, overrideExisting: true)
    }
    
    func saveSingleObject<T>(_ object: T, secondaryID: String?, overrideExisting: Bool) async throws -> String where T : FirestoreModel, T: Encodable {
        // Check if secondaryID is provided
        guard let secondaryID = secondaryID else {
            throw EncodingError.invalidValue(object, EncodingError.Context(codingPath: [], debugDescription: "secondaryID is required."))
        }

        // Encode the object to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(dateFormatter)

        let jsonData = try encoder.encode(object)
        guard var jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as? [String: Any] else {
            throw EncodingError.invalidValue(object, EncodingError.Context(codingPath: [], debugDescription: "Unable to convert object to JSON."))
        }

        // Add the secondaryID to the jsonObject
        jsonObject[T.secondaryIDKey] = secondaryID

        let collectionReference = firestore.collection(T.collectionPath)

        // Fetch document(s) with the secondaryID
        do {
            let querySnapshot = try await collectionReference.whereField(T.secondaryIDKey, isEqualTo: secondaryID).getDocuments()

            // Check if a document exists that matches the secondaryID
            if let documentSnapshot = querySnapshot.documents.first,
               overrideExisting {
                // If a document is found, update it
                try await documentSnapshot.reference.updateData(jsonObject)
                return documentSnapshot.documentID
            } else {
                // If no document is found, add a new one
                let documentReference = try await collectionReference.addDocument(data: jsonObject)
                return documentReference.documentID
            }
        } catch {
            print("=== Firebase error: \(error)")
            throw error
        }
    }
    
    func addObjects<T>(_ objects: [T], secondaryID: String?) async throws where T : FirestoreModel {
        for object in objects {
            try await saveSingleObject(object, secondaryID: secondaryID, overrideExisting: false)
        }
    }
    
    func deleteSingleObject<T>(_ object: T, id: String) async throws where T : FirestoreModel, T: Encodable {
        let documentReference = firestore.collection(T.collectionPath).document(id)
        try await documentReference.delete()
    }
    
    
    func listenToUpdates<T>(of model: T.Type) -> PassthroughSubject<[T], Never> where T : FirestoreModel {
        let collectionReference = firestore.collection(T.collectionPath)
        let collectionPublisher = PassthroughSubject<[T], Never>()
        
        let listener = collectionReference.addSnapshotListener { (snapshot, error) in
            if let _ = error {
                return
            } else if let snapshot = snapshot {
                let data = snapshot.documents.compactMap {
                    return try? self.decode(T.self, from: $0)
                }
                collectionPublisher.send(data)
            }
        }
        
        listeners.append(listener)
        publishers.append(collectionPublisher)
        
        return collectionPublisher
    }
    
    private func decode<T: Decodable>(_ type: T.Type, from document: DocumentSnapshot, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        guard var data = document.data() else {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [], debugDescription: "Document has no data."))
        }
        
        data["id"] = document.documentID
        
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
        
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        return try decoder.decode(T.self, from: jsonData)
    }
}

