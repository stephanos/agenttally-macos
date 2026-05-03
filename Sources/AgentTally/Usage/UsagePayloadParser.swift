import Foundation

private struct AgentPayload: Codable {
  let name: String
  let found: Bool
  let today: Double
  let month: Double
}

private struct HelperPayload: Codable {
  let agents: [AgentPayload]
}

public enum UsagePayloadParser {
  public static func decodeSnapshot(
    from output: Data,
    decoder: JSONDecoder = JSONDecoder()
  ) throws -> UsageSnapshot {
    let payloadData = try extractPayloadData(from: output)

    let payload: HelperPayload
    do {
      payload = try decoder.decode(HelperPayload.self, from: payloadData)
    } catch {
      throw UsageFetcherError.invalidResponse("invalid JSON")
    }

    let agents = payload.agents.map { agent in
      AgentRawData(name: agent.name, found: agent.found, today: agent.today, month: agent.month)
    }
    return UsageSnapshot(agents: agents)
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
