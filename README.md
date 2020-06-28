# [Neovim Async Tutorial (lua)](https://ms-jpq.github.io/neovim-async-tutorial)

Async Await in [90 lines](https://github.com/ms-jpq/neovim-async-tutorial/blob/master/lua/async.lua) of code.

## Special Thanks

[svermeulen](https://github.com/svermeulen) for fixing [inability to return functions](https://github.com/ms-jpq/neovim-async-tutorial/issues/2).

## Preface

This tutorial assumes that you are familiar with the concept of `async` `await`

You will also need to read through the [first 500 words](https://www.lua.org/pil/9.1.html) of how coroutines work in lua.

## [Luv](https://github.com/luvit/luv)

Neovim use [libuv](https://github.com/libuv/libuv) for async, the same monster that is the heart of NodeJS.

The `libuv` bindings are exposed through `luv` for lua, this is accessed using `vim.loop`.

Most of the `luv` APIs are similar to that of NodeJS, ie in the form of

`API :: (param1, param2, callback)`

Our goal is avoid the dreaded calback hell.

## Preview

```lua
local a = require "async"

local do_thing = a.sync(function (val)
  local o = a.wait(async_func())
  return o + val
end)

local main = a.sync(function ()
  local thing = a.wait(do_thing()) -- composable!

  local x = a.wait(async_func())
  local y, z = a.wait_all{async_func(), async_func()}
end)

main()
```

## [Coroutines](https://www.lua.org/pil/9.1.html)

If you don't know how coroutines work, go read the section on generators on [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Iterators_and_Generators).

It is in js, but the idea is identical, and the examples are much better.

---

Here is an example of coroutines in Lua:

Note that in Lua code `coroutine` is not a coroutine, it is an namespace.

To avoid confusion, I will follow the convention used in the Lua book, and use `thread` to denote coroutines in code.

```lua
local co = coroutine

local thread = co.create(function ()
  local x, y, z = co.yield(something)
  return 12
end)

local cont, ret = co.resume(thread, x, y, z)
```

---

Notice the similarities with `async` `await`

In both `async` `await` and `coroutines`, the LHS of the assignment statements receives values from the RHS.

This is how it works in all synchronous assignments. Except, we can defer the transfer of the values from RHS.

The idea is that we will make RHS send values to LHS, when RHS is ready.

## Synchronous Coroutines

To warm up, we will do a synchronous version first, where the RHS is always ready.

Here is how you send values to a coroutine:

```lua
co.resume(thread, x, y, z)
```

---

The idea is that we will repeat this until the coroutine has been "unrolled"

```lua
local pong = function (thread)
  local nxt = nil
  nxt = function (cont, ...)
    if not cont
      then return ...
      else return nxt(co.resume(thread, ...))
    end
  end
  return nxt(co.resume(thread))
end
```

---

if we give `pong` some coroutine, it will recursively run the coroutine until completion

```lua
local thread = co.create(function ()
  local x = co.yield(1)
  print(x)
  local y, z = co.yield(2, 3)
  print(y)
end)

pong(thread)
```

We can expect to see `1`, `2 3` printed.

## [Thunk](https://stackoverflow.com/questions/2641489/what-is-a-thunk)

Once you understand how the synchronous `pong` works, we are super close!

But before we make the asynchronous version, we need to learn one more simple concept.

For our purposes a `Thunk` is function whose purpose is to invoke a callback.

i.e. It adds a transformation of `(arg, callback) -> void` to `arg -> (callback -> void) -> void`

```lua
local read_fs = function (file)
  local thunk = function (callback)
    fs.read(file, callback)
  end
  return thunk
end
```

---

This too, is a process that can be automated:

```lua
local wrap = function (func)
  local factory = function (...)
    local params = {...}
    local thunk = function (step)
      table.insert(params, step)
      return func(unpack(params))
    end
    return thunk
  end
  return factory
end

local thunk = wrap(fs.read)
```

So why do we need this?

## Async Await

The answer is simple! We will use thunks for our RHS!

---

With that said, we will still need one more magic trick, and that is to make a `step` function.

The sole job of the `step` funciton is to take the place of the callback to all the thunks.

In essence, on every callback, we take 1 step forward in the coroutine.

```lua
local pong = function (func, callback)
  assert(type(func) == "function", "type error :: expected func")
  local thread = co.create(func)
  local step = nil
  step = function (...)
    local stat, ret = co.resume(thread, ...)
    assert(stat, ret)
    if co.status(thread) == "dead" then
      (callback or function () end)(ret)
    else
      assert(type(ret) == "function", "type error :: expected func")
      ret(step)
    end
  end
  step()
end
```

Notice that we also make pong call a callback once it is done.

---

We can see it in action here:

```lua
local echo = function (...)
  local args = {...}
  local thunk = function (step)
    step(unpack(args))
  end
  return thunk
end

local thread = co.create(function ()
  local x, y, z = co.yield(echo(1, 2, 3))
  print(x, y, z)
  local k, f, c = co.yield(echo(4, 5, 6))
  print(k, f, c)
end)

pong(thread)
```

We can expect this to print `1 2 3` and `4 5 6`

Note, we are using a synchronous `echo` for illustration purposes. It doesn't matter when the `callback` is invoked. The whole mechanism is agnostic to timing.

You can think of async as the more generalized version of sync.

You can run an asynchronous version in the last section.

## Await All

One more benefit of thunks, is that we can use them to inject arbitrary computation.

Such as joining together many thunks.

```lua
local join = function (thunks)
  local len = table.getn(thunks)
  local done = 0
  local acc = {}

  local thunk = function (step)
    if len == 0 then
      return step()
    end
    for i, tk in ipairs(thunks) do
      local callback = function (...)
        acc[i] = {...}
        done = done + 1
        if done == len then
          step(unpack(acc))
        end
      end
      tk(callback)
    end
  end
  return thunk
end
```

This way we can perform `await_all` on many thunks as if they are a single one.

## More Sugar

All this explicit handling of coroutines are abit ugly. The good thing is that we can completely hide the implementation detail to the point where we don't even need to require the `coroutine` namespace!

Simply wrap the coroutine interface with some friendly helpers

```lua
local pong = function (func, callback)
  local thread = co.create(func)
  ...
end

local await = function (defer)
  return co.yield(defer)
end

local await_all = function (defer)
  return co.yield(join(defer))
end
```

## Composable

At this point we are almost there, just one more step!

```lua
local sync = wrap(pong)
```

We `wrap` `pong` into a thunk factory, so that calling it is no different than yielding other thunks. This is how we can compose together our `async` `await`.

It's thunks all the way down.

## Tips and Tricks

In Neovim, we have something called `textlock`, which prevents many APIs from being called unless you are in the main event loop.

This will prevent you from essentially modifying any Neovim states once you have invoked a `vim.loop` funciton, which run in a seperate loop.

Here is how you break back to the main loop:

```lua
local main_loop = function (f)
  vim.schedule(f)
end
```

```lua
a.sync(function ()
  -- do something in other loop
  a.wait(main_loop)
  -- you are back!
end)()
```

## Plugin!

I have bundle up this tutorial as a vim plugin, you can install it the usual way.

`Plug 'ms-jpq/neovim-async-tutorial', {'branch': 'neo'}`

and then call the test functions like so:

`:LuaAsyncExample`

`:LuaSyncExample`

`:LuaTextlockFail`

`:LuaTextLockSucc`
