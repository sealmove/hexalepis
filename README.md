# hex
## Hex editor made effecient &amp; intuitive

### Introduction
This project was inspired by Simon Tatham's [article](https://www.chiark.greenend.org.uk/~sgtatham/tweak/btree.html) and is an effort to apply his ideas into a real project.
*Simon Tatham created [tweak](https://www.chiark.greenend.org.uk/~sgtatham/tweak/) which is sadly just a proof-of-concept project rather than a full-fledged hex editor.*

#### [Article](https://www.chiark.greenend.org.uk/~sgtatham/tweak/btree.html) summary
Text editors are optimized based on common text operations (per line editing, etc). While editing hex values, a very different set of operations becomes common; thus, hex editors need special data structures and algorithms for achieving comparable effeciency.

### Platform
Currently *hex* only runs on linux terminal emulators, but there are plans for making a GUI version with [nimx](https://github.com/yglukhov/nimx).

### Design goals
* Effeciency
* Simplicity
* Stability
* Featurefulness

#### How to use
* Clone
* [Install Nim](https://nim-lang.org/install.html)
* Compile (`nim c -d:release -o:hex main`) 
* Run `./hex <filename>`

#### Key bindings

| Key | Action |
|----------------- | -------------------------
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

#### Planning to add
- [ ] Mouse support
- [ ] Status bar
- [ ] Insert/delete (needs a btree-like data structure for effeciency)
- [ ] Color themes (cycle at runtime)
- [ ] Vertical line separators
- [ ] Toggle ascii panel
- [ ] .ksy support ([Kaitai Struct](https://kaitai.io/))
- [ ] Keybinding configution system
- [x] Redo
- [x] Mark (color a byte)
- [x] Adjustable panel width
- [x] Automatically-adjusting panel width (to fit screen)