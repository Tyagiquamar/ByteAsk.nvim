-- Headless regression tests for how :ByteAskExec transports editor context.
--
--   nvim --headless --clean -l tests/exec_stdin.lua
--
-- The selection/diagnostics block must travel on stdin, not in the command
-- line: `byteask exec` appends piped stdin as a `<stdin>` block, while Windows
-- refuses to spawn a process whose command line exceeds 32K characters.
-- Exits non-zero when any expectation fails.
local this = debug.getinfo(1, 'S').source:sub(2)
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(this, ':p:h:h'))

local captured = {}

rawset(vim.fn, 'jobstart', function(argv, opts)
  captured.argv = argv
  captured.opts = opts
  return 4242
end)
rawset(vim.fn, 'chansend', function(id, data)
  captured.stdin = data
  return 1
end)
rawset(vim.fn, 'chanclose', function(_, stream)
  captured.closed = stream
end)

local failures = 0
local function check(name, ok, detail)
  if ok then
    print('ok - ' .. name)
  else
    failures = failures + 1
    print('FAIL - ' .. name .. (detail and ('\n  ' .. detail) or ''))
  end
end

local commands = require('byteask.commands')

-- A selection big enough to blow the Windows command-line limit on its own.
local context = string.rep('x', 40000)
commands.exec('Improve this code.', context)

local argv = captured.argv or {}
local longest = 0
for _, arg in ipairs(argv) do
  longest = math.max(longest, #arg)
end

check('the instruction stays on the command line', vim.tbl_contains(argv, 'Improve this code.'))
check('no command-line argument carries the context', longest < 1000, 'longest argument: ' .. longest)
check(
  'the context is written to stdin',
  captured.stdin == context,
  'stdin bytes: ' .. tostring(captured.stdin and #captured.stdin)
)
check('stdin is closed so the CLI sees EOF', captured.closed == 'stdin')

if failures > 0 then
  print(string.format('\n%d check(s) FAILED', failures))
  vim.cmd('cquit 1')
end
print('\nAll checks passed.')
vim.cmd('quit')
