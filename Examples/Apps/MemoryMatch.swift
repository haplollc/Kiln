import SwiftUI

struct Card: Identifiable {
    let id: Int
    let emoji: String
    var isFaceUp = false
    var isMatched = false
}

struct ContentView: View {
    @State private var cards: [Card] = []
    @State private var firstIndex: Int?
    @State private var moves = 0

    private let emojis = ["🐶", "🐱", "🦊", "🐼", "🐸", "🐵"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var hasWon: Bool {
        !cards.isEmpty && cards.allSatisfy { $0.isMatched }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Memory")
                    .font(.largeTitle.bold())
                Spacer()
                Text("Moves: \(moves)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(cards.indices, id: \.self) { index in
                    CardView(card: cards[index])
                        .onTapGesture {
                            flip(index)
                        }
                }
            }

            if hasWon {
                Text("You won in \(moves) moves! 🎉")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
            }

            Button("New Game", action: newGame)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear(perform: newGame)
    }

    private func flip(_ index: Int) {
        guard !cards[index].isFaceUp, !cards[index].isMatched else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            cards[index].isFaceUp = true
        }
        if let first = firstIndex {
            moves += 1
            if cards[first].emoji == cards[index].emoji {
                cards[first].isMatched = true
                cards[index].isMatched = true
            } else {
                let a = first
                let b = index
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation {
                        cards[a].isFaceUp = false
                        cards[b].isFaceUp = false
                    }
                }
            }
            firstIndex = nil
        } else {
            firstIndex = index
        }
    }

    private func newGame() {
        cards = (emojis + emojis).shuffled().enumerated().map { pair in
            Card(id: pair.offset, emoji: pair.element)
        }
        firstIndex = nil
        moves = 0
    }
}

struct CardView: View {
    let card: Card

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(card.isFaceUp || card.isMatched ? Color.white : Color.indigo)
                .shadow(radius: 2)
            if card.isFaceUp || card.isMatched {
                Text(card.emoji)
                    .font(.system(size: 40))
            } else {
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(height: 90)
        .opacity(card.isMatched ? 0.5 : 1)
        .rotation3DEffect(.degrees(card.isFaceUp || card.isMatched ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        .accessibilityLabel(card.isFaceUp || card.isMatched ? card.emoji : "Card \(card.id)")
    }
}
