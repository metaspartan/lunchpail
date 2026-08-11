import Hummingbird
import LunchpailCore

struct BearerTokenMiddleware<Context: RequestContext>: RouterMiddleware {
  let token: String

  func handle(
    _ request: Request,
    context: Context,
    next: (Request, Context) async throws -> Response
  ) async throws -> Response {
    let supplied = request.headers[.authorization] ?? ""
    guard Self.secureEquals(supplied, "Bearer \(token)") else {
      throw HTTPError(
        .unauthorized,
        headers: [.wwwAuthenticate: "Bearer"],
        message: "missing or invalid bearer token"
      )
    }
    return try await next(request, context)
  }

  private static func secureEquals(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var difference = left.count ^ right.count
    for index in 0..<max(left.count, right.count) {
      difference |=
        Int(
          (index < left.count ? left[index] : 0)
            ^ (index < right.count ? right[index] : 0)
        )
    }
    return difference == 0
  }
}

struct APIErrorMiddleware<Context: RequestContext>: RouterMiddleware {
  func handle(
    _ request: Request,
    context: Context,
    next: (Request, Context) async throws -> Response
  ) async throws -> Response {
    do {
      return try await next(request, context)
    } catch let error as HTTPError {
      throw error
    } catch let error as VMRegistryError {
      switch error {
      case .notFound:
        throw HTTPError(.notFound, message: error.localizedDescription)
      case .ambiguousSelector:
        throw HTTPError(.conflict, message: error.localizedDescription)
      default:
        throw HTTPError(.internalServerError, message: error.localizedDescription)
      }
    } catch let error as VMRuntimeError {
      switch error {
      case .alreadyRunning, .notRunning, .stopRejected:
        throw HTTPError(.conflict, message: error.localizedDescription)
      case .invalidVM, .metalBridgeDisabled:
        throw HTTPError(.unprocessableContent, message: error.localizedDescription)
      }
    } catch let error as VMDirectoryLockError {
      throw HTTPError(.conflict, message: error.localizedDescription)
    } catch {
      throw HTTPError(.badRequest, message: error.localizedDescription)
    }
  }
}
