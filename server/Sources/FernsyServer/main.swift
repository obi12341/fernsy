import Foundation

// Fernsy Server: see server/README.md.
#if DEBUG
if CommandLine.arguments.count > 1, CommandLine.arguments[1].hasPrefix("app-") {
    do { try await DevApp.run(Array(CommandLine.arguments.dropFirst())) } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
    exit(0)
}
#endif
let config = Config.fromEnvironment()
Log.info("Fernsy Server \(config.version), data in \(config.data.path), status page on port \(config.port)")
let server = Server(config: config)
do {
    try StatusPage(board: server.board, port: config.port).start()
} catch {
    Log.error("The status page cannot listen on port \(config.port): \(error)")
}
await server.run()
