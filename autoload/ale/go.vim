" Author: Horacio Sanson https://github.com/hsanson
" Description: Functions for integrating with Go tools

" Attempt to find the root for this project.
function! ale#go#FindProjectRoot(buffer) abort
    " Vendoring tools: good bet this is the root.
    for l:f in ['go.mod', 'Gopkg.toml', 'glide.yaml']
        let l:f = ale#path#FindNearestFile(a:buffer, l:f)

        if l:f isnot# ''
            return fnamemodify(l:f, ':h')
        endif
    endfor

    " vendor directory or VCS dir is also reasonably safe.
    for l:d in ['vendor', '.git', '.hg']
        let l:d = ale#path#FindNearestDirectory(a:buffer, 'vendor')

        if l:d isnot# ''
            return l:d
        endif
    endfor

    " Better than nothing, I guess?
    for l:f in ['doc.go', 'README.md']
        let l:f = ale#path#FindNearestFile(a:buffer, l:f)

        if l:f isnot# ''
            return fnamemodify(l:f, ':h')
        endif
    endfor

    return ''
endfunction
