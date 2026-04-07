import Foundation

public enum UsagePayloadParser {
  public static func decodeSnapshot(
    from output: Data,
    decoder: JSONDecoder = JSONDecoder()
  ) throws -> UsageSnapshot {
    let payloadData = try extractPayloadData(from: output)

    let payload: UsagePayload
    do {
      payload = try decoder.decode(UsagePayload.self, from: payloadData)
    } catch {
      throw UsageFetcherError.invalidResponse("invalid JSON")
    }

    return UsageSnapshot(today: payload.today, month: payload.month)
  }

  public static func extractPayloadData(from output: Data) throws -> Data {
    guard let string = String(data: output, encoding: .utf8) else {
      throw UsageFetcherError.invalidResponse("invalid UTF-8 output")
    }

    let candidate =
      string
      .split(whereSeparator: \.isNewline)
      .reversed()
      .first { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.first == "{"
      }

    guard let candidate else {
      throw UsageFetcherError.invalidResponse("missing JSON payload")
    }

    return Data(candidate.utf8)
  }
}
