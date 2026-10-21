import Testing

@testable import FeatureErrors

@Suite struct ExceptionParserTests {
  private let chainedFixture = """
    {
      "$exception_issue_id": "issue-1",
      "$exception_list": [
        {
          "type": "DecodingError",
          "value": "keyNotFound(id)",
          "stacktrace": {
            "type": "resolved",
            "frames": [
              {
                "raw_id": "frame-1",
                "mangled_name": "$s5MyApp13SettingsModelC4loadyyF",
                "resolved_name": "SettingsModel.load()",
                "source": "SettingsModel.swift",
                "line": 42,
                "in_app": true
              },
              {"raw_id": "frame-2", "mangled_name": "swift_getError", "in_app": false}
            ]
          }
        },
        {
          "type": "NetworkError",
          "value": "timeout",
          "stacktrace": {"frames": [{"resolved_name": "APIClient.send", "in_app": true, "line": "nope"}]}
        }
      ]
    }
    """

  @Test func parsesChainedExceptionsWithFrames() {
    let exceptions = ExceptionParser.parse(propertiesJSON: chainedFixture)
    #expect(exceptions.count == 2)
    #expect(exceptions[0].type == "DecodingError")
    #expect(exceptions[0].value == "keyNotFound(id)")
    #expect(exceptions[0].frames.count == 2)
    #expect(exceptions[0].frames[0].inApp)
    #expect(exceptions[0].frames[0].displayName == "SettingsModel.load()")
    #expect(exceptions[0].frames[0].location == "SettingsModel.swift:42")
    #expect(!exceptions[0].frames[1].inApp)
    #expect(exceptions[0].frames[1].displayName == "swift_getError")
    #expect(exceptions[0].frames[1].location == nil)
    #expect(exceptions[1].type == "NetworkError")
    #expect(exceptions[1].frames.count == 1)
    #expect(exceptions[1].frames[0].line == nil)
  }

  @Test(arguments: [
    "not json at all",
    "12",
    #"{"$exception_list": "nope"}"#,
    #"{"other": true}"#,
    #"{"$exception_list": ["junk", 4]}"#,
  ])
  func junkInputParsesEmpty(_ input: String) {
    #expect(ExceptionParser.parse(propertiesJSON: input).isEmpty)
  }

  @Test func doubleEncodedExceptionListStillParses() {
    let json = #"{"$exception_list": "[{\"type\": \"Err\", \"stacktrace\": {\"frames\": []}}]"}"#
    let exceptions = ExceptionParser.parse(propertiesJSON: json)
    #expect(exceptions.count == 1)
    #expect(exceptions[0].type == "Err")
    #expect(exceptions[0].frames.isEmpty)
  }
}
