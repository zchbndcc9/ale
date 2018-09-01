" Author: Ben Reedy <https://github.com/breed808>, Jeff Willette <jrwillette88@gmail.com>
" Description: Adds support for the gometalinter suite for Go files

call ale#Set('go_golangcilint_options', '')
call ale#Set('go_golangcilint_executable', 'golangci-lint')

function! ale_linters#go#golangcilint#GetCommand(buffer) abort
    let l:filename = expand('#' . a:buffer . ':t')
    let l:options = ale#Var(a:buffer, 'go_golangcilint_options')

    return ale#path#BufferCdString(a:buffer)
    \   . 'golangci-lint run'
    \   . ' --out-format json'
    \   . (!empty(l:options) ? ' ' . l:options : '') . ' .'
endfunction

function! ale_linters#go#golangcilint#Handler(buffer, lines) abort
    let l:dir = expand('#' . a:buffer . ':p:h')

    let l:lines = type(a:lines) is v:t_list ? join(a:lines, "\n") : a:lines
    let l:j = json_decode(l:lines)
    if l:j is v:none
        " TODO: report error?
        return []
    endif

    let l:output = []
    for l:match in l:j["Issues"]
        call add(l:output, {
        \   'filename': ale#path#GetAbsPath(l:dir, l:match["Pos"]["Filename"]),
        \   'lnum': l:match["Pos"]["Line"],
        \   'col': l:match["Pos"]["Column"],
        \   'text': l:match["FromLinter"] . ': ' . l:match["Text"],
        \})
    endfor

    return l:output
endfunction

call ale#linter#Define('go', {
\   'name': 'golangcilint',
\   'executable_callback': ale#VarFunc('go_golangcilint_executable'),
\   'command_callback': 'ale_linters#go#golangcilint#GetCommand',
\   'callback': 'ale_linters#go#golangcilint#Handler',
\   'lint_file': 1,
\})
