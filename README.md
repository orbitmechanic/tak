# Tak

A two-player digital implementation of [Tak](https://en.wikipedia.org/wiki/Tak_(fictional_game)), the abstract strategy board game from Patrick Rothfuss's *The Kingkiller Chronicle*, built with **Godot 4.7** (pure GDScript, no external assets).

![Tak game board](docs/screenshot.png)

## Rules implemented (5x5)

- Each player: 21 flat stones + 1 capstone
- Opening moves: each player places one of the *opponent's* flats
- Place or move per turn; stack carry limit of 5 with mandatory drop in every cell entered
- No piece can be moved onto a wall, so walls are only ever the *top* of a tower, never buried inside one; a wall-topped cell can only be entered by a lone capstone, which flattens the wall (it stays the original owner's, now a flat) and rests on top of it
- Capstones block stacking entirely: **nothing may be moved onto or passed over a capstone** (it can never be buried), and nothing may be stacked on a capstone — which is why each player gets exactly one; a capstone always remains a visible road piece while it is the top of its cell
- **Tower toppling** (the novel's rule): instead of carrying, any tower whose top piece is yours (any height ≥ 2, any top piece type) may be felled in a straight line — one stone per cell, bottom-to-top — in any direction that has enough room on the board; a direction is blocked if any landing cell is off-board, wall-topped, or would need a falling wall to land on stones
- Win by road: an orthogonally connected chain of your flats/capstones (top pieces only) joining **any two opposite edges of the board** — either pair counts for either player; if the game ends by board fill / no legal moves, winner is by count of top flats
- Diagonals are meaningless, per the book

## Running

Install Godot 4.7 (or later 4.x), then:

```bash
godot --path .
```

## Controls

- Click an empty square to place; **F / W / C** (or the Place Tool buttons) select flat / wall / capstone
- Click one of your stacks → **click any cell of a highlighted TOPPLE ray** (blue cells, orange-capped) to fell the tower that way, bottom-to-top; or press a **direction** button (or arrow key) first and then a green **destination** to make a carry-move instead
- **Undo** (or Ctrl+Z), **New Game**, and a **Human vs Bot / Hotseat** switch live in the top bar
- A lone capstone moving onto a wall toppling it is hinted with `TOPPLE`

## The AI opponent

`scripts/mcts_bot.gd` is a UCT Monte Carlo Tree Search player:

- Time-budgeted (2 s default), executed in small chunks per frame so the UI never freezes
- Fast random-rollout policy backed by a cheap move sampler and bitmask road detection in the engine (`scripts/tak_state.gd`)
- Roughly 500–1,200 playouts per move on a laptop — a solid casual opponent

## Tests

A headless rules/AI suite lives in `Probe.gd`:

```bash
godot --headless --path . --import
godot --headless --path . -s res://Probe.gd   # 30 tests
```

## Project layout

| File | Purpose |
|---|---|
| `scripts/tak_state.gd` | Rules engine: move generation/validation, roads, endgame |
| `scripts/mcts_bot.gd` | UCT MCTS player |
| `scripts/main.gd` | UI scene logic (board rendering, input, turn flow) |
| `scenes/Main.tscn` | Main scene |
| `Probe.gd` | Headless test suite |

## Note

Tak is a game devised by Patrick Rothfuss and developed for publication by James Ernest / Cheapass Games. This is an unofficial, from-the-rules fan implementation; no game components or trademarks are included.

## License

MIT — see [LICENSE](LICENSE).
