import SwiftUI

// Graferne tegnes i webappens SVG-koordinater (viewBox) og skaleres til bredden.

/// .drawin (venstre mod højre) og .rise (nedefra og op).
struct Reveal: ViewModifier {
    enum Kind { case drawin, rise }
    var kind: Kind
    var delay: Double = 0
    @State private var p: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: kind == .drawin ? .leading : .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .frame(
                            width: kind == .drawin ? geo.size.width * p : geo.size.width,
                            height: kind == .rise ? geo.size.height * p : geo.size.height
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: kind == .drawin ? .leading : .bottom)
                }
            }
            .onAppear {
                if reduceMotion {
                    p = 1
                } else {
                    let dur = kind == .drawin ? 0.9 : 0.7
                    withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: dur).delay(delay)) { p = 1 }
                }
            }
    }
}

extension View {
    func reveal(_ kind: Reveal.Kind, delay: Double = 0) -> some View {
        modifier(Reveal(kind: kind, delay: delay))
    }
}

/// Et lærred med webappens koordinater: tegner i (0..W, 0..H) og skalerer til bredden.
struct ViewBoxCanvas: View {
    let w: CGFloat
    let h: CGFloat
    let draw: (inout GraphicsContext, CGFloat) -> Void

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / w
            draw(&ctx, k)
        }
        .aspectRatio(w / h, contentMode: .fit)
    }
}

// MARK: - spark()

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var delay: Double = 0

    var body: some View {
        let v = Array(values.suffix(12))
        let n = v.count
        let W: CGFloat = 64, H: CGFloat = 26, p: CGFloat = 3
        if n < 2 {
            ViewBoxCanvas(w: W, h: H) { ctx, k in
                let r: CGFloat = 2.5 * k
                ctx.fill(Path(ellipseIn: CGRect(x: W / 2 * k - r, y: H / 2 * k - r, width: 2 * r, height: 2 * r)),
                         with: .color(T.muted))
            }
            .frame(width: 64)
        } else {
            let mn = v.min()!, mx = v.max()!
            ViewBoxCanvas(w: W, h: H) { ctx, k in
                func X(_ i: Int) -> CGFloat { (p + CGFloat(i) * (W - 2 * p) / CGFloat(n - 1)) * k }
                func Y(_ x: Double) -> CGFloat {
                    (mx == mn ? H / 2 : H - p - CGFloat((x - mn) / (mx - mn)) * (H - 2 * p)) * k
                }
                var path = Path()
                for (i, x) in v.enumerated() {
                    let pt = CGPoint(x: X(i), y: Y(x))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, lineJoin: .round))
                let r: CGFloat = 2.4 * k
                let end = CGPoint(x: X(n - 1), y: Y(v[n - 1]))
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color))
            }
            .frame(width: 64)
            .reveal(.drawin, delay: delay)
        }
    }
}

// MARK: - volChart()

struct VolumeChart: View {
    let vols: [Double]
    let firstDate: String
    let lastDate: String

    var body: some View {
        let n = vols.count
        let W: CGFloat = 320, H: CGFloat = 130, pt: CGFloat = 22, pb: CGFloat = 18
        let mxRaw = vols.max() ?? 0
        let mx = mxRaw == 0 ? 1 : mxRaw
        let slot = W / CGFloat(max(n, 1))
        let bw = min(28, slot * 0.62)

        VStack(alignment: .leading, spacing: 8) {
            ViewBoxCanvas(w: W, h: H) { ctx, k in
                    for (i, v) in vols.enumerated() {
                        let h = max(2, CGFloat(v / mx) * (H - pt - pb))
                        let x = CGFloat(i) * slot + (slot - bw) / 2
                        let rect = CGRect(x: x * k, y: (H - pb - h) * k, width: bw * k, height: h * k)
                        let last = i == n - 1
                        ctx.fill(Path(rect), with: .color(last ? T.blue : T.ink.opacity(0.18)))
                    }
                    var base = Path()
                    base.move(to: CGPoint(x: 0, y: (H - pb) * k))
                    base.addLine(to: CGPoint(x: W * k, y: (H - pb) * k))
                    ctx.stroke(base, with: .color(T.hair), lineWidth: 1)
                }
                .reveal(.rise)
                .overlay {
                    chartLabels(
                        left: "Maks: \(fmt(mx / 1000)) t",
                        right: "Seneste: \(fmt((vols.last ?? 0) / 1000)) t",
                        bottomLeft: firstDate,
                        bottomRight: n > 1 ? lastDate : ""
                    )
                }
            Text("De seneste \(n) træninger. Den blå er den nyeste.")
                .smallMuted()
        }
        .padding(.top, 6)
    }
}

/// Tekstetiketter i hjørnerne af en graf.
@MainActor
func chartLabels(left: String, right: String, bottomLeft: String, bottomRight: String) -> some View {
    VStack(spacing: 0) {
        HStack {
            Text(left).foregroundStyle(T.muted)
            Spacer()
            Text(right).fontWeight(.bold).foregroundStyle(T.ink)
        }
        .font(.system(size: 11))
        Spacer()
        HStack {
            Text(bottomLeft)
            Spacer()
            Text(bottomRight)
        }
        .font(.system(size: 10))
        .foregroundStyle(T.muted)
    }
    .monospacedDigit()
}

// MARK: - chartSVG(rows, key)

enum Metric: String, CaseIterable {
    case e1, top, vol

    var label: String {
        switch self {
        case .e1: return "1RM"
        case .top: return "Tungeste sæt"
        case .vol: return "Volumen"
        }
    }

    var note: String {
        switch self {
        case .e1: return "Estimeret 1RM ud fra vægt, gentagelser og hvad du havde i tanken. Det er den, der skal stige."
        case .top: return "Den tungeste vægt, du løftede i øvelsen, per træning."
        case .vol: return "Samlet vægt × gentagelser i øvelsen per træning."
        }
    }

    func value(_ r: StatRow) -> Double {
        switch self {
        case .e1: return r.e1
        case .top: return r.top
        case .vol: return r.vol
        }
    }
}

struct StatChart: View {
    let rows: [StatRow]
    let key: Metric

    var body: some View {
        let vals = rows.map { key.value($0) }
        let n = vals.count
        if n > 0 {
            let W: CGFloat = 320, H: CGFloat = 170, pl: CGFloat = 8, pr: CGFloat = 8, pt: CGFloat = 24, pb: CGFloat = 22
            let mn = vals.min()!, mx = vals.max()!
            let padRaw = (mx - mn) * 0.2
            let pad = padRaw != 0 ? padRaw : max(2, mx * 0.05)
            let lo = mn - pad, hi = mx + pad
            let best = vals.firstIndex(of: mx) ?? 0
            let fv: (Double) -> String = { key == .vol ? kg($0) : fmt($0) + " kg" }

            VStack(alignment: .leading, spacing: 8) {
                ViewBoxCanvas(w: W, h: H) { ctx, k in
                        func X(_ i: Int) -> CGFloat {
                            (n == 1 ? W / 2 : pl + CGFloat(i) * (W - pl - pr) / CGFloat(n - 1)) * k
                        }
                        func Y(_ v: Double) -> CGFloat {
                            (pt + CGFloat((hi - v) / (hi - lo)) * (H - pt - pb)) * k
                        }
                        for f in [0.0, 0.5, 1.0] {
                            let y = (pt + CGFloat(f) * (H - pt - pb)) * k
                            var g = Path()
                            g.move(to: CGPoint(x: 0, y: y))
                            g.addLine(to: CGPoint(x: W * k, y: y))
                            ctx.stroke(g, with: .color(T.hair), lineWidth: 1)
                        }
                        var line = Path()
                        for (i, v) in vals.enumerated() {
                            let p = CGPoint(x: X(i), y: Y(v))
                            if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                        }
                        if n > 1 {
                            var area = line
                            area.addLine(to: CGPoint(x: X(n - 1), y: (H - pb) * k))
                            area.addLine(to: CGPoint(x: X(0), y: (H - pb) * k))
                            area.closeSubpath()
                            ctx.fill(area, with: .color(T.blue.opacity(0.10)))
                            ctx.stroke(line, with: .color(T.blue),
                                       style: StrokeStyle(lineWidth: 2.5 * k, lineCap: .round, lineJoin: .round))
                        }
                        let rb: CGFloat = 8 * k
                        let bp = CGPoint(x: X(best), y: Y(mx))
                        ctx.stroke(Path(ellipseIn: CGRect(x: bp.x - rb, y: bp.y - rb, width: 2 * rb, height: 2 * rb)),
                                   with: .color(T.blue.opacity(0.35)), lineWidth: 2 * k)
                        for (i, v) in vals.enumerated() {
                            let r: CGFloat = (i == n - 1 ? 4 : 2.8) * k
                            let c = CGPoint(x: X(i), y: Y(v))
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                     with: .color(T.blue))
                        }
                    }
                    .reveal(.drawin)
                    .overlay {
                        chartLabels(
                            left: "Bedst: " + fv(mx),
                            right: "Nu: " + fv(vals[n - 1]),
                            bottomLeft: rows[0].date,
                            bottomRight: n > 1 ? rows[n - 1].date : ""
                        )
                    }
                if n == 1 {
                    Text("Første logning. Kurven vokser for hver træning.")
                        .smallMuted()
                }
            }
            .padding(.vertical, 6)
            .id(key)
        }
    }
}
