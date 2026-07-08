# Kiln — how it works & how to generate code for it

Kiln is a **Swift/SwiftUI interpreter** that runs source code at runtime (no
compilation). It renders **real SwiftUI views** from a **subset** of Swift. Bond
uses it as the "native" runtime: a generated `Main.swift` is interpreted and
shown live on device.

This guide is the source of truth for what Kiln supports. It is distilled into
the agent system prompt and the build-error hints. It was validated against five
hand-written apps that all render and pass buildCheck: **Todo, Calculator,
Tic-Tac-Toe, Pong, Tetris.**

---

## 1. Entry point

The file must BE a single complete view struct named `ContentView`:

```swift
import SwiftUI
struct ContentView: View {
    @State private var count = 0
    var body: some View {
        VStack { Text("\(count)"); Button("+") { count += 1 } }
    }
}
```

- Kiln renders `ContentView` automatically — do **not** add an `@main App`, a
  `PreviewProvider` is ignored, and do **not** write a stub/reference like
  `\(ContentView())`. The whole program lives in this one struct.
- Write **real newlines** between lines. A file emitted as one line with literal
  `\n` escapes will not parse ("no view produced").

## 2. Supported language subset

**State & data**
- `@State` / `@State private var` holding Int, Double, String, Bool, Array,
  Dictionary, or tuples. Plain `let` constants also work.
- Dictionaries: `["key": value]`, read with `obj["key"]`.
- Tuples: positional `(100, 200)` → `.0`/`.1`; labeled `(x: 1, y: 2)` → `.x`/`.y`.
  Both are mutable: `p.x += 5`, `arr[0].0 = 9`.

**Expressions**
- Arithmetic `+ - * / %`, comparisons, `&&` `||` `!`, unary minus `-x`, ternary
  `a ? b : c`, ranges `0..<n` / `0...n`, string interpolation `"\(x)"`.
- Arrays: `append`, `insert(_:at:)`, `remove(at:)`, `removeLast/First`,
  `removeAll`, `sort`, `reverse`, `shuffle`, `map`, `filter`, `reduce(0, +)`,
  `sorted`, `shuffled`, `randomElement`, `min`, `max`, `count`, `first`, `last`,
  `isEmpty`, `contains`, `+` (concat). Spread inside a literal: `[a, ...xs.map { … }, b]`.
- Strings: `split(separator:)`, `replacingOccurrences(of:with:)`, `uppercased`,
  `lowercased`, `hasPrefix`, `contains`, `count`, `+`.
- Math: `sqrt pow abs min max floor ceil round`.
- Random: `Int.random(in: 1...6)`, `Double.random(in: 0...1)`, `arr.randomElement()`.

**Control flow & functions**
- `if/else`, `switch`, `func` (with params + return), **`for x in collection { … }`**
  and `for i in 0..<n { … }` loops, subscript assignment `arr[i] = v`.
- Helper functions called from `body` are fine, including ones that build and
  return data with a local `var` + a `for` loop (e.g. a `cells()` that assembles
  game shapes). Mutating local vars in such a function does **not** loop the
  renderer.

**Views**: VStack/HStack/ZStack, Text, Button, Image(systemName:), Label,
TextField, Toggle, Slider, ScrollView, ForEach (over ranges, arrays, and `id: \.self`),
Spacer, Divider, Rectangle/RoundedRectangle/Circle/Capsule, LinearGradient,
LazyVGrid, GeometryReader, BarChart([nums])/LineChart([nums]).

**Modifiers**: padding, frame (incl. maxWidth/maxHeight: .infinity), foregroundColor/
foregroundStyle, background, font (.title/.headline/.body/.caption/.system(size:)…),
cornerRadius, opacity, bold, italic, onTapGesture, onAppear, onChange, .dragToMove().

**Colors** (use these names or hex `#RRGGBB`): red, orange, yellow, green, mint,
teal, cyan, blue, indigo, purple, pink, brown, white, black, gray, primary,
secondary. An unknown color name renders invisibly — stick to the list.

## 3. Native game / animation API

Use **these** for any game, animation, or canvas drawing — NOT SwiftUI `Canvas`,
`Timer`, `TimelineView`, or `AnimatableData` (Kiln rejects those).

- `GameCanvas(shapes)` — a full-screen surface. `shapes` is an array of shape
  objects, redrawn whenever `@State` changes. It can be an inline literal **or**
  the return value of a helper function (`GameCanvas(cells())`):
  ```
  rect:   ["type": "rect",   "x": X, "y": Y, "w": W, "h": H, "color": C]
  circle: ["type": "circle", "x": X, "y": Y, "r": R, "color": C]
  text:   ["type": "text",   "x": X, "y": Y, "text": S, "size": SZ, "color": C]
  ```
  Coordinates are points from the top-left (screen ≈ 393 wide).
- `.onTick(seconds) { … }` — the game loop; mutate `@State` to animate. Use a few
  ticks/sec for grid games (e.g. `.onTick(0.18)`), ~0.016 for smooth motion.
- `.onSwipe { dir in … }` — `dir` is "up"/"down"/"left"/"right".
- `.onTapGesture { … }` — a tap (restart, place a mark, etc.).

## 4. NOT supported — avoid

- `class`, custom `struct`/`enum` **data types** (model data as dictionaries or
  tuples instead), generics, protocols, Combine.
- SwiftUI `Canvas`, `Timer`, `TimelineView`, `AnimatableData`, `@StateObject`,
  `ObservableObject`, `async/await` beyond provided helpers.
- `@main` / `App` / scene types — only `ContentView`.

## 5. Validated patterns (from the test apps)

- **List/CRUD (Todo):** `@State var items = [...]`; `TextField` + `Button` to
  `append`; `ScrollView { ForEach(items, id: \.self) { item in … } }`. Each row
  shows its own item correctly (loop variable is per-row).
- **Grid of buttons (Calculator, Tic-Tac-Toe):** nested `ForEach` over rows/ranges;
  `Button(label) { method() }`; subscript writes `board[i] = turn`.
- **Real-time game (Pong):** `GameCanvas([... state-driven shapes ...])` +
  `.onTick(0.016)` bounce physics + `.onSwipe` paddle.
- **Computed shapes + loop (Tetris):** `GameCanvas(cells())` where `cells()` uses
  `var shapes = [...]`, a `for` loop over landed pieces, and `return shapes`;
  `.onTick` gravity; `.onSwipe` move.
