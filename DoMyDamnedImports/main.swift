//
//  main.swift
//  DoMyDamnedImports
//
//  Created by Pivotal - DX236 on 2016-12-21.
//  Copyright © 2016 Really. All rights reserved.
//

import Foundation

print("Hello, You minion!")
print("Finding files...")

typealias FileSuffix = String
typealias FilePath = URL

typealias ClassString = String
typealias ImportStatement = String

enum FileType: FileSuffix {
    case spec = "mm"
    case implementation = "m"
    case header = "h"
    case other
    
    init(fromRawValue:FileSuffix) {
        self = FileType(rawValue: fromRawValue) ?? .other
    }
    
    func simpleDescription() -> String {
        switch self {
        case .spec:
            return "spec file"
        case .implementation:
            return "implementation file"
        case .header:
            return "header file"
        default:
            return "unknown"
        }
    }
}

extension FileManager {
    func listFiles(path: String) -> [URL] {
        let baseurl: URL = URL(fileURLWithPath: path, isDirectory: true)
        var urls = [URL]()
        enumerator(atPath: path)?.forEach({ (e) in
            guard let s = e as? String else { return }
            let relativeURL = URL(fileURLWithPath: s, relativeTo: baseurl)
            let url = relativeURL.absoluteURL
            urls.append(url)
        })
        return urls
    }
}

class DemonFileFinder {
    func findFilesRecursively(in rootDirectoryPath: String) -> (specFiles:[FilePath],impFiles:[FilePath],headerFiles:[FilePath],otherFiles:[FilePath]) {
        let fileManager = FileManager.default
        let listOfFiles = fileManager.listFiles(path: rootDirectoryPath)
        var specFiles = [FilePath]()
        var impFiles = [FilePath]()
        var headerFiles = [FilePath]()
        var otherFiles = [FilePath]()
        
        for fileURL in listOfFiles {
            let fileSuffix : FileSuffix = NSString(string:fileURL.absoluteString).pathExtension
            let fileType = FileType(fromRawValue: fileSuffix)
            switch fileType {
            case .spec:
                specFiles.append(fileURL)
            case .implementation:
                impFiles.append(fileURL)
            case .header:
                headerFiles.append(fileURL)
            case .other:
                otherFiles.append(fileURL)
            }
        }
        return (specFiles,impFiles,headerFiles,otherFiles)
    }
}


class AngelUmbrellaHeaderParser {

    func matches(for regex: String, in text: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let nsString = text as NSString
            let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length))
            return nsString.substring(with:result!.range)
        } catch let error {
            print("invalid regex: \(error.localizedDescription)")
            return ""
        }
    }
    
    func findAvailableClassFiles(in umbrellaFilePath: String) -> Dictionary<ClassString, ImportStatement> {
        do {
            let s = try String(contentsOfFile: umbrellaFilePath)
            var dictionary = [ClassString:ImportStatement]()
            print(s)
            let array = s.components(separatedBy: "\n")
            func isImportStatement(statement: String) -> Bool {
                return statement.hasPrefix("#import ")
            }
            let imports = array.filter(isImportStatement)
            print(imports)
            for statement in imports {
                let classString = matches(for:"(?<=\\/)()\\w*", in: statement)
                dictionary[classString] = statement
            }
//            let plausibleClasses = imports.map({ (statement) -> String in
//                return matches(for:"(?<=\\/)()\\w*", in: statement)
//            })
            return dictionary
        } catch {
            print(error)
        }
        return Dictionary()
    }
}

class DemonFileParser {
    
    func lastMatch(for regex: String, in text: String) -> NSTextCheckingResult? {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let nsString = text as NSString
            let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            return results.last
        } catch let error {
            print("invalid regex: \(error.localizedDescription)")
            return nil
        }
    }
    
    func hasMatch(for regex: String, in text: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let nsString = text as NSString
            if let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)) {
                return result.range.location != NSNotFound
            } else {
                return false;
            }
        } catch let error {
            print("invalid regex: \(error.localizedDescription)")
            return false
        }
    }

    
    func exorciseAndBlessImports(in fileURL:URL, ofType type:FileType, using classDictionary:Dictionary<ClassString, ImportStatement>, withUmbrellaFile umbrellaFileName:String, replacing oldFramework:String) {
        do {
            let originalContents = try String(contentsOf: fileURL)
            var newContents = NSMutableString(string:originalContents)
            var hasChanged = false
            for (klass, statement) in classDictionary {
                if newContents.contains("#import <\(oldFramework)/\(klass).h>") {
                    newContents.replaceOccurrences(of: "#import <\(oldFramework)/\(klass).h>", with: "#import <\(umbrellaFileName)/\(klass).h>", options: NSString.CompareOptions(rawValue: 0) , range: NSMakeRange(0, newContents.length))
                    hasChanged = true;
                }
                if hasMatch(for:"(?<![A-Za-z<\\/*])\(klass)", in:newContents as String) && !newContents.contains("#import <\(umbrellaFileName)/\(umbrellaFileName).h>") && !newContents.contains("#import <\(umbrellaFileName)/\(klass).h>") && !newContents.contains("@import \(umbrellaFileName)") && !newContents.contains("@class \(klass)") {
                    if let resultingMatch = self.lastMatch(for:"[#@]import .*\\s(?!(?s).*[@#]import .*)", in: newContents as String) {
                        if resultingMatch.range.location != NSNotFound {
                            let insertPoint = resultingMatch.range.location + resultingMatch.range.length
                            switch type {
                            case .header:
                                newContents.insert("#import <\(umbrellaFileName)/\(klass).h>\n", at: insertPoint)
                                hasChanged = true;
                                print(newContents)
                            case .implementation:
                                newContents.insert("@import \(umbrellaFileName);\n", at: insertPoint)
                                hasChanged = true;
                                print(newContents)
                            case .spec:
                                newContents.insert("#import <\(umbrellaFileName)/\(umbrellaFileName).h>\n", at: insertPoint)
                                hasChanged = true;
                                print(newContents)
                            default:
                                print("-")
                                //do nothing
                            }
                            print(newContents)
                        }
                        
                    }
                }
            }
            if hasChanged {
                try newContents.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8.rawValue)
            }
        } catch  {
            print(error)
        }
    }
}

let find = DemonFileFinder.init().findFilesRecursively(in:NSString(string:"~/workspace/ford-oa-ios/fordownerAPTests").expandingTildeInPath)
print(find)
let classes = AngelUmbrellaHeaderParser.init().findAvailableClassFiles(in:NSString(string:"~/workspace/ford-oa-ios/Externals/Powertrain/PWRPark/PWRPark/PWRPark.h").expandingTildeInPath)
print(classes)
for file in find.headerFiles {
    DemonFileParser.init().exorciseAndBlessImports(in:file, ofType: .header, using: classes,withUmbrellaFile:"PWRPark",replacing: "Powertrain")
}

for file in find.specFiles {
    DemonFileParser.init().exorciseAndBlessImports(in:file, ofType: .header, using: classes,withUmbrellaFile:"PWRPark",replacing: "Powertrain")
}

for file in find.impFiles {
    DemonFileParser.init().exorciseAndBlessImports(in:file, ofType: .header, using: classes,withUmbrellaFile:"PWRPark",replacing: "Powertrain")
}
