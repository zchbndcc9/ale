" Author: Ben Reedy <https://github.com/breed808>
" Description: staticcheck for Go files

call ale#Set('go_staticcheck_options', '')
call ale#Set('go_staticcheck_lint_package', 0)

function! ale_linters#go#staticcheck#GetCommand(buffer) abort
    let l:lint_package = ale#Var(a:buffer, 'go_staticcheck_lint_package')

    return 'staticcheck'
    \   . ale#Pad(ale#Var(a:buffer, 'go_staticcheck_options'))
    \   . (l:lint_package ? '' : ' ' . ale#Escape(expand('#' . a:buffer . ':t')))
endfunction

call ale#linter#Define('go', {
\   'name': 'staticcheck',
\   'executable': 'staticcheck',
\   'cwd': function('ale#linter#GetBufferDirname'),
\   'command': function('ale_linters#go#staticcheck#GetCommand'),
\   'callback': 'ale#handlers#go#Handler',
\   'output_stream': 'both',
\   'lint_file': 1,
\})
