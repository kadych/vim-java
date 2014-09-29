" vim: set sw=2 sts=2 ts=2 et :
"
if exists('g:loaded_java')
  finish
endif
let g:loaded_java = 1

if !exists('g:mustache_directory')
  " ~/.vim/bundle/vim-java/mustaches
  let g:mustache_directory = expand(expand('<sfile>:p:h:h').'/mustaches')
endif

if !exists('g:java_max_imports')
  let g:java_max_imports = 4
endif

if !exists('g:java_source_set')
  let g:java_source_set = ['src/main/%f', 'src/test/%f']
endif

if !exists('g:java_file_types')
  let g:java_file_types = ['java', 'groovy']
endif

let s:package_pattern = '\vpackage\s+([^;]+);'
let s:import_pattern = '\v^import\s+(static\s+)?(\w+)(\..*);'
let s:class_pattern = '\v^(public\s+(class|interface|enum)\s+)([^ \t{]+)'

function! s:is_valid(fileType)
  return index(g:java_file_types, a:fileType) != -1
endfunction

function! java#get_package_name()
  let lnum = search(s:package_pattern, 'n')
  if lnum == 0
    return ''
  endif
  let groups = matchlist(getline(lnum), s:package_pattern)
  return groups[1]
endfunction

function! java#get_canonical_name()
  if !s:is_valid(&filetype)
    return ''
  endif
  let className = expand("%:t:r")
  let packageName = java#get_package_name()
  if packageName == ''
    return className
  endif
  return packageName.'.'.className
endfunction

function! java#split_canonical_name(canonicalName)
  if a:canonicalName ==# ''
    let names = ['']
  else
    let names = split(a:canonicalName, '\.')
  endif
  return {'className': names[-1], 'packageName': join(names[:-2], '.')}
endfunction

function! s:expand_source_path(sourcePath, fileType)
  return substitute(a:sourcePath, '%f', a:fileType, 'g')
endfunction

function! java#get_working_dir()
  let currentPath = expand('%:p:h')
  for fileType in g:java_file_types
    for sourcePath in g:java_source_set
      let pattern = escape('[\/]'.expand(s:expand_source_path(sourcePath, fileType)).'[\/]', '\\.')
      let npos = match(currentPath, '\v'.pattern)
      if npos != -1
        return currentPath[0:npos - 1]
      endif
    endfor
  endfor
  return getcwd()
endfunction

function! java#get_source_set(fileType)
  let workingDir = java#get_working_dir()
  let sourceSet = []
  for sourcePath in g:java_source_set
    let path = expand(workingDir.'/'.s:expand_source_path(sourcePath, a:fileType))
    if isdirectory(path)
      call add(sourceSet, path)
    endif
  endfor
  if empty(sourceSet)
    call add(sourceSet, '.')
  endif
  return sourceSet
endfunction

function! s:expand_name(sourcePath, canonicalName, fileType)
  return expand(a:sourcePath.'/'.substitute(a:canonicalName, '\v\.', '/', 'g').'.'.a:fileType)
endfunction

function! s:remove_test(sourcePath, isTest)
  let pattern = '\v[\\/]test'
  if a:isTest && a:sourcePath =~# pattern
    return a:sourcePath
  elseif !a:isTest && a:sourcePath !~# pattern
    return a:sourcePath
  else
    return ''
  endif
endfunction

function! s:unlet_empty_items(list)
  for i in reverse(range(len(a:list)))
    if empty(a:list[i])
      unlet a:list[i]
    endif
  endfor
  return a:list
endfunction

function! s:is_test(canonicalName)
  return a:canonicalName =~# '\v\.?Test[^\.]*$' || a:canonicalName =~# '\vTest$'
endfunction

function! java#get_source_file(canonicalName, fileType)
  let isTest = s:is_test(a:canonicalName)
  let sourceSet = s:unlet_empty_items(map(java#get_source_set(a:fileType), 's:remove_test(v:val, isTest)'))
  let sourceFiles = map(sourceSet, 's:expand_name(v:val, a:canonicalName, a:fileType)')
  if empty(sourceFiles)
    return ''
  endif
  return sourceFiles[0]
endfunction

function! java#get_canonical_name_ex(filePath)
  for sourcePath in java#get_source_set(a:filePath)
    let pattern = escape(expand(sourcePath.'/'), '\\.')
    let result = substitute(a:filePath, pattern, '', '')
    if result !=# a:filePath
      return substitute(fnamemodify(result, ':r'), '[\\/]', '.', 'g')
    endif
  endfor
  return fnamemodify(a:filePath, ':t:r')
endfunction

function! s:get_siblings(A, L, P)
  let fileType = tolower(split(a:L, ' ')[0])
  let sourceSet = java#get_source_set(fileType)

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
  
  let current = java#split_canonical_name(java#get_canonical_name())
  let fileList = split(globpath(join(sourceSet, ','), prefix.suffix), '\n')

  let classes = []
  let canonicalClasses = []
  for item in fileList
    for sourcePath in sourceSet
      let pattern = escape(expand(sourcePath.'/'), '\\.')
      let fileName = substitute(item, pattern, '', '')
      if item !=# fileName
        let canonicalName = substitute(fnamemodify(fileName, ':r'), '[\\/]', '.', 'g')
        let splitted = java#split_canonical_name(canonicalName)
        if splitted.className !=# current.className
          if splitted.packageName !=# current.packageName
            call add(canonicalClasses, canonicalName)
          elseif splitted.packageName ==# current.packageName
            call add(classes, splitted.className)
          endif
        endif
        break
      endif
    endfor
  endfor

  return sort(classes) + sort(canonicalClasses)
endfunction

function! java#render_template(scriptFile, outputFile, params)
  let inputFile = expand(g:mustache_directory.'/'.a:scriptFile)
  execute '!vim-tools vim.tools.MustacheGenerator'.
        \' -i '.shellescape(inputFile).
        \' -o '.shellescape(a:outputFile).
        \' '.shellescape(string(a:params))
  execute 'edit! '.a:outputFile
endfunction

function! java#template_params(className, fileType)
  let params = java#split_canonical_name(a:className)
  if params.packageName ==# '' && s:is_valid(&filetype)
    let params.packageName = java#get_package_name()
  endif

  let params.scriptName = a:fileType.'.mustache'

  if params.className =~# '^Test' || params.className =~# 'Test$'
    let params.isTest = 'yes'
  endif

  if params.packageName ==# ''
    let canonicalName = params.className
  else
    let canonicalName = params.packageName.'.'.params.className
  endif

  let params.fileName = java#get_source_file(canonicalName, a:fileType)

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

function! s:open_class(canonicalName, fileType)
  let params = java#template_params(a:canonicalName, a:fileType)
  if filereadable(params.fileName)
    let wnum = s:find_window(params.fileName)
    if wnum != -1
      execute wnum.'wincmd w'
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

function! java#java(canonicalName)
  call s:open_class(a:canonicalName, 'java')
endfunction

function! java#groovy(canonicalName)
  call s:open_class(a:canonicalName, 'groovy')
endfunction

function! java#toggle()
  if !s:is_valid(&filetype)
    return
  endif
  let canonicalName = java#get_canonical_name()
  let filePath = expand('%:p:h')
  if !s:is_test(canonicalName)
    let newCanonicalName = substitute(canonicalName, '\v([^\.]+)$', 'Test\1', '')
    let newFilePath = java#get_source_file(newCanonicalName, &filetype)
    if filereadable(newFilePath)
      execute 'edit! '.newFilePath
    else
      let newCanonicalName = substitute(canonicalName, '$', 'Test', '')
      let newFilePath = java#get_source_file(newCanonicalName, &filetype)
      call java#java(newCanonicalName)
    endif
  else
    if canonicalName =~# '\vTest$'
      let newCanonicalName = substitute(canonicalName, '\vTest$', '', '')
    elseif canonicalName =~# '\v\.?Test[^\.]*$'
      let newCanonicalName = substitute(canonicalName, '\v(\.)Test', '\1', '')
    endif
    call java#java(newCanonicalName)
  endif
endfunction

function! s:get_command_params(args)
  let args = a:args
  let className = ''
  let arr = split(args, ' ')
  if len(arr) > 0
    if arr[0] == '%'
      let className = java#get_canonical_name()
    else
      let className = arr[0]
    endif
    let args = join(arr[1:], ' ')
  endif
  return {'className': className, 'args': args}
endfunction

function! java#execute(...)
  if exists('g:java_execute')
    let params = s:get_command_params(a:1)
    call function(g:java_execute)(params.className, params.args)
  endif
endfunction

function! java#run(...)
  if exists('g:java_run')
    let params = s:get_command_params(a:1)
    call function(g:java_run)(params.className, params.args)
  endif
endfunction

function! java#test(...)
  if exists('g:java_test')
    let params = s:get_command_params(a:1)
    call function(g:java_test)(params.className, params.args)
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
    let item = java#split_canonical_name(groups[2])
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
  let fileDir = fnamemodify(a:newFileName, ':h')
  if !isdirectory(fileDir)
    call mkdir(fileDir, 'p')
  endif
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

function! s:fix_class_name(className)
  let lnum = search(s:class_pattern, 'n')
  if lnum == 0
    return
  endif
  let groups = matchlist(getline(lnum), s:class_pattern)
  execute lnum.',$s/\v\C<'.groups[3].'>/'.a:className.'/g'
endfunction

function! s:fix_package_name(packageName)
  let lnum = search(s:package_pattern, 'n')
  if lnum == 0
    if !empty(a:packageName)
      let stopline = search(s:class_pattern, 'n')
      let lnum = search(s:import_pattern, '', stopline)
      execute 'normal! Opackage '.a:packageName.";\<cr>"
    endif
  else
    if empty(a:packageName)
      execute lnum.'delete'
    else
      execute lnum.'s/'.s:package_pattern.'/package '.a:packageName.';/'
    endif
  endif
endfunction

function! java#rename(className)
  normal! mq
  normal! gg

  let splitted = java#split_canonical_name(a:className)
  if splitted.packageName ==# ''
    let splitted.packageName = java#get_package_name()
  endif

  if splitted.packageName ==# ''
    let canonicalName = splitted.className
  else
    let canonicalName = splitted.packageName.'.'.splitted.className
  endif

  let filePath = java#get_source_file(canonicalName, &filetype)
  if s:rename_file(filePath, '!')
    call s:fix_package_name(splitted.packageName)
    call s:fix_class_name(splitted.className)
    write
  endif

  silent! normal! `q
endfunction

function! java#maven_script(canonicalName)
  let splitted = java#split_canonical_name(a:canonicalName)
  if splitted.packageName ==# ''
    let splitted.packageName = java#get_package_name()
  endif
  let params = {'scriptName': 'pom.xml.mustache', 'fileName': 'pom.xml'}
  let params['groupId'] = splitted.packageName
  let params['artifactId'] = tolower(splitted.className)
  let params['className'] = a:canonicalName
  call java#render_template(params.scriptName, params.fileName, params)
endfunction

function! java#gradle_script(canonicalName)
  let splitted = java#split_canonical_name(a:canonicalName)
  if splitted.packageName ==# ''
    let splitted.packageName = java#get_package_name()
  endif
  let params = {'scriptName': 'build.gradle.mustache', 'fileName': 'build.gradle'}
  let params['groupId'] = splitted.packageName
  let params['artifactId'] = tolower(splitted.className)
  let params['className'] = a:canonicalName
  call java#render_template(params.scriptName, params.fileName, params)
endfunction

command! -nargs=1 -complete=customlist,s:get_siblings Java call java#java(<q-args>)
command! -nargs=1 -complete=customlist,s:get_siblings Groovy call java#groovy(<q-args>)
command! Jtoggle call java#toggle()
command! -nargs=* Jexecute call java#execute(<q-args>)
command! -nargs=* Jrun call java#run(<q-args>)
command! Jtest call java#test()
command! -nargs=* Jtest call java#test(<q-args>)
command! Jformat call java#format()
command! Jorganize call java#organize_imports()
command! -nargs=1 Jrename call java#rename(<q-args>)
command! -nargs=* -bang Rename call s:rename_file(<args>, <bang>)
command! -nargs=1 Maven call java#maven_script(<q-args>)
command! -nargs=1 Gradle call java#gradle_script(<q-args>)

augroup java
  autocmd FileType java nmap <buffer> <f7> :make<cr>
  autocmd FileType java nmap <buffer> <s-f8> :Jrun<cr>
  autocmd FileType java nmap <buffer> <m-f8> :Jtest<cr>
  autocmd FileType java nmap <buffer> <leader>jt :Jtoggle<cr>
  autocmd FileType java nmap <buffer> <leader>jr :Jexecute %<cr>
  autocmd FileType java nmap <buffer> <leader>jf :Jformat<cr>
  autocmd FileType java nmap <buffer> <leader>jo :Jorganize<cr>
  cabbrev java <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Java' : 'java'<cr>
  cabbrev groovy <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Groovy' : 'groovy'<cr>
  cabbrev rename <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Rename' : 'rename'<cr>
  autocmd FileType java cabbrev <buffer> rename <c-r>=getcmdpos() == 1 && getcmdtype() == ':' ? 'Jrename' : 'rename'<cr>
augroup END
