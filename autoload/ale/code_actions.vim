" Author: w0rp <devw0rp@gmail.com>
" Description: Get and run code actions for language servers.

let s:code_actions_map = {}

" Used to get the map in tests.
function! ale#code_actions#GetMap() abort
    return deepcopy(s:code_actions_map)
endfunction

" Used to set the map in tests.
function! ale#code_actions#SetMap(map) abort
    let s:code_actions_map = a:map
endfunction

function! ale#code_actions#ClearLSPData() abort
    let s:code_actions_map = {}
endfunction

function! s:EscapeMenuName(text) abort
    return substitute(a:text, '\\\| \|\.\|&', '\\\0', 'g')
endfunction

function! ale#code_actions#ApplyChanges(filename, changes) abort
    " The buffer is used to determine the fileformat, if available.
    let l:buffer = bufnr(a:filename)

    if l:buffer >= 0
        let l:lines = getbufline(l:buffer, 1, '$')
    else
        let l:lines = readfile(a:filename, 'b')

        " Remove the newline at the end if it exists, we'll add it back in again.
        if l:lines[-1] is# ''
            let l:lines = l:lines[:-2]
        endif
    endif

    " We have to keep track of how many lines we have added, and offset
    " changes accordingly.
    let l:line_offset = 0
    let l:column_offset = 0
    let l:last_end_line = 0

    for [l:line, l:column, l:end_line, l:end_column, l:text] in a:changes
        if l:line isnot l:last_end_line
            let l:column_offset = 0
        endif

        let l:last_end_line = l:end_line

        " Adjust the ends according to previous edits.
        let l:line += l:line_offset
        let l:end_line += l:line_offset
        let l:column += l:column_offset
        let l:end_column += l:column_offset
        let l:end_line_len = len(l:lines[l:end_line - 1])

        let l:insertions = split(l:text, '\n', 1)
        let l:line_offset += len(l:insertions) - 1

        let l:column_offset = len(l:insertions[0]) - (l:end_column - l:column)

        if l:column is 1
            " We need to handle column 1 specially, because we can't slice an
            " empty string ending on index 0.
            let l:middle = [l:insertions[0]]
        else
            let l:middle = [l:lines[l:line - 1][: l:column - 2] . l:insertions[0]]
        endif

        call extend(l:middle, l:insertions[1:])
        let l:middle[-1] .= l:lines[l:end_line - 1][l:end_column - 1 :]

        let l:lines = l:lines[: l:line - 2]
        \   + l:middle
        \   + l:lines[l:end_line :]

        let l:column_offset = len(l:lines[l:end_line - 1]) - l:end_line_len
    endfor

    call ale#util#Writefile(l:buffer, l:lines, a:filename)

    if l:buffer is bufnr('')
        :e!
    endif
endfunction

function! ale#code_actions#ApplyRename(old_name, locations) abort
    let l:new_name = input('New name: ', a:old_name)

    for [l:filename, l:spans] in a:locations
        call ale#code_actions#ApplyChanges(
        \   l:filename,
        \   map(copy(l:spans), 'v:val + [l:new_name]'),
        \)
    endfor
endfunction

function! ale#code_actions#Execute(conn_id, location, linter_name, id) abort
    if a:linter_name is# 'tsserver'
        let [l:refactor, l:action] = a:id

        let l:message = ale#lsp#tsserver_message#GetEditsForRefactor(
        \   a:location.buffer,
        \   a:location.line,
        \   a:location.column,
        \   a:location.end_line,
        \   a:location.end_column,
        \   l:refactor,
        \   l:action,
        \)

        let l:request_id = ale#lsp#Send(a:conn_id, l:message)

        let s:code_actions_map[l:request_id] = {}
    endif
endfunction

function! s:UpdateMenu(conn_id, location, linter_name, menu_items) abort
    silent! aunmenu PopUp.Refactor\.\.\.

    for l:item in a:menu_items
        execute printf(
        \   'anoremenu <silent> PopUp.&Refactor\.\.\..%s'
        \       . ' :call ale#code_actions#Execute(%s, %s, %s, %s)<CR>',
        \   join(map(copy(l:item.names), 's:EscapeMenuName(v:val)'), '.'),
        \   string(a:conn_id),
        \   string(a:location),
        \   string(a:linter_name),
        \   string(l:item.id)
        \)
    endfor
endfunction

function! s:HandleGetApplicableRefactors(response, details) abort
    let l:conn_id = a:details.connection_id
    let l:location = a:details.location
    let l:linter_name = a:details.linter_name
    let l:menu_items = []

    if get(a:response, 'success', v:false) is v:true
    \&& !empty(get(a:response, 'body'))
        for l:item in a:response.body
            for l:action in l:item.actions
                " Actions for inlineable items can top level items.
                call add(l:menu_items, {
                \   'names': get(l:item, 'inlineable')
                \       ? [l:item.description, l:action.description]
                \       : [l:action.description],
                \   'id': [l:item.name, l:action.name],
                \})
            endfor
        endfor
    endif

    call s:UpdateMenu(l:conn_id, l:location, l:linter_name, l:menu_items)
endfunction

function! s:HandleRename(response, details) abort
    if get(a:response, 'success', v:false) is v:true
    \&& !empty(get(a:response, 'body'))
    \&& a:response.body.info.canRename
        silent! aunmenu PopUp.Rename

        let l:locations = []

        for l:filename_item in a:response.body.locs
            let l:spans = []

            for l:item in l:filename_item.locs
                call add(l:spans, [
                \   l:item.start.line,
                \   l:item.start.offset,
                \   l:item.end.line,
                \   l:item.end.offset,
                \])
            endfor

            call add(l:locations, [l:filename_item.file, l:spans])
        endfor

        execute printf(
        \   'anoremenu <silent> PopUp.Rename'
        \       . ' :call ale#code_actions#ApplyRename(%s, %s)<CR>',
        \   string(a:response.body.info.displayName),
        \   string(l:locations),
        \)
    endif
endfunction

function! s:HandleGetEditsForRefactor(response, details) abort
    if get(a:response, 'success', v:false) is v:true
    \&& !empty(get(a:response, 'body'))
        " Could be set for a location: a:response.renameLocation
        for l:item in a:response.body.edits
            let l:changes = map(copy(l:item.textChanges), {_, edit -> [
            \   edit.start.line,
            \   edit.start.offset,
            \   edit.end.line,
            \   edit.end.offset,
            \   edit.newText,
            \]})

            call ale#code_actions#ApplyChanges(l:item.fileName, l:changes)
        endfor
    endif
endfunction

function! ale#code_actions#HandleTSServerResponse(conn_id, response) abort
    if has_key(a:response, 'request_seq')
    \&& has_key(s:code_actions_map, a:response.request_seq)
        let l:details = remove(s:code_actions_map, a:response.request_seq)
        let l:command = get(a:response, 'command', '')

        if l:command is# 'getApplicableRefactors'
            call s:HandleGetApplicableRefactors(a:response, l:details)
        elseif l:command is# 'rename'
            call s:HandleRename(a:response, l:details)
        elseif l:command is# 'getEditsForRefactor'
            call s:HandleGetEditsForRefactor(a:response, l:details)
        endif
    endif
endfunction

function! ale#code_actions#HandleLSPResponse(conn_id, response) abort
    Dump a:response
endfunction

function! s:OnReady(location, options, linter, lsp_details) abort
    let l:id = a:lsp_details.connection_id

    if !ale#lsp#HasCapability(l:id, 'code_actions')
        return
    endif

    let l:buffer = a:lsp_details.buffer

    let l:Callback = a:linter.lsp is# 'tsserver'
    \   ? function('ale#code_actions#HandleTSServerResponse')
    \   : function('ale#code_actions#HandleLSPResponse')
    call ale#lsp#RegisterCallback(l:id, l:Callback)

    let l:request_id_list = []

    if a:linter.lsp is# 'tsserver'
        let l:message = ale#lsp#tsserver_message#GetApplicableRefactors(
        \   a:location.buffer,
        \   a:location.line,
        \   a:location.column,
        \   a:location.end_line,
        \   a:location.end_column,
        \)

        call add(l:request_id_list, ale#lsp#Send(l:id, l:message))

        let l:message = ale#lsp#tsserver_message#Rename(
        \   a:location.buffer,
        \   a:location.line,
        \   a:location.column,
        \)

        call add(l:request_id_list, ale#lsp#Send(l:id, l:message))
    else
        " Send a message saying the buffer has changed first, or the
        " definition position probably won't make sense.
        call ale#lsp#NotifyForChanges(l:id, l:buffer)

        let l:message = ale#lsp#message#CodeAction(
        \   a:location.buffer,
        \   a:location.line,
        \   a:location.column,
        \   a:location.end_line,
        \   a:location.end_column,
        \)

        call add(l:request_id_list, ale#lsp#Send(l:id, l:message))
    endif

    for l:request_id in l:request_id_list
        let s:code_actions_map[l:request_id] = {
        \   'connection_id': l:id,
        \   'location': a:location,
        \   'linter_name': a:linter.name,
        \}
    endfor
endfunction

function! s:GetCodeActions(linter, options) abort
    let l:buffer = bufnr('')
    let [l:line, l:column] = getpos('.')[1:2]
    let l:column = min([l:column, len(getline(l:line))])

    let l:location = {
    \   'buffer': l:buffer,
    \   'line': l:line,
    \   'column': l:column,
    \   'end_line': l:line,
    \   'end_column': l:column,
    \}
    let l:Callback = function('s:OnReady', [l:location, a:options])
    call ale#lsp_linter#StartLSP(l:buffer, a:linter, l:Callback)
endfunction

function! ale#code_actions#GetCodeActions(options) abort
    silent! aunmenu PopUp.Refactor\.\.\.
    silent! aunmenu PopUp.Rename

    for l:linter in ale#linter#Get(&filetype)
        if !empty(l:linter.lsp)
            call s:GetCodeActions(l:linter, a:options)
        endif
    endfor
endfunction

function! s:Setup(enabled) abort
    augroup ALECodeActionsGroup
        autocmd!

        if a:enabled
            autocmd MenuPopup * :call ale#code_actions#GetCodeActions({})
        endif
    augroup END

    if !a:enabled
        augroup! ALECompletionGroup
    endif
endfunction

function! ale#code_actions#Enable() abort
    let g:ale_code_actions_enabled = 1
    call s:Setup(1)
endfunction

function! ale#code_actions#Disable() abort
    let g:ale_code_actions_enabled = 0
    call s:Setup(0)
endfunction
