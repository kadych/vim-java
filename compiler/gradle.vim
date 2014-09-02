" vim: set sw=2 sts=2 ts=2 et :

if exists('current_compiler')
  finish
endif
let current_compiler = 'gradle'

if exists(":CompilerSet") != 2
  command -nargs=* CompilerSet setlocal <args>
endif

CompilerSet makeprg=gradle\ build
CompilerSet errorformat=
      \%W:compileJava%f:%l:\ warning:\ %m,
      \%W:compileTestJava%f:%l:\ warning:\ %m,
      \%W%f:%l:\ warning:\ %m,
      \%E:compileJava%f:%l:\ error:\ %m,
      \%E:compileTestJava%f:%l:\ error:\ %m,
      \%E%f:%l:\ error:\ %m,
      \%-C\ \ \ \ \ \ %.%#,
      \%C\ \ \ \ %m,
      \%C\ \ %m,
      \%Z%p^,
      \%-G%.%#,

function! gradle#execute()
  if !empty(matchstr(expand('%:h'), '\<main\>'))
    execute '!gradle -q run -DmainClass='.java#get_class_name()
  elseif !empty(matchstr(expand('%:h'), '\<test\>'))
    execute '!gradle -q test --tests '.java#get_class_name()
  endif
endfunction

function! gradle#run()
  execute '!gradle -q run'
endfunction

function! gradle#test()
  execute '!gradle -q test'
endfunction

let g:java_execute = 'gradle#execute'
let g:java_run = 'gradle#run'
let g:java_test = 'gradle#test'
