//
//  File.swift
//  
//
//  Created by Halil Gursoy on 20.11.23.
//

import Foundation

public protocol FirestoreModel: Codable {
    public static var collectionPath: String { get }
    public static var secondaryIDKey: String { get }
}
