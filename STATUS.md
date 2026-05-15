# Kiln — Support Status & Roadmap

## Plans 2–8 (2026-04-23) — user functions, Foundation, JSON, layout, AsyncImage

### Plan 2 — User-defined functions
- `func name(<params>) [async] [throws] -> T { body }` — captured as `.functionDecl`
  with `FunctionParameter` list (external label, internal name, type annotation as string).
- Top-level, enum-scoped (`BookService.search`), and extension-scoped (`View.shimmer`)
  functions register in `SwiftRunnerState.functions` (keyed by `name` or `Owner.name`).
- Calls dispatch via the function table first, falling back to built-ins — so user
  code shadows library calls when named identically.
- Parameter binding handles labeled and positional args; return values propagate via
  a `ReturnSignal` thrown out of `executeWithReturn` and caught by the caller.
- Early returns work inside `guard`, `do/catch`, `if/else`, and nested blocks.

### Plan 3 — Foundation value bridges (synchronous MVP)
- `URL(string:)`, `URLComponents(string:)`, `URLQueryItem(name:value:)` all return
  tagged `.object` values (`_type: URL/URLComponents/URLQueryItem`).
- `URL.absoluteString`, `URLComponents.url`, `HTTPURLResponse.statusCode`
  property-access reads implemented.
- `URLSession.shared` → tagged sentinel; `URLSession.shared.data(from: url)` fires
  a real synchronous fetch via `URLSession.shared.dataTask` + `DispatchSemaphore.wait`
  and returns `.array([Data-tagged, HTTPURLResponse-tagged])`.
- `try`/`try?`/`try!`/`await` are transparent prefixes; `throws` in function
  signatures is consumed and ignored. Throw/catch propagation still stubbed.
- `Task { body }` executes its closure synchronously.
- Tuple destructuring: `let (a, b, _) = expr` binds each named slot to the
  corresponding index of the evaluated array.
- Postfix `!` (force-unwrap) is eaten silently. `?.` chaining is *not*
  consumed at `parseCall` level so ternaries like `flag ? .blue : .red` stay intact.
- `.self` after `.` (e.g. `Response.self`) parses as a `"self"` property access.
- `Color(.systemX)` renders as `.gray` (system-color bridge is a no-op for now).

### Plan 4 — JSON decoding (schema-free)
- `JSONDecoder()` → tagged marker; `.decode(T.self, from: data)` ignores `T` and
  runs `JSONSerialization.jsonObject` over the `Data`-tagged bytes, converting the
  result to nested `Value` (`.object`/`.array`/`.string`/`.number`/`.boolean`/`.nil`).
- Property access on decoded values walks the JSON structure with no type-registry
  overhead — `resp.docs.first.title` works out-of-the-box as long as the JSON keys
  match. No custom `CodingKeys`, `init(from:)`, or property-wrapper support.

### Plan 6 — Layout containers
- `LazyVGrid(columns: [GridItem], spacing:) { ... }` → real SwiftUI `LazyVGrid`.
- `LazyHGrid(rows: [GridItem], spacing:) { ... }` → real SwiftUI `LazyHGrid`.
- `GridItem(.adaptive(minimum:maximum:))`, `.fixed(n)`, `.flexible()`.
- `GeometryReader { geo in ... }` — exposes `geo.size.width/height` via
  `state.renderVariables` under the captured closure binding name.
- `LinearGradient(colors:startPoint:endPoint:)` with `UnitPoint` values
  (`.top/.bottom/.leading/.trailing/.topLeading/.topTrailing/.bottomLeading/.bottomTrailing/.center`)
  renders as a real SwiftUI `LinearGradient`.

### Plan 8 — AsyncImage phase closure
- `AsyncImage(url:) { phase in switch phase { case .empty: ... case .success(let image): ...
  case .failure: ... @unknown default: ... } }` — parser hoists branches into
  `.asyncImagePhased(emptyBranch:successBranch:failureBranch:imageBinding:)`.
- Renderer maps to a real `AsyncImage(url:)` with a phase closure; the success
  branch splices in the live `SwiftUI.Image`, applying any modifier chain
  applied to the bound name (e.g. `image.resizable()`).

### Plan 5 — struct methods + property chain assignment
- Struct bodies now capture `func` declarations and hoist them into the runtime
  function table as `StructName.methodName` (shares the enum/extension hoisting
  path). `struct Shimmer: ViewModifier { func body(content:) -> some View { ... } }`
  registers `Shimmer.body`, and `extension View { func shimmer() -> some View { ... } }`
  registers `View.shimmer`.
- Property / subscript chain assignment: `obj.prop = value`, `obj.a.b = value`,
  `arr[i] = value`, `arr[0].field = value` — parsed via a bounded LHS scanner
  and executed via a recursive `writeInto` that mutates nested `.object`/`.array`
  values in place. Compound forms (`+=`/`-=`/`*=`/`/=`) honor the existing value.
- Statement-level `hasAssignOperatorBeforeBoundary` peek-ahead rules out
  non-assignments cheaply, so expression statements parse with no extra cost.
- **Render-time `.modifier(X())` dispatch.** `.modifier(Shimmer())` resolves
  `Shimmer.body(content:)` from the function table, substitutes every
  `.variable("content")` in the body with the receiver ViewNode, and renders the
  expanded tree. Chained user modifiers work (each receives the previous result
  as its `content`). Pending modifiers applied before a user modifier are folded
  into `content` automatically.
- **Computed properties on decoded objects.** `var authorLine: String { … }` in
  a struct body is captured as a zero-arg functionDecl and hoisted as
  `StructName.authorLine`. `JSONDecoder().decode(T.self, from:)` tags the
  top-level result (and array elements for bare-array roots) with `_type: T`.
  Property access on a tagged object falls through to the computed getter when
  the requested key is missing; the getter body runs with the object's fields
  bound as temporary variables.
- **Schema-propagated nested tagging.** Struct field type annotations captured
  at parse time (`let docs: [OpenLibraryDoc]` → schema maps `docs` → `OpenLibraryDoc`)
  are copied into `state.typeSchemas` and consulted by `tagWithSchema`. After
  decoding, nested arrays and object fields get their own `_type` tags, so
  `resp.docs.first.authorLine` dispatches the computed getter on each inner
  `OpenLibraryDoc`.

### Plan 7 — iOS chrome modifiers
- `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius:))` and the
  full material family (`.thinMaterial` / `.regularMaterial` / `.thickMaterial`
  / `.ultraThickMaterial` / `.bar`) — real SwiftUI material backgrounds with
  optional shape clipping.
- `.buttonStyle(.borderedProminent / .bordered / .borderless / .plain / .automatic)`
- `.textFieldStyle(.plain / .roundedBorder / .automatic)`
- `.controlSize(.mini / .small / .regular / .large / .extraLarge)`
- `.refreshable { await … }` — real pull-to-refresh; wraps the action with
  `await MainActor.run` so the interpreter body runs on the main actor.
- `.submitLabel` was already wired and remains functional.
- `withAnimation(curve) { body }` — body executes synchronously (curve captured
  but not yet applied through SwiftUI.withAnimation wrapping).
- `Task { body }` — body executes synchronously.
- `Color(.systemX)` → `.gray` for now.

## Plan 1 (2026-04-22) — parse-accepted, execution partially stubbed

The following syntactic forms now parse without errors. Execution semantics for most
arrive in later stages (see `docs/superpowers/plans/2026-04-21-swiftrunner-full-swift-runtime-roadmap.md`).

**New keywords:** `switch`, `case`, `default`, `do`, `catch`, `try`, `throws`, `throw`,
`guard`, `defer`, `enum`, `extension`, `protocol`, `async`, `await`.

**New attribute tokens:** `@MainActor`, `@ViewBuilder`, `@unknown`, `@available(...)`
and any other `@Name` / `@Name(...)` form — consumed transparently at parse time.

**Parser support (stubbed at runtime):**
- `switch <expr> { case <pattern>: <body> ... default: <body> }` — *evaluates at runtime*
  for literal string/number patterns and for `.caseMember` names matched against
  scrutinee's string representation. Full typed enum matching comes in Stage 4.
- `do { ... } catch [binding] { ... }` — body executes; catch clauses are no-ops
  until Stage 2/3 introduces real throws propagation.
- `try`, `try?`, `try!`, `await` — transparent prefixes (eaten, underlying expression parses).
- `throw <expr>` — parsed, no-op at runtime.
- `guard let x [= y] else { <block> }` — evaluates; if nil, executes the else block.
- `guard <cond> else { <block> }` — evaluates; if falsy, executes the else block.
- `defer { ... }` — parsed, no-op until real function scopes exist (Stage 2).
- `enum Name [: Conformances] { case A; case B(T); static func ...() }` — cases and
  members captured in the AST; type registry wiring comes in Stage 4.
- `extension Type [: Conformances] { ... }` — members captured in the AST.
- `protocol Foo { ... }` — body skipped entirely (not useful at runtime yet).
- `struct X: A, B, C { ... }` — arbitrary conformance lists accepted.
- Computed properties `var x: T { <body> }` and `{ get { } set { } }` — accepted
  inside struct bodies.
- `return [<expr>]` — accepted anywhere; no-op until function scopes exist.
- Keypath literals `\.self`, `\.prop`, `\.prop.sub` — lexed as dot-prefix tokens so
  `.compactMap(\.prop)` usage reads as member access.

## Currently Supported

### Views
| View | Status | Notes |
|------|--------|-------|
| Text | Full | String literals, string interpolation, .bold(), .italic() |
| Image(systemName:) | Full | SF Symbols, .resizable(), .scaledToFit/Fill() |
| Image("asset") | Full | Asset catalog |
| Button | Full | action: closure, trailing closure, @State mutations |
| VStack | Full | spacing, alignment |
| HStack | Full | spacing, alignment |
| ZStack | Full | alignment |
| ScrollView | Full | .horizontal/.vertical, showsIndicators |
| Spacer | Full | minLength |
| Divider | Full | |
| Circle | Full | .fill(), .stroke() |
| Rectangle | Full | .fill(), .stroke() |
| RoundedRectangle | Full | cornerRadius, .fill(), .stroke() |
| Capsule | Full | .fill() |
| ForEach (range) | Full | 0..<5 and 1...10 ranges, { index in } closure params |
| Color as View | Full | Color.blue.frame(...) renders as filled rectangle |

### Modifiers
| Modifier | Status |
|----------|--------|
| .font() | Full — all semantic styles + .system(size:weight:design:) |
| .fontWeight() | Full — all weights |
| .bold() | Full |
| .italic() | Full |
| .lineLimit() | Full |
| .multilineTextAlignment() | Full — leading, center, trailing |
| .foregroundColor() | Full — named colors + Color.xxx |
| .foregroundStyle() | Full — named colors |
| .padding() | Full — .all(n), .horizontal(n), .vertical(n), per-edge |
| .frame(width:height:) | Full — includes maxWidth/maxHeight with .infinity |
| .background() | Colors only |
| .cornerRadius() | Full |
| .clipShape() | Full — Circle, Rectangle, RoundedRectangle, Capsule |
| .clipped() | Full |
| .opacity() | Full |
| .shadow() | Full — radius, x, y |
| .overlay() | Full — view overlay |
| .border() | Full — color, width |
| .fixedSize() | Full |
| .aspectRatio() | Full — ratio, contentMode |
| .fill() | Full — shape color fill |
| .stroke() | Full — color, lineWidth |
| .resizable() | Full (on Image) |
| .scaledToFit() | Full |
| .scaledToFill() | Full |
| .offset(x:y:) | Full |
| .onTapGesture | Full — executes state action |
| .disabled() | Full |
| .hidden() | Full |
| .navigationTitle() | Full |

### Expressions & Control Flow
| Feature | Status |
|---------|--------|
| Ternary (a ? b : c) | Full — in expressions and modifier arguments |
| if/else views | Full — if { } else { }, else if chains |
| String interpolation | Full — resolves from live state |
| Binary ops (+,-,*,/,%,==,!=,<,>,&&,\|\|) | Full |
| Range operators (..<, ...) | Full |
| Compound assignment (+=,-=,*=,/=,=) | Full |
| .toggle() | Full — on boolean state variables |
| min(), max(), abs(), Int(), String() | Full |

### Colors
red, orange, yellow, green, blue, purple, pink, white, black, gray, clear, primary, secondary
Also: Color.xxx syntax (e.g., Color.blue)

### State & Interactivity
- @State var declarations with initial values (let and var)
- Reactive state via SwiftRunnerState + DynamicView
- Button taps execute actions and trigger re-render
- Struct/View body extraction from full Swift files
- #Preview block handling

---

## Not Yet Supported — Prioritized Roadmap

### P1 — Common (needed for typical tutorials)

1. **Ternary in modifier arguments at render time**
   `.foregroundColor(isActive ? .blue : .gray)` — ternary evaluates correctly but modifier extraction can't resolve dynamic colors at parse time. The modifier is silently dropped.

2. **Label view**
   `Label("Settings", systemImage: "gear")` — icon + text pair

3. **ProgressView**
   `ProgressView()`, `ProgressView(value: 0.5)`

4. **Color.opacity() method**
   `Color.gray.opacity(0.3)` — method on Color, not a modifier

5. **NavigationStack + NavigationLink**
   Navigation container and push navigation

6. **TextField + @State binding**
   `TextField("Name", text: $name)`

7. **Toggle + @State binding**
   `Toggle("Enable", isOn: $isOn)`

### P2 — Nice to Have

8. Picker with selection binding
9. List view with styled rows
10. Section with header/footer
11. Form view
12. .sheet(isPresented:) modal
13. .alert(isPresented:) dialogs
14. LinearGradient / RadialGradient
15. Custom RGB colors: Color(red:green:blue:)
16. .rotationEffect(), .scaleEffect()
17. .blur(radius:)
18. TabView with .tabItem
19. .animation(), .transition()
20. Custom struct views (multi-struct files)
