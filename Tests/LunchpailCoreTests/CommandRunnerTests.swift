import Foundation
import Testing

@testable import LunchpailCore

@Test func commandRunnerCapturesLargeStderrWithoutPipeDeadlock() throws {
  let result = try CommandRunner().run(
    executable: URL(fileURLWithPath: "/usr/bin/awk"),
    arguments: [
      "BEGIN { for (i = 0; i < 20000; i++) print \"a deliberately long diagnostic line\" > \"/dev/stderr\"; print \"done\" }"
    ]
  )
  #expect(result.status == 0)
  #expect(result.stdout == "done\n")
  #expect(result.stderr.count > 500_000)
}
