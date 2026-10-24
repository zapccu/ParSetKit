//
//  ParSetKit.swift
//
//  Manage static parameter set to store multiple versions
//  of application data and parameters.
//
//  Created by Dirk Braner on 01.03.26.
//
//  Usage:
//
//    1. Define a structure or class which contains your application parameters.
//       The structure must be conform to protocol Codable.
//
//       struct MyAppData: Codable {
//          var name: String
//          var age: Int
//       }
//
//    2. Initialize a dictionary of type [String: Any] with default / initial values
//       for your MyAppData struct:
//
//       let myAppDataInitValues[String: Any] = [
//          "name": "NoName",
//          "age":  0
//
//    3. Initialize your parameterset. Pass MyAppData as a type and the dictionary
//       myAppDataInitValues.
//
//       let myParSet = ParSet<MyAppData>(myAppDataInitValues)
//
//    4. Access the parameters:
//
//       let n = myParSet.name
//
//       myParSet.name = "John"
//

import Foundation

extension Encodable {
    
    /// Convert a Codable-Type to a JSON compatible Dictionary
    public func asDictAny(_ defval: [String: Any] = [:]) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(self) else { return defval }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: .allowFragments),
              let dict = jsonObject as? [String: Any] else {
            return defval
        }
        
        return dict
    }
    
}

@dynamicMemberLookup
public struct ParSet<T: Codable & Sendable & Equatable> : Codable & Sendable {
    
    /// Return name of data type stored in ParSet
    public var dataType: String { String(describing: T.self) }
    
    // Array of data versions. Cannot be accessed directly
    private var versions: [T] = []
    
    // Automatically create a new version on first set operation
    private let autoVersioning: Bool
    
    // First set operation. Triggers creation of a new version if autoVersioning is true
    private var isFirstSetOperation = true

    /// The initial value. Can be accessed directly
    public let initial: T
    
    /// Return current version or initial version if there's no current version
    public var current: T {
        versions.last ?? initial
    }
    
    /// Return previous version or initial version if only one version exists
    public var previous: T {
        versions.count > 1 ? versions[versions.count - 2] : initial
    }
    
    /// Return number of versions
    public var versionsCount: Int { versions.count }
    
    /// Return true if current version has been modified
    public var hasChanges: Bool {
        current != previous
    }
    
    /// Search for invalid JSON elements, prevent runtime errors
    private static func findInvalidJSONElement(_ object: Any, path: String = "root") -> Bool {
        if JSONSerialization.isValidJSONObject([object]) {
            return true
        }

        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if !findInvalidJSONElement(value, path: "\(path).\(key)") {
                    return false
                }
            }
        } else if let array = object as? [Any] {
            for (index, value) in array.enumerated() {
                if !findInvalidJSONElement(value, path: "\(path)[\(index)]") {
                    return false
                }
            }
        } else {
            print("❌ Invalid type found at: \(path)")
            print("   Type: \(type(of: object))")
            print("   Value: \(object)")
            return false
        }
        
        return true
    }
    
    /// Initialize ParSet from data structure
    public init(initial: T, autoVersioning: Bool = false) {
        self.initial = initial
        self.autoVersioning = autoVersioning
        self.versions.append(initial)
    }
 
    /// Initialize static ParSet from JSON data
    public init(jsonData: Data, autoVersioning: Bool = false) throws {
        // Configure decoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // For dates
        
        let decodedInitial = try decoder.decode(T.self, from: jsonData)
        
        // Setup initial version
        self.initial = decodedInitial
        
        self.autoVersioning = autoVersioning
        
        // Current version is identical to initial version
        self.versions.append(decodedInitial)
    }
    
    /// Initialize static ParSet from Dictionary [String: Any]
    public init(dictionary: [String: Any], autoVersioning: Bool = false) throws {
        _ = ParSet.findInvalidJSONElement(dictionary)
        
        // Convert dictionary to JSON data
        let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        
        // Init with JSON data by calling JSON data initializer
        try self.init(jsonData: jsonData, autoVersioning: autoVersioning)
    }
    
    /// Initialize static ParSet from JSON String
    public init(jsonString: String, autoVersioning: Bool = false) throws {
        // Try to convert String to UTF-8
        guard let jsonData = jsonString.data(using: .utf8) else {
            // Conversion failed
            let context = DecodingError.Context(
                codingPath: [],
                debugDescription: "Cannot convert String to UTF8."
            )
            throw DecodingError.dataCorrupted(context)
        }
        try self.init(jsonData: jsonData, autoVersioning: autoVersioning)
    }
    
    /// Direct access to members of current version
    public subscript<V>(dynamicMember keyPath: WritableKeyPath<T, V>) -> V {
        get { return current[keyPath: keyPath] }
        set {
            guard !versions.isEmpty else { return }
            if autoVersioning && isFirstSetOperation {
                newVersion()
            }
            else {
                isFirstSetOperation = false
            }
            versions[versions.count - 1][keyPath: keyPath] = newValue
        }
    }
    
    /// Create a new data version by cloning the current version
    /// If there's no current version, create a copy of initial version
    public mutating func newVersion(data: T? = nil) {
        if let data = data {
            versions.append(data)
        }
        else {
            versions.append(self.versions.last ?? initial)
        }
        
        // Next set operation won't create a new version
        isFirstSetOperation = false
    }
    
    /// Go back to previous version / initial version
    public mutating func undo() {
        if versions.isEmpty {
            versions.append(initial)
        }
        else {
            versions.removeLast()
        }
    }
    
    /// Apply changes to current version. Next set operation will create a new
    /// version if autoVersioning is true
    public mutating func commit() {
        isFirstSetOperation = true
    }
    
    /// Apply all changes / versions. Keep only current version
    public mutating func consolidate() {
        let currentVersion = current
        versions.removeAll()
        versions.append(currentVersion)
        isFirstSetOperation = true
    }
    
    /// Delete all versions and reset to initial version
    public mutating func reset() {
        versions.removeAll()
        versions.append(initial)
        isFirstSetOperation = true
    }
    
    /// Convert parameterset to json String.
    /// Return empty String on error
    /// - Parameter prettyPrinted: true will create a well formatted JSON string
    /// - Returns: JSON string or empty string on error
    public func toJSON(prettyPrinted: Bool = true) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = prettyPrinted ? [.prettyPrinted] : []
            let s = try encoder.encode(current)
            return String(data: s, encoding: .utf8) ?? ""
        }
        catch {
            return ""
        }
    }
}
