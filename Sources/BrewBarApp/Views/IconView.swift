import SwiftUI
import BrewBarKit

struct IconView: View {
    let item: FormulaItem
    let size: CGFloat
    
    init(item: FormulaItem, size: CGFloat = 48) {
        self.item = item
        self.size = size
    }
    
    var iconURL: URL? {
        guard let urlString = item.homepage, let url = URL(string: urlString), let host = url.host else {
            return nil
        }
        
        // GitHub avatar extraction
        if host.contains("github.com") {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let userOrOrg = pathComponents.first {
                return URL(string: "https://github.com/\(userOrOrg).png")
            }
        }
        
        // General Favicon using Google Favicon API
        return URL(string: "https://s2.googleusercontent.com/s2/favicons?domain=\(host)&sz=128")
    }
    
    var body: some View {
        if let iconURL {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: size, height: size)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    fallbackIcon
                @unknown default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }
    
    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: size, height: size)
            Image(systemName: item.type == .cask ? "app.fill" : "terminal.fill")
                .foregroundColor(.secondary)
                .font(.system(size: size * 0.5))
        }
    }
}
