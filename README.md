# Zawinski

Simple-but-functional mail client.

In utter defiance of Zawinski's Law, this program does not expand until it can
read mail - it starts out with reading mail, and will vehemently resist expanding
too much or too rapidly.

It is built on the same self-updating model as Gypsum and StilleBot.

TODO: Make a bootstrapper as part of the framework. And a gh-pages menu page.
Hmm. Where would be the boundary between repos? They'd want to share a lot of the
structure - not just the one master file that never updates. So does an update
download from two repos? (Probably okay.) Should there be two files of globals -
one shared, one private?

Basic structure: Tree down the left (accounts and folders), and messages on the
right. Double click message to open independent window (not affected by code
update - just reopen them). Menu bar for compose etc.

TODO: Threading. Should messages be treated as conversations (Gmail style), or
as stand-alone entities (classic style), or as some kind of tree (Mailman style)?
A tree could cost a lot in performance (have to load all messages), and might
complicate the sorting.

NOTE: This requires a *very* recent build of Pike. Changes have been made in the
core language to support functionality needed (or wanted) by Zawinski. Use 8.1,
and make sure your Pike version is at least as new as your Zawinski. (One day,
these changes will be in the stable builds, but they'll still be called 8.1 or
better. So assume that anything older than 8.1 won't work.) CAUTION: Currently
requires Pike branch rosuav/gtk2-drag-drop.

License: MIT

Copyright (c) 2016, Chris Angelico

Permission is hereby granted, free of charge, to any person obtaining a copy of 
this software and associated documentation files (the "Software"), to deal in 
the Software without restriction, including without limitation the rights to 
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
of the Software, and to permit persons to whom the Software is furnished to do 
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all 
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
SOFTWARE.
