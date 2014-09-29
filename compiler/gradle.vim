" vim: set sw=2 sts=2 ts=2 et :

if exists('current_compiler')
  finish
endif
let current_compiler = 'gradle'

if exists(":CompilerSet") != 2
  command -nargs=* CompilerSet setlocal <args>
endif

CompilerSet makeprg=gradle\ -q
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

function! gradle#execute(className, args)
  if !empty(matchstr(expand('%:h'), '\<main\>'))
    call gradle#run(a:className, a:args)
  elseif !empty(matchstr(expand('%:h'), '\<test\>'))
    call gradle#test(a:className, a:args)
  endif
endfunction

function! gradle#run(className, args)
  let mainClass = a:className != '' ? ' -DmainClass='.a:className : ''
  let args = a:args != '' ? ' -Pargs="'.escape(a:args, '"').'"' : ''
  execute 'make run'.mainClass.args
endfunction

function! gradle#test(className, args)
  let mainClass = a:className != '' ? ' --tests '.a:className : ''
  execute 'make test'.mainClass
endfunction

let g:java_execute = 'gradle#execute'
let g:java_run = 'gradle#run'
let g:java_test = 'gradle#test'
