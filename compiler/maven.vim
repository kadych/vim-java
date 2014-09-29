" vim: set sw=2 sts=2 ts=2 et :

if exists('current_compiler')
  finish
endif
let current_compiler = 'maven'

if exists(":CompilerSet") != 2
  command -nargs=* CompilerSet setlocal <args>
endif

CompilerSet makeprg=mvn\ -B
CompilerSet errorformat=
      \%E[ERROR]\ %f:[%l\\,%v]\ error:\ %m,
      \%W[WARNING]\ %f:[%l\\,%v]\ %m,%Z[WARNING]\ %m,
      " \%IRunning\ %m,%ZTests\ run:\ %m,
      \%I%m\ \ Time\ elapsed:\ %*\\d.%*\\d\ sec\ \ <<<\ FAILURE!,%Z%.%#:\ %m,
      \%-G%.%#,

function! maven#execute(className, args)
  if !empty(matchstr(expand('%:h'), '\<main\>'))
    call maven#run(a:className, a:args)
  elseif !empty(matchstr(expand('%:h'), '\<test\>'))
    call maven#test(a:className, a:args)
  endif
endfunction

function! maven#run(className, args)
  let mainClass = a:className != '' ? ' -Dexec.mainClass='.a:className : ''
  let args = a:args != '' ? ' -Dexec.args="'.escape(a:args, '"').'"' : ''
  execute 'make -q compile exec:java'.mainClass.args
endfunction

function! maven#test(className, args)
  let mainClass = a:className != '' ? ' -Dtest='.a:className : ''
  execute 'make -q test'.mainClass
endfunction

let g:java_execute = 'maven#execute'
let g:java_run = 'maven#run'
let g:java_test = 'maven#test'
