# hex
## Console hex editor. Modern, ergonomic &amp; intuitive!

&nbsp;

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
| tab | change panel |
| m (in hex panel) | mark byte |

#### Planning to add
- [x] Redo
- [ ] Mark (color a byte manually)
- [ ] A status bar
- [ ] Insert/delete (needs a btree-like data structure for effeciently)
- [ ] Color themes (cycle at runtime)
- [ ] Vertical line separators
- [ ] Toggle ascii panel
- [ ] Adjustable number of columns
- [ ] Adjust number of columns and/or toggle ascii panel if too small to fit
- [ ] A keybinding configution system
