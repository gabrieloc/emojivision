import UIKit
import PlaygroundSupport

enum Error: Swift.Error {
  case missingColorMap
  case invalidColorRGB(String)
  case invalidColorEmojiPair(String)
  case invalidInputImage(String)
}

let imageFileName = "ml.jpg"
let colorMapName = "colormap_simple.txt"
let emojiFileName = "Emoji_iOS12.1_Simulator_2503_Emojis.txt"
let resolution: CGFloat = 10

extension UIColor {
  convenience init(rgb: Int) {
    self.init(
      red:    CGFloat((rgb & 0xFF0000) >> 16) / 0xFF,
      green:  CGFloat((rgb & 0x00FF00) >> 8) / 0xFF,
      blue:   CGFloat(rgb & 0x0000FF) / 0xFF,
      alpha:  1
    )
  }
  
  var hexString: String {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)
    let rgb:Int = (Int)(r*255)<<16 | (Int)(g*255)<<8 | (Int)(b*255)<<0
    return NSString(format:"%06x", rgb) as String
  }
  
  func distance(from color: UIColor) -> CGFloat {
    var r1: CGFloat = 0
    var g1: CGFloat = 0
    var b1: CGFloat = 0
    var r2: CGFloat = 0
    var g2: CGFloat = 0
    var b2: CGFloat = 0
    getRed(&r1, green: &g1, blue: &b1, alpha: nil)
    color.getRed(&r2, green: &g2, blue: &b2, alpha: nil)
    return sqrt(pow(r2 - r1, 2) + pow(g2 - g1, 2) + pow(b2 - b1, 2))
  }
}

extension String {
  func dominantColor(size: CGSize = CGSize(width: 16, height: 16)) -> UIColor? {
    defer {
      UIGraphicsEndImageContext()
    }
    
    let rect = CGRect(
      origin: .zero,
      size: size
    )
    UIGraphicsBeginImageContextWithOptions(rect.size, false, 1)
    self.draw(in: rect, withAttributes: [:])
    guard
      let image = UIGraphicsGetImageFromCurrentImageContext(),
      let color = image.averageColor
      else {
        return nil
    }
    return color    
  }
}

extension UIImage {
  var averageColor: UIColor? {
    guard let inputImage = CIImage(image: self) else {
      return nil
    }
    
    let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
    
    guard
      let filter = CIFilter(
        name: "CIAreaAverage",
        parameters: [
          kCIInputImageKey: inputImage,
          kCIInputExtentKey: extentVector
        ]
      ),
      let outputImage = filter.outputImage else {
        return nil
    }
    
    var bitmap = [UInt8](repeating: 0, count: 4)
    let context = CIContext(options: [.workingColorSpace: kCFNull!])
    context.render(
      outputImage,
      toBitmap: &bitmap,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: nil
    )
    return UIColor(
      red: CGFloat(bitmap[0]) / 255,
      green: CGFloat(bitmap[1]) / 255,
      blue: CGFloat(bitmap[2]) / 255,
      alpha: CGFloat(bitmap[3]) / 255
    )
  }
}

func generateColorMap() throws {
  let emojisURL = Bundle.main.url(
    forResource: emojiFileName.components(separatedBy: ".")[0],
    withExtension: emojiFileName.components(separatedBy: ".")[1]
  )!
  let emojis = try String(contentsOf: emojisURL).components(
    separatedBy: ","
  )
  emojis.count
  let writeURL = playgroundSharedDataDirectory.appendingPathComponent("colormap.txt")
  var swatches = [UIColor: String]()
  let str = emojis.compactMap { e in
    guard let c = e.dominantColor(), swatches[c] == nil else {
      return nil
    }
    return "\(c.hexString):\(e)"
    }.joined(separator: "\n")
  try str.write(to: writeURL, atomically: true, encoding: .utf8)
  print("wrote emojis to \(writeURL)")
}

func createColorMap() throws -> [UIColor: String] {
  guard let colorMapURL = Bundle.main.url(
    forResource: colorMapName.components(separatedBy: ".")[0],
    withExtension: colorMapName.components(separatedBy: ".")[1]
    ) else {
      throw Error.missingColorMap
  }
  let colorMapRaw = try String(
    contentsOf: colorMapURL
    ).components(separatedBy: .newlines)
  let colorMap = try colorMapRaw.reduce(into: [UIColor: String](), { (r, str) in
    let c = str.components(separatedBy: ":")
    guard c.count == 2 else {
      throw Error.invalidColorEmojiPair(str)
    }
    guard let rgb = Int(c[0], radix: 16) else {
      throw Error.invalidColorRGB(c[0])
    }
    let color = UIColor(rgb: rgb)
    let emoji = c[1]
    r[color] = emoji
  })
  return colorMap
}

extension UIImage {
  func pixelColor(at p: CGPoint) -> UIColor? {
    guard let pixelData = cgImage?.dataProvider?.data else {
      return nil
    }
    let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
    
    let pixelInfo: Int = ((Int(self.size.width) * Int(p.y)) + Int(p.x)) * 4
    
    let r = CGFloat(data[pixelInfo]) / CGFloat(255.0)
    let g = CGFloat(data[pixelInfo+1]) / CGFloat(255.0)
    let b = CGFloat(data[pixelInfo+2]) / CGFloat(255.0)
    let a = CGFloat(data[pixelInfo+3]) / CGFloat(255.0)
    
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
  
  func luminance(at p: CGPoint) -> CGFloat {
    let col = pixelColor(at: p)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    col?.getRed(&r, green: &g, blue: &b, alpha: nil)
    let y = r * 0.2126 + g * 0.7152 + b * 0.0722
    
    return y
  }
}

extension ClosedRange {
  func clamp(_ value : Bound) -> Bound {
    return self.lowerBound > value ? self.lowerBound : self.upperBound < value ? self.upperBound : value
  }
}

class View: UIView {
  let image: UIImage
  let colorMap: [UIColor: String]
  
  init(image: UIImage, colorMap: [UIColor: String]) {
    self.image = image
    self.colorMap = colorMap
 
    super.init(
      frame: CGRect(
        origin: .zero,
        size: image.size
      )
    )
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func draw(_ rect: CGRect) {
    var cache = [UIColor: String]()
    
    let (w, h) = (
      rect.width / resolution,
      rect.height / resolution
    )
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
      .paragraphStyle: paragraph,
      .font: UIFont.systemFont(
        ofSize: (rect.width / resolution) * 0.098
      )
    ]
    (0..<Int(w)).forEach { ix in
      (0..<Int(h)).forEach { iy in
        let (x, y) = (CGFloat(ix), CGFloat(iy))
        let rect = CGRect(
          x: x * resolution,
          y: y * resolution,
          width: resolution,
          height: resolution
        )
        
        guard let color = image.pixelColor(at: rect.origin) else {
          return
        }
        
        let text: String = {
          if let v = cache[color] {
            return v
          }
          
          let sorted = colorMap.sorted(by: { (lhs, rhs) -> Bool in
            return lhs.key.distance(from: color) < rhs.key.distance(from: color)
          })
          let value = sorted[0].value
          cache[color] = value
          return value
        }()
        
        text.draw(
          with: rect,
          options: .usesLineFragmentOrigin,
          attributes: attributes,
          context: nil
        )
      }
    }
  }
}

let imageComp = imageFileName.components(separatedBy: ".")
let url = Bundle.main.url(
  forResource: imageComp[0],
  withExtension: imageComp[1]
  )!
let data = try Data(contentsOf: url)
guard let image = UIImage(data: data) else {
  throw Error.invalidInputImage(imageFileName)
}
let view = View(image: image, colorMap: try createColorMap())
PlaygroundPage.current.liveView = view


// Writes output to file

let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
let rendered = renderer.image { ctx in
  view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
}
let writePath = playgroundSharedDataDirectory.appendingPathComponent("out.png")
try rendered.pngData()!.write(to: writePath)
print("wrote to \(writePath)")
