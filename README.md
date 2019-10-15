# Hexalepis
## Hex editor made effecient

### Introduction
Hex editors need special optimizations (different from text editors) which are typically not implemented. This project was inspired by Simon Tatham's [article](https://www.chiark.greenend.org.uk/~sgtatham/tweak/btree.html) and is an effort to apply his ideas into a *real project*.

This means **hexalepis** also aims for:
* Featurefulness
    - Various radices
    - Highlighting
    - Parameterizable search
    - [Kaitai Struct](https://kaitai.io/) integration
    - Configurable keybindings
    - (...)
* User interface (TUI and GUI)
    - Responsive
    - Intuitive
    - Modern
* Platform
    - Linux
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

### Main goals
- [ ] Implement Simon Tatham's engine
- [ ] Make a [nimx](https://github.com/yglukhov/nimx) GUI edition
- [ ] ([Kaitai Struct](https://kaitai.io/)) support

### TUI goals
- [ ] Toggle ascii panel
- [ ] Mouse support
- [ ] Status bar
- [ ] Color themes (cycle at runtime)
- [ ] Keybinding configution system
- [x] Automatically-adjusting panel to fit console

### Installation
* [Install Nim](https://nim-lang.org/install.html)
* Clone
* Compile (`nim c -d:release -o:hexalepis main`) 
* Run `./hexalepis <filename>`

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