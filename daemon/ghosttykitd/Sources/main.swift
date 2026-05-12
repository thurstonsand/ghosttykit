import Foundation

let version = "0.0.0-dev"

if CommandLine.arguments.dropFirst().contains("--version") {
    print("ghosttykitd \(version)")
    exit(0)
}

FileHandle.standardError.write(Data("ghosttykitd: daemon implementation has not been extracted yet\n".utf8))
exit(2)
