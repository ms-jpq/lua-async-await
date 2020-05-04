if exists('g:nvim_tut_loaded')
  finish
endif

command! LuaSyncExample  lua require "tutorial".sync_example()
command! LuaAsyncExample lua require "tutorial".async_example()()
command! LuaTextlockFail lua require "tutorial".textlock_fail()()
command! LuaTextLockSucc lua require "tutorial".textlock_succ()()

let g:nvim_tut_loaded = 1

