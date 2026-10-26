Here is a memory matching card game in SwiftUI with emoji cards, a move counter, and a win message:

```swift
import SwiftUI

struct MemoryMatchingGame: View {
    // State variables for game elements
    @State private var cards: [Int: EmojiCard] = [
        0: EmojiCard(image: "🐶"),
        1: EmojiCard(image: "🐱"),
        2: EmojiCard(image: "🍎"),
        3: EmojiCard(image: "🚗")
    ]
    @State private var flippedCards: Set<Int> = []
    @State private var moveCount: Int = 0
    @State private var isGameOver: Bool = false
    @State private var winningMessage: String = ""

    // Function to flip a card
    func flipCard(_ index: Int) {
        // Check if the card is already flipped
        if flippedCards.contains(index) { return }

        // Check if the card is a duplicate
        if cards.values.contains(where: { $0.image == cards[index]?.image }) {
            return
        }

        // Increment move counter
        moveCount += 1

        // Add the card to the flipped cards set
        flippedCards.insert(index)

        // Check if all cards are flipped
        if flippedCards.count == cards.count / 2 {
            isGameOver = true
            winningMessage = "You won! 🎉"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Display the move counter
            Text("Moves: \(moveCount)")

            // Display the winning message if the game is over
            if isGameOver {
                Text(winningMessage)
                    .font(.largeTitle)
                    .foregroundColor(.green)
            }

            // Display the cards
            ForEach(Array(cards.keys).sorted(), id: \.self) { index in
                // Check if the card is flipped
                if flippedCards.contains(index) {
                    // Display the flipped card
                    EmojiCard(image: cards[index]?.image ?? "🍎")
                        .frame(width: 100, height: 150)
                        .background(Color.white)
                        .cornerRadius(10)
                } else {
                    // Display the card face down
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 100, height: 150)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
}

// Custom emoji card view
struct EmojiCard: View {
    var image: String

    var body: some View {
        Text(image)
            .font(.largeTitle)
            .foregroundColor(.black)
            .padding()
            .background(Color.white)
            .cornerRadius(10)
    }
}

// Emoji data
let emojis: [String: String] = [
    "🐶": "🐶",
    "🐱": "🐱",
    "🍎": "🍎",
    "🚗": "🚗"
]

// Preview provider
struct MemoryMatchingGame_Previews: PreviewProvider {
    static var previews: some View {
        MemoryMatchingGame()
    }
}
```