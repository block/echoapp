import Foundation
import EchoPluginAPI

extension URLRequest {
    static func makeProxyRequest(
        from originalRequest: Request,
        replacementBaseURL: URL? = nil
    ) -> URLRequest? {
        var urlRequest = URLRequest(url: originalRequest.url)
        urlRequest.httpMethod = originalRequest.httpMethod
        urlRequest.httpBody = originalRequest.rawBody
        urlRequest.allHTTPHeaderFields = originalRequest.headers

        if let replacementBaseURL {
            guard
                let originalComponents = URLComponents(url: originalRequest.url, resolvingAgainstBaseURL: false),
                var newComponents = URLComponents(url: replacementBaseURL, resolvingAgainstBaseURL: false),
                newComponents.path.isEmpty || newComponents.path == "/"
            else {
                return nil
            }

            if !originalRequest.endpoint.isEmpty {
                newComponents.path = originalRequest.endpoint.path
            }
            newComponents.query = originalComponents.query

            guard let url = newComponents.url else {
                return nil
            }
            urlRequest.url = url
        }
        return urlRequest
    }
}

// MARK: -

private extension Endpoint {

    var isEmpty: Bool {
        path == "" || path == "/"
    }
}
