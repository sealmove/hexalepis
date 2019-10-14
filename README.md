# hex
## Hex editor made effecient

### Introduction
Hex editors need special optimizations (different from text editors) which are typically not implemented. This project was inspired by Simon Tatham's [article](https://www.chiark.greenend.org.uk/~sgtatham/tweak/btree.html) and is an effort to apply his ideas into a *real project*.

This means **hex** also aims for:
* Featurefulness
    - Highlighting
    - Various radices
    - Parameterizable search
    - Configurable keybindings
    - [Kaitai Struct](https://kaitai.io/) integration
    - (...)
* User interface
    - Modern
    - Intuitive
    - Simple
* Platform
    - Linux (both TUI and GUI)
    - MacOS
    - Windows
    - Browsers

### Time effeciency
| Operation | Complexity |
|---------- | ---------- |
| Replace | O(1) |
| Copy-paste | O(1) |
| Insert | O(log(n)) |
| Delete | O(log(n)) |
| Seek | O(log(n)) |
| Search | O(n) |
| Save | O(n) |

### Space effeciency
The engine implements lazy file loading and copy-on-write; thus, memory usage is minimal (proportionally to changes).
Copy-paste is not an insertion operation! This means pasting the same block in multiple places does not increase memory usage proportionally to the block size. One could view this as a form of compression.

*Simon Tatham created [tweak](https://www.chiark.greenend.org.uk/~sgtatham/tweak/) which is more of a proof-of-concept rather than a full-fledged hex editor.*

### 5% [#....................]
This is **hex version 1**. It only runs on linux terminal emulators and the engine described above is not yet implemented.
**Hex version 2** will have the engine + a cross-platform GUI made with [nimx](https://github.com/yglukhov/nimx).

### Design goals
* Effeciency
* Simplicity
* Stability
* Featurefulness

### Installation
* Clone
* [Install Nim](https://nim-lang.org/install.html)
* Compile (`nim c -d:release -o:hex main`) 
* Run `./hex <filename>`

### Key bindings

| Key | Action |
|----------------- | ------------------------- |
| ctrl+q | exit |
| ctrl+s | save (in-place) |
| u (or ctrl+z) | undo |
| ctrl+r | redo |
| esc | cancel |
| h, j, k, l (or arrows) | movement |
| home | go to beginning of line |
| end | go to end of line |
| pageup, pagedown  | vertical scroll |
| [ ] | horizontal scroll |
| +, = | adjust width |
| tab | change panel |
| m (in hex panel) | mark byte |

### Version 1 plans
- [ ] Mouse support
- [ ] Status bar
- [ ] Color themes (cycle at runtime)
- [ ] Vertical line separators
- [ ] Toggle ascii panel
- [ ] .ksy support ([Kaitai Struct](https://kaitai.io/))
- [ ] Keybinding configution system
- [x] Redo
- [x] Mark (color a byte)
- [x] Adjustable panel width
- [x] Automatically-adjusting panel width (to fit screen)

### Version 2 plans
- [ ] Implement Simon Tatham's engine
- [ ] Make a nimx GUI edition