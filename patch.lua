#!/usr/bin/env lua
-- patch.lua - Patch utility to apply unified diffs
--
-- http://lua-users.org/wiki/LuaPatch
--
-- (c) 2008 David Manura, Licensed under the same terms as Lua (MIT license).
-- Code is heavilly based on the Python-based patch.py version 8.06-1
--   Copyright (c) 2008 rainforce.org, MIT License
--   Project home: http://code.google.com/p/python-patch/ .
-- See included LICENSE.txt file.

local M = {}

local version = '0.1'

local io = io
local os = os
local string = string
local table = table
local format = string.format

-- logging
local debugmode = false
local function debug(s) end
local function info(s) end
local function warning(s) io.stderr:write(s .. '\n') end

local function DEBUG(t)
  require "table2"
  require "string2"
  table.print(t, 50)
end

-- Returns boolean whether string s2 starts with string s.
local function startswith(s, s2)
  return s:sub(1, #s2) == s2
end

-- Returns boolean whether string s2 ends with string s.
local function endswith(s, s2)
  return #s >= #s2 and s:sub(#s-#s2+1) == s2
end

-- Returns string s after filtering out any new-line characters from end.
local function endlstrip(s)
  return s:gsub('[\r\n]+$', '')
end

-- Returns shallow copy of table t.
local function table_copy(t)
  local t2 = {}
  for k,v in pairs(t) do t2[k] = v end
  return t2
end

-- Returns boolean whether array t contains value v.
local function array_contains(t, v)
  for _,v2 in ipairs(t) do if v == v2 then return true end end
  return false
end

local function exists(filename)
  local fh = io.open(filename)
  local result = fh ~= nil
  if fh then fh:close() end
  return result
end
local function isfile() return true end --FIX?

local function read_file(filename)
  local fh, err, oserr = io.open(filename, 'rb')
  if not fh then return fh, err, oserr end
  local data, err, oserr = fh:read'*a'
  fh:close()
  if not data then return nil, err, oserr end
  return data
end

local function write_file(filename, data)
  local fh, err, oserr = io.open(filename 'wb')
  if not fh then return fh, err, oserr end
  local status, err, oserr = fh:write(data)
  fh:close()
  if not status then return nil, err, oserr end
  return true
end

local function file_copy(src, dest)
  local data, err, oserr = read_file(src)
  if not data then return data, err, oserr end
  local status, err, oserr = write_file(dest)
  if not status then return status, err, oserr end
  return true
end

--
-- file_lines(f) is similar to f:lines() for file f.
-- The main difference is that read_lines includes
-- new-line character sequences ("\n", "\r\n", "\r"),
-- if any, at the end of each line.  Embedded "\0" are also handled.
-- Caution: The newline behavior can depend on whether f is opened
-- in binary or ASCII mode.
-- (file_lines - version 20080913)
--
local function file_lines(f)
  local CHUNK_SIZE = 1024
  local buffer = ""
  local pos_beg = 1
  return function()
    local pos, chars
    while 1 do
      pos, chars = buffer:match('()([\r\n].)', pos_beg)
      if pos or not f then
        break
      elseif f then
        local chunk = f:read(CHUNK_SIZE)
        if chunk then
          buffer = buffer:sub(pos_beg) .. chunk
          pos_beg = 1
        else
          f = nil
        end
      end
    end
    if not pos then
      pos = #buffer
    elseif chars == '\r\n' then
      pos = pos + 1
    end
    local line = buffer:sub(pos_beg, pos)
    pos_beg = pos + 1
    if #line > 0 then
      return line
    end    
  end
end

local function match_linerange(line)
  local m1, m2, m3, m4 =      line:match("^@@ %-(%d+),(%d+) %+(%d+),(%d+)")
  if not m1 then m1, m3, m4 = line:match("^@@ %-(%d+) %+(%d+),(%d+)") end
  if not m1 then m1, m2, m3 = line:match("^@@ %-(%d+),(%d+) %+(%d+)") end
  if not m1 then m1, m3     = line:match("^@@ %-(%d+) %+(%d+)") end
  return m1, m2, m3, m4
end

local function read_patch(filename)
  -- define possible file regions that will direct the parser flow
  local state = 'header'
    -- 'header'    - comments before the patch body
    -- 'filenames' - lines starting with --- and +++
    -- 'hunkhead'  - @@ -R +R @@ sequence
    -- 'hunkbody'
    -- 'hunkskip'  - skipping invalid hunk mode

  local lineends = {lf=0, crlf=0, cr=0}
  local files = {source={}, target={}, hunks={}, fileends={}, hunkends={}}
  local nextfileno = 0
  local nexthunkno = 0    --: even if index starts with 0 user messages
                          --  number hunks from 1

  -- hunkinfo holds parsed values, hunkactual - calculated
  local hunkinfo = {
    startsrc=nil, linessrc=nil, starttgt=nil, linestgt=nil,
    invalid=false, text={}
  }
  local hunkactual = {linessrc=nil, linestgt=nil}

  info(format("reading patch %s", filename))

  local fp = filename == '-' and io.stdin or assert(io.open(filename, "rb"))
  local lineno = 0
  for line in file_lines(fp) do
    lineno = lineno + 1
    if state == 'header' then
      if startswith(line, "--- ") then
        state = 'filenames'
      end
      -- state is 'header' or 'filenames'
    end
    if state == 'hunkbody' then
      -- skip hunkskip and hunkbody code until definition of hunkhead read

      -- process line first
      if line:match"^[- +\\]" then
          -- gather stats about line endings
          local he = files.hunkends[nextfileno]
          if endswith(line, "\r\n") then
            he.crlf = he.crlf + 1
          elseif endswith(line, "\n") then
            he.lf = he.lf + 1
          elseif endswith(line, "\r") then
            he.cr = he.cr + 1
          end
          if startswith(line, "-") then
            hunkactual.linessrc = hunkactual.linessrc + 1
          elseif startswith(line, "+") then
            hunkactual.linestgt = hunkactual.linestgt + 1
          elseif startswith(line, "\\") then
            -- nothing
          else
            hunkactual.linessrc = hunkactual.linessrc + 1
            hunkactual.linestgt = hunkactual.linestgt + 1
          end
          table.insert(hunkinfo.text, line)
          -- todo: handle \ No newline cases
      else
          warning(format("invalid hunk no.%d at %d for target file %s",
                         nexthunkno, lineno, files.target[nextfileno]))
          -- add hunk status node
          table.insert(files.hunks[nextfileno], table_copy(hunkinfo))
          files.hunks[nextfileno][nexthunkno].invalid = true
          state = 'hunkskip'
      end

      -- check exit conditions
      if hunkactual.linessrc > hunkinfo.linessrc or
         hunkactual.linestgt > hunkinfo.linestgt
      then
          warning(format("extra hunk no.%d lines at %d for target %s",
                         nexthunkno, lineno, files.target[nextfileno]))
          -- add hunk status node
          table.insert(files.hunks[nextfileno], table_copy(hunkinfo))
          files.hunks[nextfileno][nexthunkno].invalid = true
          state = 'hunkskip'
      elseif hunkinfo.linessrc == hunkactual.linessrc and
             hunkinfo.linestgt == hunkactual.linestgt
      then
          table.insert(files.hunks[nextfileno], table_copy(hunkinfo))
          state = 'hunkskip'

          -- detect mixed window/unix line ends
          local ends = files.hunkends[nextfileno]
          if (ends.cr~=0 and 1 or 0) + (ends.crlf~=0 and 1 or 0) +
             (ends.lf~=0 and 1 or 0) > 1
          then
            warning(format("inconsistent line ends in patch hunks for %s",
                    files.source[nextfileno]))
          end
          if debugmode then
            local debuglines = {crlf=ends.crlf, lf=ends.lf, cr=ends.cr,
                  file=files.target[nextfileno], hunk=nexthunkno}
            debug(format("crlf: %(crlf)d  lf: %(lf)d  cr: %(cr)d\t " ..
                         "- file: %(file)s hunk: %(hunk)d", debuglines))
          end
      end
      -- state is 'hunkbody' or 'hunkskip'
    end

    if state == 'hunkskip' then
      if match_linerange(line) then
        state = 'hunkhead'
      elseif startswith(line, "--- ") then
        state = 'filenames'
        if debugmode and #files.source > 0 then
            debug(format("- %2d hunks for %s", #files.hunks[nextfileno],
                         files.source[nextfileno]))
        end
      end
      -- state is 'hunkskip', 'hunkhead', or 'filenames'
    end
    local advance
    if state == 'filenames' then
      if startswith(line, "--- ") then
        if array_contains(files.source, nextfileno) then
          warning(format("skipping invalid patch for %s",
                         files.source[nextfileno+1]))
          table.remove(files.source, nextfileno+1)
          -- double source filename line is encountered
          -- attempt to restart from this second line
        end
        local match = line:match("^--- ([^\t]+)")
        if not match then
          warning(format("skipping invalid filename at line %d", lineno+1))
          state = 'header'
        else
          table.insert(files.source, match)
        end
      elseif not startswith(line, "+++ ") then
        if array_contains(files.source, nextfileno) then
          warning(format("skipping invalid patch with no target for %s",
                         files.source[nextfileno+1]))
          table.remove(files.source, nextfileno+1)
        else
          -- this should be unreachable
          warning("skipping invalid target patch")
        end
        state = 'header'
      else
        if array_contains(files.target, nextfileno) then
          warning(format("skipping invalid patch - double target at line %d",
                         lineno+1))
          table.remove(files.source, nextfileno+1)
          table.remove(files.target, nextfileno+1)
          nextfileno = nextfileno - 1
          -- double target filename line is encountered
          -- switch back to header state
          state = 'header'
        else
          local re_filename = "^%+%+%+ ([^\t]+)"
          local match = line:match(re_filename)
          if not match then
            warning(format(
              "skipping invalid patch - no target filename at line %d",
              lineno+1))
            state = 'header'
          else
            table.insert(files.target, match)
            nextfileno = nextfileno + 1
            nexthunkno = 0
            table.insert(files.hunks, {})
            table.insert(files.hunkends, table_copy(lineends))
            table.insert(files.fileends, table_copy(lineends))
            state = 'hunkhead'
            advance = true
          end
        end
      end
      -- state is 'filenames', 'header', or ('hunkhead' with advance)
    end
    if not advance and state == 'hunkhead' then
      local m1, m2, m3, m4 = match_linerange(line)
      if not m1 then
        if not array_contains(files.hunks, nextfileno-1) then
          warning(format("skipping invalid patch with no hunks for file %s",
                         files.target[nextfileno]))
        end
        state = 'header'
      else
        hunkinfo.startsrc = tonumber(m1)
        hunkinfo.linessrc = tonumber(m2 or 1)
        hunkinfo.starttgt = tonumber(m3)
        hunkinfo.linestgt = tonumber(m4 or 1)
        hunkinfo.invalid = false
        hunkinfo.text = {}

        hunkactual.linessrc = 0
        hunkactual.linestgt = 0

        state = 'hunkbody'
        nexthunkno = nexthunkno + 1
      end
      -- state is 'header' or 'hunkbody'
    end
  end
  if state ~= 'hunkskip' then
    warning(format("patch file incomplete - %s", filename))
    -- os.exit(?)
  else
    -- duplicated message when an eof is reached
    if debugmode and #files.source > 0 then
      debug(format("- %2d hunks for %s", #files.hunks[nextfileno],
                   files.source[nextfileno]))
    end
  end

  local sum = 0; for _,hset in ipairs(files.hunks) do sum = sum + #hset end
  info(format("total files: %d  total hunks: %d", #files.source, sum))
  fp:close()
  return files
end
M.read_patch = read_patch


local function check_patched(filename, hunks)
  local matched = true
  local fp = assert(io.open(filename))
  local readline = file_lines(fp)

  local lineno = 1
  local line = readline()
  local hno = nil
  local ok, err = pcall(function()
    if #line == 0 then
      error 'nomatch'
    end
    for hno, h in ipairs(hunks) do
      -- skip to line just before hunk starts
      while lineno < h.starttgt-1 do
        line = readline()
        lineno = lineno + 1
        if #line == 0 then
          error 'nomatch'
        end
      end
      for hline in h.text do
        -- todo: \ No newline at the end of file
        if not startswith(hline, "-") and not startswith(hline, "\\") then
          line = readline()
          lineno = lineno + 1
          if #line == 0 then
            error 'nomatch'
          end
          if endlstrip(line) ~= endlstrip(hline:sub(2)) then
            warning(format("file is not patched - failed hunk: %d", hno))
            error 'nomatch'
          end
        end
      end
    end
  end)
  if err == 'nomatch' then
    matched = false
  end
    -- todo: display failed hunk, i.e. expected/found

  fp:close()
  return matched
end

local function patch_hunks(srcname, tgtname, hunks)
  local src = assert(io.open(srcname, "rb"))
  local tgt = assert(io.open(tgtname, "wb"))

  local src_readline = file_lines(src)

  -- todo: detect linefeeds early - in apply_files routine
  --       to handle cases when patch starts right from the first
  --       line and no lines are processed. At the moment substituted
  --       lineends may not be the same at the start and at the end
  --       of patching. Also issue a warning about mixed lineends

  local srclineno = 1
  local lineends = {['\n']=0, ['\r\n']=0, ['\r']=0}
  for hno, h in ipairs(hunks) do
    debug(format("processing hunk %d for file %s", hno, tgtname))
    -- skip to line just before hunk starts
    while srclineno < h.startsrc do
      local line = src_readline()
      -- Python 'U' mode works only with text files
      if endswith(line, "\r\n") then
        lineends["\r\n"] = lineends["\r\n"] + 1
      elseif endswith(line, "\n") then
        lineends["\n"] = lineends["\n"] + 1
      elseif endswith(line, "\r") then
        lineends["\r"] = lineends["\r"] + 1
      end
      tgt:write(line)
      srclineno = srclineno + 1
    end

    for _,hline in ipairs(h.text) do
      -- todo: check \ No newline at the end of file
      if startswith(hline, "-") or startswith(hline, "\\") then
        src_readline()
        srclineno = srclineno + 1
      else
        if not startswith(hline, "+") then
          src_readline()
          srclineno = srclineno + 1
        end
        local line2write = hline:sub(2)
        -- detect if line ends are consistent in source file
        local sum = 0
        for k,v in pairs(lineends) do if v > 0 then sum=sum+1 end end
        if sum == 1 then
          local newline
          for k,v in pairs(lineends) do if v ~= 0 then newline = k end end
          tgt:write(endlstrip(line2write) .. newline)
        else -- newlines are mixed or unknown
          tgt:write(line2write)
        end
      end
    end
  end
  for line in src_readline do
    tgt:write(line)
  end
  tgt:close()
  src:close()
  return true
end 


local function apply_patch(patch)
  local total = #patch.source
  for fileno, filename in ipairs(patch.source) do
    local continue
    local f2patch = filename
    if not exists(f2patch) then
      f2patch = patch.target[fileno]
      if not exists(f2patch) then  --FIX:if f2patch nil
        warning(format("source/target file does not exist\n--- %s\n+++ %s",
                filename, f2patch))
        continue = true
      end
    end
    if not continue and not isfile(f2patch) then
      warning(format("not a file - %s", f2patch))
      continue = true
    end
    if not continue then

    filename = f2patch

    info(format("processing %d/%d:\t %s", fileno, total, filename))

    -- validate before patching
    local f2fp = assert(io.open(filename))
    local hunkno = 1
    local hunk = patch.hunks[fileno][hunkno]
    local hunkfind = {}
    local hunkreplace = {}
    local validhunks = 0
    local canpatch = false
    local hunklineno
    local isbreak
    local lineno = 0
    for line in file_lines(f2fp) do
      lineno = lineno + 1
      local continue
      if not hunk or lineno < hunk.startsrc then
        continue = true
      elseif lineno == hunk.startsrc then
        hunkfind = {}
        for _,x in ipairs(hunk.text) do
        if x:sub(1,1) == ' ' or x:sub(1,1) == '-' then
          hunkfind[#hunkfind+1] = endlstrip(x:sub(2))
        end end
        hunkreplace = {}
        for _,x in ipairs(hunk.text) do
        if x:sub(1,1) == ' ' or x:sub(1,1) == '+' then
          hunkreplace[#hunkreplace+1] = endlstrip(x:sub(2))
        end end
        --pprint(hunkreplace)
        hunklineno = 1

        -- todo \ No newline at end of file
      end
      -- check hunks in source file
      if not continue and lineno < hunk.startsrc + #hunkfind - 1 then
        if endlstrip(line) == hunkfind[hunklineno] then
          hunklineno = hunklineno + 1
        else
          debug(format("hunk no.%d doesn't match source file %s",
                       hunkno, filename))
          -- file may be already patched, but check other hunks anyway
          hunkno = hunkno + 1
          if hunkno <= #patch.hunks[fileno] then
            hunk = patch.hunks[fileno][hunkno]
            continue = true
          else
            isbreak = true; break
          end
        end
      end
      -- check if processed line is the last line
      if not continue and lineno == hunk.startsrc + #hunkfind - 1 then
        debug(format("file %s hunk no.%d -- is ready to be patched",
                     filename, hunkno))
        hunkno = hunkno + 1
        validhunks = validhunks + 1
        if hunkno <= #patch.hunks[fileno] then
          hunk = patch.hunks[fileno][hunkno]
        else
          if validhunks == #patch.hunks[fileno] then
            -- patch file
            canpatch = true
            isbreak = true; break
          end
        end
      end
    end
    if not isbreak then
      if hunkno <= #patch.hunks[fileno] then
        warning(format("premature end of source file %s at hunk %d",
                       filename, hunkno))
      end
    end
    f2fp:close()

    if validhunks < #patch.hunks[fileno] then
      if check_patched(filename, patch.hunks[fileno]) then
        warning(format("already patched  %s", filename))
      else
        warning(format("source file is different - %s", filename))
      end
    end
    if canpatch then
      local backupname = filename .. ".orig"
      if exists(backupname) then
        warning(format("can't backup original file to %s - aborting",
                       backupname))
      else
        assert(os.rename(filename, backupname))
        if patch_hunks(backupname, filename, patch.hunks[fileno]) then
          warning(format("successfully patched %s", filename))
          assert(os.remove(backupname))
        else
          warning(format("error patching file %s", filename))
          assert(file_copy(filename, filename .. ".invalid"))
          warning(format("invalid version is saved to %s",
                         filename .. ".invalid"))
          -- todo: proper rejects
          assert(os.rename(backupname, filename))
        end
      end
    end

    end -- if not continue
  end -- for
  -- todo: check for premature eof
end
M.apply_patch = apply_patch

-- Lua command line option parser based on Python optparse.
-- http://lua-users.org/wiki/CommandLineParsing
local function OptionParser(t)
  local usage = t.usage
  local version = t.version

  local o = {}
  local option_descriptions = {}
  local option_of = {}

  function o.fail(s) -- extension
    io.stderr:write(s .. '\n')
    os.exit(1)
  end

  function o.add_option(optdesc)
    option_descriptions[#option_descriptions+1] = optdesc
    for _,v in ipairs(optdesc) do
      option_of[v] = optdesc
    end
  end
  function o.parse_args()
    -- expand options (e.g. "--input=file" -> "--input", "file")
    local arg = {unpack(arg)}
    for i=#arg,1,-1 do local v = arg[i]
      local flag, val = v:match('^(%-%-%w+)=(.*)')
      if flag then
        arg[i] = flag
        table.insert(arg, i+1, val)
      end
    end

    local options = {}
    local args = {}
    local i = 1
    while i <= #arg do local v = arg[i]
      local optdesc = option_of[v]
      if optdesc then
        local action = optdesc.action
        local val
        if action == 'store' or action == nil then
          i = i + 1
          val = arg[i]
          if not val then o.fail('option requires an argument ' .. v) end
        elseif action == 'store_true' then
          val = true
        elseif action == 'store_false' then
          val = false
        end
        options[optdesc.dest] = val
      else
        if v:match('^%-') then o.fail('invalid option ' .. v) end
        args[#args+1] = v
      end
      i = i + 1
    end
    if options.help then
      o.print_help()
      os.exit()
    end
    if options.version then
      io.stdout:write(t.version .. "\n")
      os.exit()
    end
    return options, args
  end

  local function flags_str(optdesc)
    local sflags = {}
    local action = optdesc.action
    for _,flag in ipairs(optdesc) do
      local sflagend
      if action == nil or action == 'store' then
        local metavar = optdesc.metavar or optdesc.dest:upper()
        sflagend = #flag == 2 and ' ' .. metavar
                              or  '=' .. metavar
      else
        sflagend = ''
      end
      sflags[#sflags+1] = flag .. sflagend
    end
    return table.concat(sflags, ', ')
  end

  function o.print_help()
    io.stdout:write("Usage: " .. usage:gsub('%%prog', arg[0]) .. "\n")
    io.stdout:write("\n")
    io.stdout:write("Options:\n")
    for _,optdesc in ipairs(option_descriptions) do
      io.stdout:write("  " .. flags_str(optdesc) ..
                      "  " .. optdesc.help .. "\n")
    end
  end
  o.add_option{"--help", action="store_true", dest="help",
               help="show this help message and exit"}
  if t.version then
    o.add_option{"--version", action="store_true", dest="version",
                 help="output version info."}
  end
  return o
end

-- Test whether running as script rather than loadfile/require.
-- (this is a hack to achieve a Python __main__ like effect)
local is_main = not pcall(getfenv, 4)

if is_main then
  -- Follow patch command-interface as much as reasonably possible:
  --   http://www.opengroup.org/onlinepubs/009695399/utilities/patch.html
  --   http://linux.die.net/man/1/patch

  local opt = OptionParser{usage="%prog [options] [patch-file]",
                           version=format("lua-patch %s", version)}
  opt.add_option{
    "-i", "--input", dest="patchfile",
    help="read patch from PATCHFILE instead of stdin."}
  local options, args = opt.parse_args()

  local patchfile = options.patchfile or '-'

  if options.help then
    opt.print_help()
    os.exit()
  end
  if patchfile ~= '-' and not exists(patchfile) or not isfile(patchfile) then
    opt.fail(format("patch file does not exist - %s", patchfile))
  end
  if #args > 0 then
    opt.fail("positions arguments not supported - " .. tostring(args[1]))
  end

  local patch = read_patch(patchfile)
  --DEBUG(patch)
  apply_patch(patch)

  -- todo: document and test line ends handling logic - patch.py
  -- detects proper line-endings
  --       for inserted hunks and issues a warning if patched file
  -- has incosistent line ends
end

return M
