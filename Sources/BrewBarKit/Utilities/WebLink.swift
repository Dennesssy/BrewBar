// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Package metadata comes from a remote catalog, so links are only allowed to
/// open web pages — never `file://` or arbitrary app schemes.
public enum WebLink {
    public static func url(_ string: String?) -> URL? {
        guard let string,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}
