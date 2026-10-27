import SwiftUI

enum Side {
    case white, black

    var opponent: Side { self == .white ? .black : .white }
    var name: String { self == .white ? "White" : "Black" }
}

enum Kind {
    case king, queen, rook, bishop, knight, pawn

    var value: Int {
        switch self {
        case .queen: return 9
        case .rook: return 5
        case .bishop, .knight: return 3
        case .pawn: return 1
        case .king: return 0
        }
    }

    var letter: String {
        switch self {
        case .king: return "K"
        case .queen: return "Q"
        case .rook: return "R"
        case .bishop: return "B"
        case .knight: return "N"
        case .pawn: return ""
        }
    }

    var glyph: String {
        switch self {
        case .king: return "♚"
        case .queen: return "♛"
        case .rook: return "♜"
        case .bishop: return "♝"
        case .knight: return "♞"
        case .pawn: return "♟\u{FE0E}"
        }
    }
}

struct Piece: Identifiable {
    let id: Int
    var kind: Kind
    let side: Side
    var hasMoved = false
}

struct Move {
    let from: Int
    let to: Int
    var rookFrom = -1
    var rookTo = -1
}

struct Game {
    static let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
    static let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    static let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    static let knightJumps = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]

    static func squareName(_ i: Int) -> String {
        files[i % 8] + "\(8 - i / 8)"
    }

    var squares: [Piece?] = Game.start()
    var turn: Side = .white
    var history: [String] = []
    var captured: [Piece] = []
    var lastMove: Move?
    var result: String?

    static func start() -> [Piece?] {
        var board: [Piece?] = Array(repeating: nil, count: 64)
        let back: [Kind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for c in 0..<8 {
            board[c] = Piece(id: c, kind: back[c], side: .black)
            board[8 + c] = Piece(id: 8 + c, kind: .pawn, side: .black)
            board[48 + c] = Piece(id: 48 + c, kind: .pawn, side: .white)
            board[56 + c] = Piece(id: 56 + c, kind: back[c], side: .white)
        }
        return board
    }

    var pieces: [(piece: Piece, square: Int)] {
        squares.indices.compactMap { i in squares[i].map { (piece: $0, square: i) } }
    }

    func onBoard(_ r: Int, _ c: Int) -> Bool {
        r >= 0 && r < 8 && c >= 0 && c < 8
    }

    /// Whether `side` attacks square `target`.
    func attacked(_ target: Int, by side: Side) -> Bool {
        let r = target / 8
        let c = target % 8
        let pawnRow = side == .white ? r + 1 : r - 1
        for dc in [-1, 1] {
            if onBoard(pawnRow, c + dc), let p = squares[pawnRow * 8 + c + dc], p.side == side, p.kind == .pawn {
                return true
            }
        }
        for (dr, dc) in Game.knightJumps {
            if onBoard(r + dr, c + dc), let p = squares[(r + dr) * 8 + c + dc], p.side == side, p.kind == .knight {
                return true
            }
        }
        for (dr, dc) in Game.straight + Game.diagonal {
            var k = 1
            while onBoard(r + dr * k, c + dc * k) {
                if let p = squares[(r + dr * k) * 8 + c + dc * k] {
                    if p.side == side {
                        let isStraight = dr == 0 || dc == 0
                        if p.kind == .queen || (p.kind == .king && k == 1)
                            || (isStraight && p.kind == .rook) || (!isStraight && p.kind == .bishop) {
                            return true
                        }
                    }
                    break
                }
                k += 1
            }
        }
        return false
    }

    func kingSquare(_ side: Side) -> Int? {
        squares.firstIndex { $0?.kind == .king && $0?.side == side }
    }

    func inCheck(_ side: Side) -> Bool {
        guard let k = kingSquare(side) else { return false }
        return attacked(k, by: side.opponent)
    }

    /// Moves by the rules of each piece, before checking the king is safe.
    func reachable(from i: Int) -> [Move] {
        guard let p = squares[i] else { return [] }
        let r = i / 8
        let c = i % 8
        var out: [Move] = []

        func slide(_ dirs: [(Int, Int)], far: Bool) {
            for (dr, dc) in dirs {
                var k = 1
                while onBoard(r + dr * k, c + dc * k) {
                    let to = (r + dr * k) * 8 + c + dc * k
                    if let q = squares[to] {
                        if q.side != p.side { out.append(Move(from: i, to: to)) }
                        break
                    }
                    out.append(Move(from: i, to: to))
                    if !far { break }
                    k += 1
                }
            }
        }

        switch p.kind {
        case .pawn:
            let dir = p.side == .white ? -1 : 1
            if onBoard(r + dir, c), squares[(r + dir) * 8 + c] == nil {
                out.append(Move(from: i, to: (r + dir) * 8 + c))
                let home = p.side == .white ? 6 : 1
                if r == home, squares[(r + 2 * dir) * 8 + c] == nil {
                    out.append(Move(from: i, to: (r + 2 * dir) * 8 + c))
                }
            }
            for dc in [-1, 1] {
                if onBoard(r + dir, c + dc), let q = squares[(r + dir) * 8 + c + dc], q.side != p.side {
                    out.append(Move(from: i, to: (r + dir) * 8 + c + dc))
                }
            }
        case .knight:
            slide(Game.knightJumps, far: false)
        case .bishop:
            slide(Game.diagonal, far: true)
        case .rook:
            slide(Game.straight, far: true)
        case .queen:
            slide(Game.straight + Game.diagonal, far: true)
        case .king:
            slide(Game.straight + Game.diagonal, far: false)
            let enemy = p.side.opponent
            if !p.hasMoved && !attacked(i, by: enemy) {
                if let rook = squares[r * 8 + 7], rook.kind == .rook, !rook.hasMoved,
                   squares[r * 8 + 5] == nil, squares[r * 8 + 6] == nil,
                   !attacked(r * 8 + 5, by: enemy), !attacked(r * 8 + 6, by: enemy) {
                    out.append(Move(from: i, to: r * 8 + 6, rookFrom: r * 8 + 7, rookTo: r * 8 + 5))
                }
                if let rook = squares[r * 8], rook.kind == .rook, !rook.hasMoved,
                   squares[r * 8 + 1] == nil, squares[r * 8 + 2] == nil, squares[r * 8 + 3] == nil,
                   !attacked(r * 8 + 2, by: enemy), !attacked(r * 8 + 3, by: enemy) {
                    out.append(Move(from: i, to: r * 8 + 2, rookFrom: r * 8, rookTo: r * 8 + 3))
                }
            }
        }
        return out
    }

    /// Moves that don't leave your own king in check.
    func legalMoves(from i: Int) -> [Move] {
        guard let p = squares[i], p.side == turn else { return [] }
        return reachable(from: i).filter { move in
            var next = self
            next.place(move)
            return !next.inCheck(p.side)
        }
    }

    func hasLegalMove() -> Bool {
        for i in squares.indices {
            if let p = squares[i], p.side == turn, !legalMoves(from: i).isEmpty {
                return true
            }
        }
        return false
    }

    /// Moves the pieces only (used to test a move before playing it).
    mutating func place(_ move: Move) {
        guard var p = squares[move.from] else { return }
        p.hasMoved = true
        if p.kind == .pawn && (move.to / 8 == 0 || move.to / 8 == 7) {
            p.kind = .queen
        }
        squares[move.to] = p
        squares[move.from] = nil
        if move.rookFrom >= 0, var rook = squares[move.rookFrom] {
            rook.hasMoved = true
            squares[move.rookTo] = rook
            squares[move.rookFrom] = nil
        }
    }

    mutating func play(_ move: Move) {
        guard let p = squares[move.from] else { return }
        var name: String
        if move.rookFrom >= 0 {
            name = move.to % 8 == 6 ? "O-O" : "O-O-O"
        } else {
            let takes = squares[move.to] != nil
            if p.kind == .pawn {
                name = (takes ? Game.files[move.from % 8] + "x" : "") + Game.squareName(move.to)
                if move.to / 8 == 0 || move.to / 8 == 7 { name += "=Q" }
            } else {
                name = p.kind.letter + (takes ? "x" : "") + Game.squareName(move.to)
            }
        }
        if let taken = squares[move.to] {
            captured.append(taken)
        }
        place(move)
        lastMove = move
        turn = turn.opponent
        if !hasLegalMove() {
            if inCheck(turn) {
                name += "#"
                result = "\(turn.opponent.name) wins in \(history.count / 2 + 1) moves"
            } else {
                result = "Stalemate"
            }
        } else if inCheck(turn) {
            name += "+"
        }
        history.append(name)
    }

    func material(_ side: Side) -> Int {
        captured.filter { $0.side != side }.reduce(0) { $0 + $1.kind.value }
    }
}

struct ContentView: View {
    @State private var game = Game()
    @State private var selected: Int?
    @State private var targets: [Move] = []

    private let lightSquare = Color(red: 0.89, green: 0.86, blue: 0.80)
    private let darkSquare = Color(red: 0.40, green: 0.47, blue: 0.62)
    private let glow = Color(red: 0.42, green: 0.52, blue: 1.0)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.20), Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [glow.opacity(0.28), Color.clear], center: .center, startRadius: 20, endRadius: 340)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                Spacer(minLength: 4)
                playerCard(.black)
                board
                playerCard(.white)
                Spacer(minLength: 4)
                moveList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let result = game.result {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                resultCard(result)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chess")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
            Button(action: newGame) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("New game")
        }
    }

    private var status: String {
        if game.result != nil { return "Game over" }
        if game.history.isEmpty { return "Pass and play · tap a piece" }
        return "Move \(game.history.count / 2 + 1)"
    }

    private func playerCard(_ side: Side) -> some View {
        let active = game.turn == side && game.result == nil
        let checked = active && game.inCheck(side)
        let taken = game.captured.filter { $0.side != side }.sorted { $0.kind.value > $1.kind.value }
        let lead = game.material(side) - game.material(side.opponent)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(side == .white ? Color.white : Color(white: 0.17))
                Text("♚")
                    .font(.system(size: 24))
                    .foregroundStyle(side == .white ? Color.black : Color.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(side.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 1) {
                    ForEach(taken) { p in
                        Text(p.kind.glyph)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    if lead > 0 {
                        Text("+\(lead)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .padding(.leading, 4)
                    }
                }
                .frame(height: 16)
            }
            Spacer()
            if active {
                Text(checked ? "Check" : "To move")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(checked ? Color.white : Color.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(checked ? Color.red : Color(red: 0.56, green: 0.95, blue: 0.68), in: Capsule())
            }
        }
        .padding(10)
        .background(Color.white.opacity(active ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(active ? 0.28 : 0.06), lineWidth: 1))
    }

    private var board: some View {
        GeometryReader { geo in
            let size = geo.size.width / 8
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { c in
                                square(r * 8 + c, size: size)
                            }
                        }
                    }
                }
                ForEach(game.pieces, id: \.piece.id) { item in
                    Text(item.piece.kind.glyph)
                        .font(.system(size: size * 0.8))
                        .foregroundStyle(item.piece.side == .white ? Color.white : Color(white: 0.1))
                        .shadow(color: item.piece.side == .white ? Color.black.opacity(0.75) : Color.white.opacity(0.35), radius: 1)
                        .shadow(color: Color.black.opacity(0.35), radius: 3, y: 2)
                        .scaleEffect(selected == item.square ? 1.15 : 1)
                        .frame(width: size, height: size)
                        .position(x: CGFloat(item.square % 8) * size + size / 2,
                                  y: CGFloat(item.square / 8) * size + size / 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: glow.opacity(0.35), radius: 28)
        .shadow(color: Color.black.opacity(0.6), radius: 20, y: 12)
    }

    private func square(_ i: Int, size: CGFloat) -> some View {
        let r = i / 8
        let c = i % 8
        let light = (r + c) % 2 == 0
        let isTarget = targets.contains { $0.to == i }
        let isLast = game.lastMove?.from == i || game.lastMove?.to == i
        let inCheckHere = game.squares[i]?.kind == .king && game.squares[i]?.side == game.turn && game.inCheck(game.turn)
        return ZStack {
            Rectangle()
                .fill(light ? lightSquare : darkSquare)
            if isLast {
                Rectangle().fill(Color.yellow.opacity(0.30))
            }
            if selected == i {
                Rectangle().fill(Color.yellow.opacity(0.50))
            }
            if inCheckHere {
                RadialGradient(colors: [Color.red, Color.red.opacity(0)], center: .center, startRadius: 2, endRadius: size * 0.62)
            }
            if isTarget {
                if game.squares[i] != nil {
                    Circle()
                        .stroke(Color.black.opacity(0.3), lineWidth: size * 0.09)
                        .padding(size * 0.05)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: size * 0.3, height: size * 0.3)
                }
            }
            if c == 0 {
                Text("\(8 - r)")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(light ? darkSquare : lightSquare)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(3)
            }
            if r == 7 {
                Text(Game.files[c])
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(light ? darkSquare : lightSquare)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { tap(i) }
        .accessibilityLabel(Game.squareName(i))
    }

    private var moveList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<(game.history.count + 1) / 2, id: \.self) { n in
                    HStack(spacing: 6) {
                        Text("\(n + 1).")
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(game.history[n * 2])
                            .foregroundStyle(.white)
                        if n * 2 + 1 < game.history.count {
                            Text(game.history[n * 2 + 1])
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
        }
        .frame(height: 36)
    }

    private func resultCard(_ text: String) -> some View {
        VStack(spacing: 12) {
            Text("♚")
                .font(.system(size: 72))
                .foregroundStyle(LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.orange.opacity(0.6), radius: 16)
            Text(game.inCheck(game.turn) ? "Checkmate" : "Draw")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(text)
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.7))
            Button(action: newGame) {
                Text("Play again")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 13)
                    .background(Color.white, in: Capsule())
            }
            .padding(.top, 6)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 30, y: 10)
        .transition(.scale.combined(with: .opacity))
    }

    private func newGame() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            game = Game()
            selected = nil
            targets = []
        }
    }

    private func tap(_ i: Int) {
        guard game.result == nil else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if let move = targets.first(where: { $0.to == i }) {
                game.play(move)
                selected = nil
                targets = []
            } else if let p = game.squares[i], p.side == game.turn, selected != i {
                selected = i
                targets = game.legalMoves(from: i)
            } else {
                selected = nil
                targets = []
            }
        }
    }
}
