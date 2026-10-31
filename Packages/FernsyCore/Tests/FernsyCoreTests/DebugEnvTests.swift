#if DEBUG
import Foundation
import Testing
@testable import FernsyCore

/// Debug switches shared by the Mac and the Apple TV (code-structure-cleanup 3.2).
struct DebugEnvTests {
    @Test func hideStepsReadBothSyntaxes() {
        #expect(DebugEnv.parseHideSteps("channel:102,category:3,wait:20,show:channel:102,bogus,x:1") == [
            .channel(102, hidden: true), .category("3", hidden: true), .wait(20), .channel(102, hidden: false),
        ])
        #expect(DebugEnv.parseHideSteps("") == [])
    }

    @Test func enlargedRepeatsWithNewIds() throws {
        let data = try JSONSerialization.data(withJSONObject: [["stream_id": 5, "name": "A", "added": "1000"]])
        let live = try JSONSerialization.jsonObject(with: DebugEnv.enlarged(data, to: 3, id: "stream_id")) as! [[String: Any]]
        #expect(live.map { $0["stream_id"] as? Int } == [5, 1_000_005, 2_000_005])
        #expect(live.map { $0["name"] as? String } == ["A", "A", "A"])
        let films = try JSONSerialization.jsonObject(with: DebugEnv.enlarged(data, to: 2, id: "stream_id", date: "added")) as! [[String: Any]]
        #expect(films[1]["name"] as? String == "A 1")
        #expect(films[1]["added"] as? String == "940")
    }
}
#endif
