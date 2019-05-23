" Author: Ben Reedy <https://github.com/breed808>, Jeff Willette <jrwillette88@gmail.com>
" Description: Adds support for the gometalinter suite for Go files

call ale#Set('go_gometalinter_options', '')
call ale#Set('go_gometalinter_executable', 'gometalinter')
call ale#Set('go_gometalinter_lint_package', 0)

function! ale_linters#go#gometalinter#GetCommand(buffer) abort
    let l:options = ale#Var(a:buffer, 'go_gometalinter_options')
    let l:lint_package = ale#Var(a:buffer, 'go_gometalinter_lint_package')

    return '%e'
    \   . (l:lint_package ? ' --include=' . ale#Escape(ale#util#EscapePCRE(expand('#' . a:buffer . ':t'))) : '')
    \   . (!empty(l:options) ? ' ' . l:options : '') . ' .'
endfunction

function! ale_linters#go#gometalinter#GetMatches(lines) abort
    let l:pattern = '\v^([a-zA-Z]?:?[^:]+):(\d+):?(\d+)?:?:?(warning|error):?\s\*?(.+)$'

    return ale#util#GetMatches(a:lines, l:pattern)
endfunction

function! ale_linters#go#gometalinter#Handler(buffer, lines) abort
    let l:dir = expand('#' . a:buffer . ':p:h')
    let l:output = []

    for l:match in ale_linters#go#gometalinter#GetMatches(a:lines)
        " l:match[1] will already be an absolute path, output from gometalinter
        call add(l:output, {
        \   'filename': ale#path#GetAbsPath(l:dir, l:match[1]),
        \   'lnum': l:match[2] + 0,
        \   'col': l:match[3] + 0,
        \   'type': tolower(l:match[4]) is# 'warning' ? 'W' : 'E',
        \   'text': l:match[5],
        \})
    endfor

    return l:output
endfunction

call ale#linter#Define('go', {
\   'name': 'gometalinter',
\   'executable': {b -> ale#Var(b, 'go_gometalinter_executable')},
\   'cwd': function('ale#linter#GetBufferDirname'),
\   'command': function('ale_linters#go#gometalinter#GetCommand'),
\   'callback': 'ale_linters#go#gometalinter#Handler',
\   'lint_file': 1,
\})
