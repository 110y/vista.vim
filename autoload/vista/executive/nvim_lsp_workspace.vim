" Copyright (c) 2019 Alvaro Muñoz
" MIT License
" vim: ts=2 sw=2 sts=2 et

let s:provider = fnamemodify(expand('<sfile>'), ':t:r')

let g:vista_executive_nvim_lsp_reload_only = v:false
let g:vista_executive_nvim_lsp_should_display = v:false
let g:vista_executive_nvim_lsp_fetching = v:true

function! s:AutoUpdate(fpath) abort
  let g:vista_executive_nvim_lsp_reload_only = v:true
  let s:fpath = a:fpath
  call s:RunAsync()
endfunction

function! s:Run() abort
  if !has('nvim-0.5')
    return
  endif
  let g:vista_executive_nvim_lsp_fetching = v:true
  call s:RunAsync()
  while g:vista_executive_nvim_lsp_fetching
    sleep 100m
  endwhile
  return get(s:, 'data', {})
endfunction

function! vista#executive#nvim_lsp_workspace#SetData(data) abort
  let s:data = a:data
  " Update cache when new data comes.
  let s:cache = get(s:, 'cache', {})
  let s:cache[s:fpath] = s:data
  let s:cache.ftime = getftime(s:fpath)
  let s:cache.bufnr = bufnr('')
endfunction

function! s:RunAsync() abort
  if !has('nvim-0.5')
    return
  endif
  call vista#SetProvider(s:provider)
  lua << EOF
    local params = vim.lsp.util.make_position_params()
    local callback = function(err, method_or_result, result_or_context)
        -- signature for the handler changed in neovim 0.6/master. The block
        -- below allows users to check the compatibility.
        local result
        if type(method_or_result) == 'string' then
          -- neovim 0.5.x
          result = result_or_context
        else
          -- neovim 0.6+
          result = method_or_result
        end

        if err then print(tostring(err)) return end
        if not result then return end
        -- data = vim.fn['vista#renderer#LSPPreprocess'](result)
        data = vim.fn['vista#executive#nvim_lsp_workspace#Preprocess'](result)
        vim.fn['vista#executive#nvim_lsp_workspace#SetData'](data)
        vim.g.vista_executive_nvim_lsp_fetching = false
        if next(data) ~= nil then
          res = vim.fn['vista#renderer#LSPProcess'](data, vim.g.vista_executive_nvim_lsp_reload_only, vim.g.vista_executive_nvim_lsp_should_display)
          vim.g.vista_executive_nvim_lsp_reload_only = res[1]
          vim.g.vista_executive_nvim_lsp_should_display = res[2]
          vim.fn['vista#cursor#TryInitialRun']()
        end
    end

    local expand = vim.fn.expand('%:h')
    local pwd = os.getenv("PWD")
    local dir = (expand:sub(0, #pwd) == pwd) and expand:sub(#pwd+1) or expand

    local modfile = io.open("./go.mod", "r")
    local mod = ''
    if modfile ~= nil then
      io.close(modfile)

      local cmd = io.popen("go mod edit -json | jq -r .Module.Path | tr -d '\n'", "r")
      mod = cmd:read("*a")
    end

    local pkg = string.format('%s/%s', mod, dir)

    vim.g.vista_current_go_pkg = pkg

    local query = string.format('^%s', pkg)
    vim.lsp.buf_request(0, 'workspace/symbol', {query = query}, callback)
EOF
endfunction

function! vista#executive#nvim_lsp_workspace#Run(fpath) abort
  " TODO: check if the LSP service is registered for fpath.
  let s:fpath = a:fpath
  return s:Run()
endfunction

function! vista#executive#nvim_lsp_workspace#RunAsync() abort
  call s:RunAsync()
endfunction

function! vista#executive#nvim_lsp_workspace#Execute(bang, should_display, ...) abort
  call vista#source#Update(bufnr('%'), winnr(), expand('%'), expand('%:p'))
  let s:fpath = expand('%:p')

  call vista#OnExecute(s:provider, function('s:AutoUpdate'))

  let g:vista.silent = v:false
  let g:vista_executive_nvim_lsp_should_display = a:should_display

  if a:bang
    return s:Run()
  else
    call s:RunAsync()
  endif
endfunction

function! vista#executive#nvim_lsp_workspace#Cache() abort
  return get(s:, 'cache', {})
endfunction

function! vista#executive#nvim_lsp_workspace#Preprocess(lsp_result) abort
  let lines = []
  call map(a:lsp_result, 'vista#parser#lsp#KindToSymbol(v:val, lines)')

  let processed_data = {}
  let g:vista.functions = []
  call map(lines, 'vista#executive#nvim_lsp_workspace#ExtractSymbol(v:val, processed_data)')

  return processed_data
endfunction

function! vista#executive#nvim_lsp_workspace#ExtractSymbol(symbol, container) abort
  let symbol = a:symbol

  if vista#ShouldIgnore(symbol.kind)
    return
  endif

  let symbol.text = substitute(symbol.text, g:vista_current_go_pkg, '', '')

  if symbol.text[0] ==# '/'
    return
  endif

  let symbol.text = substitute(symbol.text, '^_test', '', '')
  let symbol.text = substitute(symbol.text, '^\.', '', '')

  if symbol.kind ==? 'Method' || symbol.kind ==? 'Function'
    call add(g:vista.functions, symbol)
  endif

  let picked = {'lnum': symbol.lnum, 'col': symbol.col, 'text': symbol.text}

  if has_key(symbol, 'path')
    let picked['path'] = symbol.path
  endif

  if has_key(a:container, symbol.kind)
    call add(a:container[symbol.kind], picked)
  else
    let a:container[symbol.kind] = [picked]
  endif
endfunction
