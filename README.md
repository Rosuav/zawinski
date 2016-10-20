# Zawinski

Simple-but-functional mail client.

In utter defiance of Zawinski's Law, this program does not expand until it can
read mail - it starts out with reading mail, and will vehemently resist expanding
too much or too rapidly.

It will be built on the same self-updating model as Gypsum and StilleBot.

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
