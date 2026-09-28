# vim-blame-split

Vim 8.2+ (`+textprop`) plugin that opens `git blame` in a left split next to the current file.

```
2 years ago    Alice    | a
1 month ago    Bob      | B
1 day ago      Charlie  | C
Uncommitted             | D
```

- Relative commit time + author's first name per line
- Colors graded from newest to oldest commit in the file (log scale)
- Blames the buffer contents, so unsaved edits show as `Uncommitted`
- Both windows scroll and move the cursor together

## Install

```sh
mkdir -p ~/.vim/pack/plugins/start
ln -s ~/work/vim-blame-split ~/.vim/pack/plugins/start/vim-blame-split
```

## Usage

- `:BlameSplit` or `<leader>gb` toggles the blame window (works from either window).
- `<CR>` on a blame line shows its commit (`git show`) in a bottom split; `q` closes it.
- Re-toggle to refresh after edits that add or remove lines.
- `:q` in the source window closes the blame window too.
- While open, `wrap` and folds are disabled in the source window and restored on close.

Custom mapping:

```vim
let g:blame_split_no_mappings = 1
nmap <F8> <Plug>(blame-split)
```

## Colors

`BlameSplitAge0` (newest) to `BlameSplitAge5` (oldest), and `BlameSplitUncommitted`. They are defined with
`hi default`, so override them in your vimrc:

```vim
hi BlameSplitAge0 ctermfg=46 guifg=#00ff00
```
