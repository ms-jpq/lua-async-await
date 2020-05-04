local a = require "async"
local co = coroutine
local uv = vim.loop


--#################### ########### ####################
--#################### Sync Region ####################
--#################### ########### ####################


-- sync version of pong
local pong = function (thread)
  local nxt = nil
  nxt = function (cont, ...)
    if not cont
      then return ...
      else return nxt(co.resume(thread), ...)
    end
  end
  return nxt(co.resume(thread))
end


local sync_example = function ()

  local thread = co.create(function ()
    local x = co.yield(1)
    print(x)
    local y, z = co.yield(2, 3)
    print(y)
    return 4, 5
  end)

  local w, t = pong(thread)
  print(w, t)
end


--#################### ############ ####################
--#################### Async Region ####################
--#################### ############ ####################


local timeout = function (ms, callback)
  local timer = assert(uv.new_timer())
  uv.timer_start(timer, ms, 0, function ()
    assert(uv.timer_stop(timer))
    assert(uv.close(timer))
    callback()
  end)
end


-- typical nodejs / luv function
local echo_2 = function (msg1, msg2, callback)
  -- wait 200ms
  timeout(200, function ()
    callback(msg1, msg2)
  end)
end


-- thunkify echo_2
local e2 = a.wrap(echo_2)


local async_tasks_1 = a.sync(function ()
  local x, y = a.wait(e2(1, 2))
  print(x, y)
  return x + y
end)


local async_tasks_2 = function (val)
  return a.sync(function ()
    -- await all
    local w, z = a.wait_all{e2(val, val + 1), e2(val + 2, val + 3)}
    print(unpack(w), unpack(z))
    return 5
  end)
end


local async_example = a.sync(function ()
  -- composable, await other async thunks
  local u = a.wait(async_tasks_1)
  local v = a.wait(async_tasks_2(3))
  print(u + v)
end)


--#################### ############ ####################
--#################### Loops Region ####################
--#################### ############ ####################


-- avoid textlock
local main_loop = function (f)
  vim.schedule(f)
end


local vim_command = function ()
end


local textlock_fail = a.sync(function ()
  a.wait(e2(1, 2))
  vim_command()
end)


local textlock_succ = a.sync(function ()
  a.wait(e2(1, 2))
  a.wait(main_loop)
  vim_command()
end)


return {
  sync_example = sync_example,
  async_example = async_example,
  textlock_fail = textlock_fail,
  textlock_succ = textlock_succ,
}
