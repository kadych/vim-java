" vim: set sw=2 sts=2 ts=2 et :
"
if exists('g:loaded_java')
  finish
endif
let g:loaded_java = 1

if has("win32")
  let g:file_separator = '\'
else
  let g:file_separator = '/'
endif

if !exists('g:mustache_directory')
  let g:mustache_directory = expand(expand('<sfile>:p:h:h').'/mustaches')
endif

let g:java_max_imports = 3

let s:package_pattern = '\vpackage\s+([^;]+);'
let s:import_pattern = '\v^import\s+(static\s+)?(\w+)(\..*);'
let s:class_pattern = '\v^public\s+class\s+'
let s:file_types = ['java', 'groovy']

function! java#get_class_name()
  if index(s:file_types, &filetype) == -1
    return ''
  endif
  let classname = expand("%:t:r")
  let linenum = search(s:package_pattern, 'n')
  if linenum == 0
    return classname
  endif
  let line = getline(linenum)
  let groups = matchlist(line, s:package_pattern)
  return groups[1].'.'.classname
endfunction

function! java#get_package_name()
  let linenum = search(s:package_pattern)
  if linenum == 0
    return ''
  endif
  return substitute(getline(linenum), s:package_pattern, '\1', '')
endfunction

function! java#split_class_name(cannonicalClassName)
  let names = split(a:cannonicalClassName, '\.')
  return {'className': names[-1], 'packageName': join(names[:-2], '.')}
endfunction

function! s:get_working_dir()
  if index(s:file_types, &filetype) != -1
    let pattern = '\v'.escape(
          \g:file_separator.'?'
          \.join(['src', '(main|test)', '('.join(s:file_types, '|').')'], g:file_separator)
          \.'('.g:file_separator.'.*)?', '\')
    return substitute(expand('%:p:h'), pattern, '', '') 
  else
    return getcwd()
  endif
endfunction

function! s:get_source_set(fileType)
  let workingDir = s:get_working_dir()
  let sourceSet = []
  for item in ['src/main/'.a:fileType, 'src/test/'.a:fileType]
    let path = expand(workingDir.'/'.item)
    if isdirectory(path)
      call add(sourceSet, path)
    endif
  endfor
  if empty(sourceSet)
    call add(sourceSet, '.')
  endif
  return sourceSet
endfunction

function! s:get_siblings(A, L, P)
  let fileType = tolower(split(a:L, ' ')[0])
  let sourceSet = s:get_source_set(fileType)

  let suffix = '.'.fileType
  if a:A =~# '\v\.'
    let prefix = substitute(a:A, '\v\.', '/', 'g')
    if prefix =~# '\v/$'
      let prefix = prefix.'**/*'
    else
      let prefix = prefix.'*'
    endif
  else
    let prefix = '**/'.a:A.'*'
  endif
  
  let currentClassName = java#get_class_name()
  let packageName = java#get_package_name()
  let list = globpath(join(sourceSet, ','), prefix.suffix, 0, 1)

  let classes = []
  for item in list
    for sourcePath in sourceSet
      let fileName = substitute(item, '\v'.escape(sourcePath.g:file_separator, ' \-.'), '', '')
      if item !=# fileName
        let cannonicalClassName = substitute(
              \substitute(fileName, '\v'.escape(g:file_separator, '\'), '.', 'g'), 
              \'\v\.('.join(s:file_types, '|').')$', '', '')
        if currentClassName !=# cannonicalClassName
          let splitted = java#split_class_name(cannonicalClassName)
          call add(classes, packageName ==# splitted.packageName ? 
                \splitted.className : cannonicalClassName)
        endif
        break
      endif
    endfor
  endfor

  return classes
endfunction

function! java#render_template(scriptFile, outputFile, params)
  let inputFile = expand(g:mustache_directory.'/'.a:scriptFile)
  execute '!vim-tools vim.tools.MustacheGenerator'.
        \' -i '.shellescape(inputFile).
        \' -o '.shellescape(a:outputFile).
        \' '.shellescape(string(a:params))
  execute 'edit! '.a:outputFile
endfunction

function! java#template_params(cannonicalClassName, fileType)
  let params = java#split_class_name(a:cannonicalClassName)
  if params.packageName ==# '' && index(s:file_types, &filetype) != -1
    let params.packageName = java#get_package_name()
  endif

  let params.scriptName = a:fileType.'.mustache'

  if params.className =~# '^Test' || params.className =~# 'Test$'
    let sourceType = 'test'
    let params.isTest = 'yes'
  else
    let sourceType = 'main'
  endif

  let workingDir = s:get_working_dir()

  let targetDir = join(['src', sourceType, a:fileType] + split(params.packageName, '\.'), '/')
  if workingDir !=# ''
    let targetDir = workingDir.'/'.targetDir
  endif
  let params.fileName = expand(targetDir.'/'.params.className.'.'.a:fileType)

  return params
endfunction

function! s:find_window(fileName)
  for i in range(winnr('$'))
    if a:fileName ==# expand('#'.winbufnr(i + 1).':p')
      return i + 1
    endif
  endfor
  return -1
endfunction

function! s:open_class(fileType, cannonicalClassName)
  let params = java#template_params(a:cannonicalClassName, a:fileType)
  if filereadable(params.fileName)
    let winNum = s:find_window(params.fileName)
    if winNum != -1
      execute winNum.'wincmd w'
    else
      execute 'edit! '.params.fileName
    endif
  else
    if exists('g:user')
      let params.user = g:user
    endif
    call java#render_template(params.scriptName, params.fileName, params)
  endif
endfunction

function! java#java(cannonicalClassName)
  call s:open_class('java', a:cannonicalClassName)
endfunction

function! java#groovy(cannonicalClassName)
  call s:open_class('groovy', a:cannonicalClassName)
endfunction

function! java#toggle()
  if index(s:file_types, &filetype) == -1
    return
  endif
  let className = java#get_class_name()
  let filePath = expand('%:p:h')
  if filePath =~# '\v<main>'
    let newClassName = substitute(className, '$', 'Test', '')
    let altClassName = substitute(className, '\v([^\.]+)$', 'Test\1', '')
    let newFilePath = java#template_params(newClassName, &filetype).fileName
    let altFilePath = java#template_params(altClassName, &filetype).fileName
    if filereadable(altFilePath)
      execute 'edit! '.altFilePath
    else
      call java#java(newClassName)
    endif
  elseif filePath =~# '\v<test>'
    if className =~# '\vTest$'
      let newClassName = substitute(className, '\vTest$', '', '')
    elseif className =~# '\v(\.)Test'
      let newClassName = substitute(className, '\v(\.)Test', '\1', '')
    endif
    call java#java(newClassName)
  endif
endfunction

function! java#execute()
  if exists('g:java_execute')
    call function(g:java_execute)()
  endif
endfunction

function! java#run()
  if exists('g:java_run')
    call function(g:java_run)()
  endif
endfunction

function! java#test()
  if exists('g:java_test')
    call function(g:java_test)()
  endif
endfunction

function! java#format()
  let fileName = expand("%:p")
  execute '!vim-tools vim.tools.EclipseFormatter '.shellescape(fileName)
  execute 'edit! '.fileName
endfunction

function! s:remove_index(s)
  return substitute(a:s, '\v^\d+', '', '')
endfunction

function! s:sort_import_list(imports)
  let zones = split('javax?,org,com,\w+', ',')
  let result = []
  for packageName in keys(a:imports)
    if index(a:imports[packageName], '*') == -1
      " remove unnesessary class a:imports
      for i in reverse(range(len(a:imports[packageName])))
        let className = a:imports[packageName][i]
        if className !=# '*'
          if search('\v\C<'.className.'>', 'nW') == 0
            unlet a:imports[packageName][i]
          endif
        endif
      endfor
      " replace large import list with *
      if len(a:imports[packageName]) > g:java_max_imports
        let a:imports[packageName] = ['*']
      endif
    else
      let a:imports[packageName] = ['*']
    endif
    " sort import list by zones
    for className in a:imports[packageName]
      for i in range(len(zones))
        if packageName =~# '\v^'.zones[i]
          call add(result, i.packageName.'.'.className)
          break
        endif
      endfor
    endfor
  endfor
  return map(sort(result), 's:remove_index(v:val)')
endfunction

function! s:add_import_item(imports, item)
  if has_key(a:imports, a:item.packageName)
    call add(a:imports[a:item.packageName], a:item.className)
  else
    let a:imports[a:item.packageName] = [a:item.className]
  endif
endfunction

function! s:get_import_list(start, finish)
  let imports = {}
  let staticImports = {}
  for i in range(a:start, a:finish)
    let groups = matchlist(getline(i), '\vimport\s+(static\s+)?([^ \t;]+)')
    let item = java#split_class_name(groups[2])
    if empty(groups[1]) 
      call s:add_import_item(imports, item)
    else
      call s:add_import_item(staticImports, item)
    endif
  endfor
  return [imports, staticImports]
endfunction

function! java#organize_imports()
  normal! mq
  normal! gg

  let stopLine = getline(search(s:class_pattern, 'n'))
  if stopLine ==# ''
    let stopLine = line('w$')
  endif

  let start = search(s:import_pattern, 'n')
  let finish = search(s:import_pattern, 'nb', stopLine)
  let imports = s:get_import_list(start, finish)

  execute start.','.finish.'delete'

  for className in s:sort_import_list(imports[0])
    execute 'normal! iimport '.className.";\<cr>"
  endfor

  for className in s:sort_import_list(imports[1])
    execute 'normal! iimport static '.className.";\<cr>"
  endfor

  silent! normal! `q
endfunction

function! s:rename_file(newFileName, bang)
  let fileName = expand('%:p')
  let v:errmsg = ''
  silent! execute 'saveas'.a:bang.' '.fnameescape(a:newFileName)
	if v:errmsg =~# '^$\|^E329'
    if fileName !=# a:newFileName
      silent execute 'bwipe! '.fnameescape(fileName)
      if delete(fileName)
        echoerr 'Could not delete '.fileName
      else
        return 1
      endif
    endif
  else
    echoerr v:errmsg
  endif
  return 0
endfunction

function! java#rename(newClassName, bang)
  " let params = java#split_class_name(java#get_class_name())
  let newParams = java#split_class_name(a:newClassName)

  let filePath = expand('%:p:h')
  let newFileName = expand(filePath.'/'.newParams.className.'.java')
  if s:rename_file(newFileName, a:bang)
    let linepos = search(s:class_pattern, 'n')
    if linepos != 0
      execute linepos.'s/\v(public\s+class\s+)([^ \t]+)/\1'
            \.escape(newParams.className, '\.').'/'
      write
    endif
  endif
endfunction

command! -nargs=1 -complete=customlist,s:get_siblings Java call java#java(<q-args>)
command! -nargs=1 -complete=customlist,s:get_siblings Groovy call java#groovy(<q-args>)
command! Jtoggle call java#toggle()
command! Jexecute call java#execute()
command! Jrun call java#run()
command! Jtest call java#test()
command! Jformat call java#format()
command! Jorganize call java#organize_imports()
command! -nargs=* -bang Jrename call java#rename(<args>, <bang>)
command! -nargs=* -bang Rename call s:rename_file(<args>, <bang>)

augroup java
  autocmd FileType java nmap <buffer> <f7> :make<cr>
  autocmd FileType java nmap <buffer> <s-f8> :Jrun<cr>
  autocmd FileType java nmap <buffer> <m-f8> :Jtest<cr>
  autocmd FileType java nmap <buffer> <leader>jt :Jtoggle<cr>
  autocmd FileType java nmap <buffer> <leader>jr :Jexecute<cr>
  autocmd FileType java nmap <buffer> <leader>jf :Jformat<cr>
  autocmd FileType java nmap <buffer> <leader>jo :Jorganize<cr>
  cabbrev java <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Java' : 'java'<cr>
  cabbrev groovy <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Groovy' : 'groovy'<cr>
  cabbrev rename <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Rename' : 'rename'<cr>
  autocmd FileType java cabbrev <buffer> rename <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Jrename' : 'rename'<cr>
augroup END
