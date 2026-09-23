import SwiftUI
import MapKit

struct RunRouteMapView: UIViewRepresentable {
    let samples: [RunReplaySample]
    @Binding var selectedTime: Double
    let showMap: Bool

    func makeUIView(context: Context) -> RouteReplaySurface { RouteReplaySurface() }

    func updateUIView(_ view: RouteReplaySurface, context: Context) {
        view.onSelect = { selectedTime = $0 }
        view.configure(samples: samples, selectedTime: selectedTime, showMap: showMap)
    }
}

/// Drawing in screen space keeps all three stripes a readable, constant width.
/// The map and route-only modes use the same projection and hit-testing.
final class RouteReplaySurface: UIView, MKMapViewDelegate, UIGestureRecognizerDelegate {
    private let map = MKMapView()
    private let drawing = RouteStripeDrawing()
    private var samples: [RunReplaySample] = []
    private var routeIdentity: [RunRoutePoint] = []
    private var fittedSize = CGSize.zero
    private var selectedTime: Double = 0
    private var showMap = true
    var onSelect: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        map.delegate = self
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        addSubview(map)
        drawing.backgroundColor = .clear
        drawing.isUserInteractionEnabled = false
        addSubview(drawing)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(trace(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(trace(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(samples: [RunReplaySample], selectedTime: Double, showMap: Bool) {
        self.samples = samples.filter { $0.route != nil }
        self.selectedTime = selectedTime
        self.showMap = showMap
        map.isHidden = !showMap
        let identity = self.samples.compactMap(\.route)
        if identity != routeIdentity {
            routeIdentity = identity
            fittedSize = .zero
            setNeedsLayout()
        }
        refreshDrawing()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        map.frame = bounds
        drawing.frame = bounds
        if fittedSize != bounds.size, bounds.width > 0, bounds.height > 0, !routeIdentity.isEmpty {
            fittedSize = bounds.size
            let rect = routeBounds()
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 34, bottom: 34, right: 34), animated: false)
        }
        refreshDrawing()
    }

    private func routeBounds() -> MKMapRect {
        let points = routeIdentity.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1
        let width = max(200, maxX - minX)
        let height = max(200, maxY - minY)
        return MKMapRect(x: (minX + maxX - width) / 2, y: (minY + maxY - height) / 2, width: width, height: height)
    }

    private func projectedPoints() -> [CGPoint] {
        if showMap {
            return routeIdentity.map { map.convert(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), toPointTo: drawing) }
        }
        let rect = routeBounds()
        let scale = min(max(1, bounds.width - 68) / rect.width, max(1, bounds.height - 114) / rect.height)
        return routeIdentity.map {
            let point = MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            return CGPoint(x: bounds.midX + (point.x - rect.midX) * scale,
                           y: bounds.midY + 23 + (point.y - rect.midY) * scale)
        }
    }

    private func refreshDrawing() {
        drawing.samples = samples
        drawing.points = projectedPoints()
        drawing.selectedTime = selectedTime
        drawing.setNeedsDisplay()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { refreshDrawing() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        nearestSample(to: touch.location(in: self), maximumDistance: 34) != nil
    }

    @objc private func trace(_ gesture: UIGestureRecognizer) {
        guard let sample = nearestSample(to: gesture.location(in: self), maximumDistance: 60) else { return }
        onSelect?(sample.timestamp)
    }

    private func nearestSample(to touch: CGPoint, maximumDistance: CGFloat) -> RunReplaySample? {
        let points = projectedPoints()
        guard points.count > 1 else { return nil }
        var best: (index: Int, fraction: Double, distance: CGFloat)?
        for i in 1..<points.count where samples[i].section == samples[i - 1].section {
            let a = points[i - 1], b = points[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = min(1, max(0, ((touch.x - a.x) * dx + (touch.y - a.y) * dy) / max(0.001, lengthSquared)))
            let distance = hypot(touch.x - a.x - t * dx, touch.y - a.y - t * dy)
            // At crossings, prefer the passage closest to the selected time.
            if let previous = best, abs(distance - previous.distance) < 4 {
                if abs(samples[i].timestamp - selectedTime) >= abs(samples[previous.index].timestamp - selectedTime) { continue }
            } else if let previous = best, distance >= previous.distance { continue }
            best = (i, Double(t), distance)
        }
        guard let best, best.distance <= maximumDistance else { return nil }
        return samples[best.fraction < 0.5 ? best.index - 1 : best.index]
    }
}

private final class RouteStripeDrawing: UIView {
    var samples: [RunReplaySample] = []
    var points: [CGPoint] = []
    var selectedTime: Double = 0

    override func draw(_ rect: CGRect) {
        guard points.count > 1, points.count == samples.count, let context = UIGraphicsGetCurrentContext() else { return }
        let paceRange = RunReplayPalette.paceRange(samples)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for i in 1..<points.count where samples[i].section == samples[i - 1].section {
            stroke(from: points[i - 1], to: points[i], color: UIColor.systemBackground.withAlphaComponent(0.88), width: 15, context: context)
        }
        for stripe in -1...1 {
            for i in 1..<points.count where samples[i].section == samples[i - 1].section {
                let a = offset(at: i - 1, stripe: stripe), b = offset(at: i, stripe: stripe)
                let sample = samples[i]
                let color: Color
                switch stripe {
                case -1: color = RunReplayPalette.pace(sample.pace, range: paceRange)
                case 0: color = RunReplayPalette.song(sample.songIndex)
                default: color = RunReplayPalette.heartRate(sample)
                }
                stroke(from: a, to: b, color: UIColor(color), width: 4, context: context)
            }
        }
        label("S", at: points[0], context: context)
        label("F", at: points[points.count - 1], context: context)
        if let index = samples.indices.min(by: { abs(samples[$0].timestamp - selectedTime) < abs(samples[$1].timestamp - selectedTime) }),
           abs(samples[index].timestamp - selectedTime) <= 12 {
            let point = points[index]
            context.setFillColor(UIColor.label.cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
            context.setStrokeColor(UIColor.systemBackground.cgColor)
            context.setLineWidth(3)
            context.strokeEllipse(in: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        }
    }

    private func offset(at index: Int, stripe: Int) -> CGPoint {
        let before = index > 0 && samples[index - 1].section == samples[index].section ? points[index - 1] : points[index]
        let after = index + 1 < points.count && samples[index + 1].section == samples[index].section ? points[index + 1] : points[index]
        let dx = after.x - before.x, dy = after.y - before.y
        let length = max(0.001, hypot(dx, dy))
        return CGPoint(x: points[index].x - dy / length * CGFloat(stripe) * 4.7,
                       y: points[index].y + dx / length * CGFloat(stripe) * 4.7)
    }

    private func stroke(from a: CGPoint, to b: CGPoint, color: UIColor, width: CGFloat, context: CGContext) {
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { return }
        context.beginPath()
        context.move(to: a)
        context.addLine(to: b)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.strokePath()
    }

    private func label(_ title: String, at point: CGPoint, context: CGContext) {
        let rect = CGRect(x: point.x - 9, y: point.y - 25, width: 18, height: 18)
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fillEllipse(in: rect)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (title as NSString).draw(in: rect.insetBy(dx: 0, dy: 1), withAttributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor.label, .paragraphStyle: style
        ])
    }
}
