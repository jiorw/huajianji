import SwiftUI

/// 一组筛完撒的彩带，一次性下落不循环
struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let drift: CGFloat
        let width: CGFloat
        let height: CGFloat
        let color: Color
        let spin: Double
        let duration: Double
        let delay: Double
    }

    @State private var started = false
    private let pieces: [Piece]

    init(count: Int = 46) {
        let palette: [Color] = [
            Color(red: 0.36, green: 0.50, blue: 1.0),
            Color(red: 1.00, green: 0.35, blue: 0.35),
            Color(red: 0.45, green: 0.90, blue: 0.40),
            Color(red: 1.00, green: 0.78, blue: 0.30),
            Color(red: 0.80, green: 0.45, blue: 1.00),
        ]
        self.pieces = (0..<count).map { i in
            Piece(id: i,
                  x: .random(in: 0...1),
                  drift: .random(in: -70...70),
                  width: .random(in: 6...11),
                  height: .random(in: 9...17),
                  color: palette[i % palette.count],
                  spin: .random(in: 260...900) * (Bool.random() ? 1 : -1),
                  duration: .random(in: 1.7...3.0),
                  delay: .random(in: 0...0.6))
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(started ? piece.spin : 0))
                        .opacity(started ? 0 : 1)
                        .position(x: piece.x * geo.size.width + (started ? piece.drift : 0),
                                  y: started ? geo.size.height * 1.05 : -24)
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: started)
                }
            }
        }
        .onAppear { started = true }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
