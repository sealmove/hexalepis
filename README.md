# hex
## Console hex editor. Modern, ergonomic &amp; intuitive!

&nbsp;

#### How to use
* Clone repository
```
git clone https://github.com/sealmove/hex.git
```
* [Install Nim](https://nim-lang.org/install.html)
```
#Windows:
Follow link's instructions

#Linux:
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```
* Compile
```
cd hex

nim c -o:hex main
```
* Run 
```
./hex <filename>
```

#### Key bindings

| Key | Action |
|----------------- | -------------------------
| ctrl+q | exit |
| ctrl+s | save (in-place) |
| u (or ctrl+z) | undo |
| esc | cancel |
| h, j, k, l (or arrows) | movement |
| home | go to beginning of line |
| end | go to end of line |
| pageup, pagedown  | vertical scroll |
| [ ] | horizontal scroll |
| tab | change panel |

#### Planning to add
- [ ] A status bar
- [ ] A key config system
- [ ] Insert/delete (needs a btree-like data structure for efficiency)
