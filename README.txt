== Name ==

luapatch - Pure Lua implementation of the Unix patch utility (unified diffs
           only).

== Description ==

This is a Lua implementation of the patch utility[1].  It only supports
unified diffs (diff -u).

A main motivation of this utility is to provide a platform-independent, easily
deployable, and simple patch utility for LuaRocks[2].

== Usage ==

For help:

  ./patch.lua --help

To patch current directory using patch file "mypatch":

  ./patch.lua < mypatch

== Download/Source ==

The latest source can be downloaded from

        * http://github.com/davidm/luapatch/

== Project Page ==

        * http://lua-users.org/wiki/LuaPatch

== Status ==

This code is new should undergo further testing.  Some of the style might be
further improved as it was converted from Python.

== License ==

(c) 2008 David Manura, Licensed under the same terms as Lua (MIT license).
Code is heavilly based on the Python-based patch.py version 8.06-1, Copyright
(c) 2008 rainforce.org, MIT License.  See included LICENSE.txt file.

Note: the source reuses Lua optparse (
http://lua-users.org/wiki/CommandLineParsing ) and {{file_lines}} (
http://lua-users.org/wiki/DavidManura ).

== See Also ==

Related documentation and implementations on patch:

        * [1] [http://en.wikipedia.org/wiki/Patch_(Unix) Wikipedia:Patch (Unix)]
        * [2] [http://lists.luaforge.net/pipermail/luarocks-developers/2008-September/000899.html
               luarocks-developers:2008-September/000899.html]
        * POSIX
          [http://www.opengroup.org/onlinepubs/009695399/utilities/patch.html
          patch] and
          [http://www.opengroup.org/onlinepubs/009695399/utilities/diff.html
          diff] specifications
        * [http://www.gnu.org/software/diffutils/manual/html_node/Detailed-Unified.html
          diffutils manual page on the patch format]
        * [http://linux.die.net/man/1/patch GNU patch man page]
        * [http://www.artima.com/weblogs/viewpost.jsp?thread=164293
          Unified Diff Format] by Guido van Rossum
        * [http://www.gnu.org/software/patch/ GNU patch]
        * [http://code.google.com/p/python-patch/wiki/README patch.py]
          Python implementation of patch (which this is based on)
        * [http://sourceforge.net/projects/phppatcher/ phppatcher]
          PHP implementation of patch
        * [http://members.chello.nl/~w.couwenberg ldiff & lpatch]
          (5.1) A very small diff and patch tool with proprietary binary
           diff format
