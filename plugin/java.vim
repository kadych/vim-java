" vim: set sw=2 sts=2 ts=2 et :

if exists('g:loaded_java')
  finish
endif
let g:loaded_java = 1

if has("win32")
  let g:file_separator = '\'
else
  let g:file_separator = '/'
endif

if !exists('g:vimfiles_directory')
  if has("win32")
    let g:vimfiles_directory = '~/vimfiles'
  else
    let g:vimfiles_directory = '~/.vim'
  endif
endif

let s:package_pattern = '\vpackage\s+([^;]+);'
let s:import_pattern = '\v^import\s+(static\s+)?(\w+)(\..*);'
let s:class_pattern = '\v^public\s+class\s+'
let g:java_max_imports = 3

function! java#get_class_name()
  let classname = substitute(expand("%:t"), '\.java$', '', '')
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

function! s:get_siblings(A, L, P)
  let filePath = expand('%:h')
  if filePath =~# '\v<main>'
    let altFilePath = substitute(filePath, '\v<main>', 'test', '')
  elseif filePath =~# '\v<test>'
    let altFilePath = substitute(filePath, '\v<test>', 'main', '')
  else
    let altFilePath = ''
  endif

  let list = []
  let list = list + globpath(filePath, a:A.'*.java', 0, 1)
  let list = list + globpath(altFilePath, a:A.'*.java', 0, 1)
  let classes = []
  for item in list
    let className = substitute(split(item, g:file_separator)[-1], '\.java$', '', '')
    call add(classes, className)
  endfor

  return classes
endfunction

function! java#render_template(scriptFile, outputFile, params)
  if !exists('g:mustache_directory')  
    let mustache_directory = g:vimfiles_directory.'/mustaches'
  else
    let mustache_directory = g:mustache_directory
  endif

  let inputFile = expand(mustache_directory.'/'.a:scriptFile)
  execute '!vim-tools vim.tools.MustacheGenerator'.
        \' -i '.shellescape(inputFile).
        \' -o '.shellescape(a:outputFile).
        \' '.shellescape(string(a:params))
  execute 'edit! '.a:outputFile
endfunction

function! java#template_params(cannonicalClassName)
  let params = java#split_class_name(a:cannonicalClassName)
  if params.packageName ==# '' && &filetype ==# 'java'
    let params.packageName = java#get_package_name()
  endif

  let params.scriptName = 'java.mustache'

  if params.className =~# '^Test' || params.className =~# 'Test$'
    let fileType = 'test'
    let params.isTest = 'yes'
  else
    let fileType = 'main'
  endif

  if &filetype ==# 'java'
    let pattern = '\v'.escape(
          \g:file_separator.'?'
          \.join(['src', '(main|test)', 'java'], g:file_separator)
          \.'('.g:file_separator.'.*)?', '\')
    let workingDir = substitute(expand('%:p:h'), pattern, '', '') 
  else
    let workingDir = getcwd()
  endif

  let targetDir = join(['src', fileType, 'java'] + split(params.packageName, '\.'), '/')
  if workingDir !=# ''
    let targetDir = workingDir.'/'.targetDir
  endif
  let params.fileName = expand(targetDir.'/'.params.className.'.java')

  return params
endfunction

function! java#java(cannonicalClassName)
  let params = java#template_params(a:cannonicalClassName)
  if filereadable(params.fileName)
    execute 'edit! '.params.fileName
  else
    if exists('g:user')
      let params.user = g:user
    endif
    call java#render_template(params.scriptName, params.fileName, params)
  endif
endfunction

function! java#toggle()
  if &filetype !=# 'java'
    return
  endif
  let className = java#get_class_name()
  let filePath = expand('%:p:h')
  if filePath =~# '\v<main>'
    let newClassName = substitute(className, '$', 'Test', '')
    let altClassName = substitute(className, '\v([^\.]+)$', 'Test\1', '')
    let newFilePath = java#template_params(newClassName).fileName
    let altFilePath = java#template_params(altClassName).fileName
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

function! java#organize_imports()
  let zones = split('javax?,org,com,\w+', ',')
  normal! mq
  normal! gg

  let stopLine = getline(search(s:class_pattern, 'n'))
  if stopLine ==# ''
    let stopLine = line('w$')
  endif

  let start = search(s:import_pattern, 'n')
  let finish = search(s:import_pattern, 'nb', stopLine)

  let imports = {}
  let staticImports = {}
  for i in range(start, finish)
    let groups = matchlist(getline(i), '\vimport\s+(static\s+)?([^ \t;]+)')
    let item = java#split_class_name(groups[2])
    if empty(groups[1]) 
      if has_key(imports, item.packageName)
        call add(imports[item.packageName], item.className)
      else
        let imports[item.packageName] = [item.className]
      endif
    else
      if has_key(staticImports, item.packageName)
        call add(staticImports[item.packageName], item.className)
      else
        let staticImports[item.packageName] = [item.className]
      endif
    endif
  endfor

  for packageName in keys(imports)
    let imports[packageName] = uniq(imports[packageName])
    if len(imports[packageName]) > g:java_max_imports || index(imports[packageName], '*') != -1
      let imports[packageName] = ['*']
    endif
  endfor

  for packageName in keys(staticImports)
    let staticImports[packageName] = uniq(staticImports[packageName])
    if len(staticImports[packageName]) > g:java_max_imports || index(staticImports[packageName], '*') != -1
      let staticImports[packageName] = ['*']
    endif
  endfor

  let newImports = []
  for packageName in sort(keys(imports))
    for className in imports[packageName]
      for i in range(len(zones))
        if packageName =~# '\v^'.zones[i]
          call add(newImports, i.packageName.'.'.className)
          break
        endif
      endfor
    endfor
  endfor

  let newStaticImports = []
  for packageName in sort(keys(staticImports))
    for className in staticImports[packageName]
      for i in range(len(zones))
        if packageName =~# '\v^'.zones[i]
          call add(newStaticImports, i.packageName.'.'.className)
          break
        endif
      endfor
    endfor
  endfor

  execute start.','.finish.'delete'
  for cannonicalClassName in sort(newImports)
    execute 'normal! iimport '.substitute(cannonicalClassName, '\v^\d', '', '').";\<cr>"
  endfor

  for cannonicalClassName in sort(newStaticImports)
    execute 'normal! iimport static '.substitute(cannonicalClassName, '\v^\d', '', '').";\<cr>"
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
  cabbrev rename <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Rename' : 'rename'<cr>
  autocmd FileType java cabbrev <buffer> rename <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Jrename' : 'rename'<cr>
augroup END
