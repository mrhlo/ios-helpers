//
//  File.swift
//  
//
//  Created by Halil Gursoy on 20.11.23.
//

import Foundation

public protocol FirestoreModel: Codable {
    static var collectionPath: String { get }
    static var secondaryIDKey: String { get }
}
