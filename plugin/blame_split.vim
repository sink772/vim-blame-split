" blame_split.vim - show git blame in a left split
if exists('g:loaded_blame_split')
  finish
endif
let g:loaded_blame_split = 1

command! BlameSplit call blame_split#toggle()

nnoremap <silent> <Plug>(blame-split) :<C-u>call blame_split#toggle()<CR>
if !get(g:, 'blame_split_no_mappings', 0) && !hasmapto('<Plug>(blame-split)', 'n')
  nmap <leader>gb <Plug>(blame-split)
endif
