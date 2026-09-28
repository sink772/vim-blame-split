" autoload/blame_split.vim

" Number of age colors; BlameSplitAge0 is the newest.
let s:levels = 6
let s:commit_bufnr = -1

augroup BlameSplit
  autocmd!
augroup END

function! blame_split#toggle() abort
  if exists('b:blame_split_source')
    bwipeout
    return
  endif
  let bnr = get(b:, 'blame_split_bufnr', -1)
  if bufwinid(bnr) != -1
    execute 'bwipeout' bnr
    return
  endif
  call s:open()
endfunction

function! s:error(msg) abort
  echohl ErrorMsg
  echomsg 'BlameSplit: ' . a:msg
  echohl None
endfunction

function! s:open() abort
  let file = expand('%:p')
  if !empty(&buftype) || empty(file)
    return s:error('not a file buffer')
  endif
  let cmd = printf('git -C %s blame --line-porcelain --contents - -- %s',
        \ shellescape(fnamemodify(file, ':h')), shellescape(fnamemodify(file, ':t')))
  " Blame the buffer contents so unsaved edits stay line-aligned.
  " A List input gets no NL after its last item; add one as the file would have.
  let out = systemlist(cmd, getline(1, '$') + (&eol || &fixeol ? [''] : []))
  if v:shell_error
    return s:error(join(out, ' '))
  endif

  let entries = s:parse(out)
  " Age color on a log scale between the newest and oldest commit in the file,
  " so a 1-day vs 1-month difference is still visible next to a 2-year-old commit.
  let now = localtime()
  let ages = map(filter(copy(entries), '!v:val.uncommitted'), 's:logage(now, v:val.time)')
  " min()/max() do not accept Floats in Vim 8.2.
  let amin = empty(ages) ? 0.0 : sort(copy(ages), 'f')[0]
  let span = empty(ages) ? 1.0 : sort(copy(ages), 'f')[-1] - amin + 0.001
  let lines = map(copy(entries), 's:format(v:val)')

  let src_win = win_getid()
  let src_buf = bufnr('%')
  let view = winsaveview()
  " wrap and folds break line alignment under scrollbind.
  let saved = {'wrap': &l:wrap, 'foldenable': &l:foldenable,
        \ 'scrollbind': &l:scrollbind, 'cursorbind': &l:cursorbind}
  setlocal nowrap nofoldenable scrollbind cursorbind

  leftabove vertical new
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
  setlocal nonumber norelativenumber nowrap nofoldenable nolist
  setlocal foldcolumn=0 signcolumn=no winfixwidth cursorline
  call setline(1, lines)
  setlocal nomodifiable scrollbind cursorbind
  execute 'vertical resize' max(map(copy(lines), 'strdisplaywidth(v:val)') + [1]) + 1

  call s:define_highlights()
  let blame_buf = bufnr('%')
  for i in range(s:levels)
    call prop_type_add('BlameSplitAge' . i, {'bufnr': blame_buf, 'highlight': 'BlameSplitAge' . i})
  endfor
  call prop_type_add('BlameSplitUncommitted', {'bufnr': blame_buf, 'highlight': 'BlameSplitUncommitted'})
  for lnum in range(1, len(entries))
    let e = entries[lnum - 1]
    let type = e.uncommitted ? 'BlameSplitUncommitted'
          \ : 'BlameSplitAge' . float2nr((s:logage(now, e.time) - amin) * s:levels / span)
    call prop_add(lnum, 1, {'type': type, 'length': strlen(lines[lnum - 1]), 'bufnr': blame_buf})
  endfor

  let b:blame_split_source = src_buf
  let b:blame_split_dir = fnamemodify(file, ':h')
  let b:blame_split_hashes = map(copy(entries), 'v:val.hash')
  nnoremap <buffer> <silent> <CR> :<C-u>call <SID>show_commit()<CR>
  execute printf('autocmd BlameSplit BufWipeout <buffer> call s:restore(%d, %d, %s)', src_win, src_buf, string(saved))
  " Close blame before :q in the source, so quitting the last file window exits Vim.
  execute printf('autocmd BlameSplit QuitPre <buffer=%d> if win_getid() == %d | silent! bwipeout %d | endif',
        \ src_buf, src_win, blame_buf)
  " Wiping a buffer inside WinClosed aborts the close (E855), so defer it.
  execute printf('autocmd BlameSplit WinClosed %d ++once call timer_start(0, {-> execute("silent! bwipeout %d")})',
        \ src_win, blame_buf)
  call winrestview({'topline': view.topline, 'lnum': view.lnum})

  call win_gotoid(src_win)
  let b:blame_split_bufnr = blame_buf
  syncbind
endfunction

" Show the commit of the blame line under the cursor in a bottom split.
function! s:show_commit() abort
  let hash = get(b:blame_split_hashes, line('.') - 1, '')
  if empty(hash) || hash =~# '^0\+$'
    echo 'BlameSplit: not committed yet'
    return
  endif
  let out = systemlist(printf('git -C %s show --stat --patch %s', shellescape(b:blame_split_dir), hash))
  if v:shell_error
    return s:error(join(out, ' '))
  endif
  let winid = bufwinid(s:commit_bufnr)
  if winid != -1
    call win_gotoid(winid)
    setlocal modifiable
    silent %delete _
  else
    let blame_win = win_getid()
    let top = line('w0')
    botright new
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
    " Window options are inherited from the blame window; don't join its scroll binding.
    setlocal noscrollbind nocursorbind nowinfixwidth filetype=git
    nnoremap <buffer> <silent> q :bwipeout<CR>
    let s:commit_bufnr = bufnr('%')
    call s:sync(blame_win, top)
    execute printf('autocmd BlameSplit WinClosed %d ++once call timer_start(0, {-> s:sync(%d, 0)})',
          \ win_getid(), blame_win)
  endif
  call setline(1, out)
  setlocal nomodifiable
endfunction

" Resizing the blame window rescrolls it (or the source) on its own, since scrollbind does
" not sync on resize. Restore blame's topline (0: keep current), then align the source to it.
function! s:sync(blame_win, top) abort
  let cur = win_getid()
  if !win_gotoid(a:blame_win)
    return
  endif
  if a:top > 0
    call winrestview({'topline': a:top})
  endif
  " line('w0') scrolls the topline so the cursor is visible in the resized window.
  call winrestview({'topline': line('w0')})
  syncbind
  call win_gotoid(cur)
endfunction

function! s:restore(src_win, src_buf, saved) abort
  execute 'autocmd! BlameSplit WinClosed' a:src_win
  execute printf('autocmd! BlameSplit QuitPre <buffer=%d>', a:src_buf)
  let nr = win_id2win(a:src_win)
  if nr == 0
    return
  endif
  for [name, value] in items(a:saved)
    call setwinvar(nr, '&' . name, value)
  endfor
endfunction

" Parse `git blame --line-porcelain` output into one entry per line.
function! s:parse(out) abort
  let entries = []
  let cur = {}
  for l in a:out
    if l[0] ==# "\t"
      call add(entries, cur)
      let cur = {}
    elseif !has_key(cur, 'hash')
      let cur.hash = matchstr(l, '^\x\+')
      let cur.uncommitted = cur.hash =~# '^0\+$'
      let cur.author = ''
      let cur.time = 0
    elseif l =~# '^author '
      let cur.author = l[7:]
    elseif l =~# '^author-time '
      let cur.time = str2nr(l[12:])
    endif
  endfor
  return entries
endfunction

function! s:format(entry) abort
  if a:entry.uncommitted
    return 'Uncommitted'
  endif
  return printf('%-14s %s', s:reltime(a:entry.time), get(split(a:entry.author), 0, ''))
endfunction

function! s:logage(now, time) abort
  return log(max([a:now - a:time, 60]))
endfunction

function! s:reltime(time) abort
  let d = localtime() - a:time
  for [secs, unit] in [[31536000, 'year'], [2592000, 'month'], [604800, 'week'],
        \ [86400, 'day'], [3600, 'hour'], [60, 'minute']]
    if d >= secs
      let n = d / secs
      return printf('%d %s%s ago', n, unit, n == 1 ? '' : 's')
    endif
  endfor
  return 'just now'
endfunction

" Defined with `hi default` so users can override them in their vimrc.
function! s:define_highlights() abort
  if &background ==# 'light'
    let cterm = [166, 130, 94, 60, 245, 250]
    let gui = ['#d75f00', '#af5f00', '#875f00', '#5f5f87', '#8a8a8a', '#bcbcbc']
    let uncommitted = [160, '#d70000']
  else
    let cterm = [214, 179, 144, 109, 244, 240]
    let gui = ['#ffaf00', '#d7af5f', '#afaf87', '#87afaf', '#808080', '#585858']
    let uncommitted = [203, '#ff5f5f']
  endif
  for i in range(s:levels)
    execute printf('hi default BlameSplitAge%d ctermfg=%d guifg=%s', i, cterm[i], gui[i])
  endfor
  execute printf('hi default BlameSplitUncommitted ctermfg=%d guifg=%s', uncommitted[0], uncommitted[1])
endfunction
