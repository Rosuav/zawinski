inherit movablewindow;
constant is_subwindow = 0;
constant pos_key = "mainwindow";
constant load_size = 1;
object mainwindow;

void makewindow()
{
	win->menuitems = ([]);
	win->mainwindow = mainwindow = GTK2.Window((["title": "Zawinski"]))->add(GTK2.Vbox(0, 0)
		->pack_start(GTK2.MenuBar()
			->add(GTK2.MenuItem("_Options")->set_submenu(win->optmenu = (object)GTK2.Menu()))
		,0,0,0)
		->add(GTK2.Hbox(0, 0)
			->pack_start(GTK2.ScrolledWindow()->set_policy(GTK2.POLICY_NEVER, GTK2.POLICY_AUTOMATIC)->add(
				win->folderview = GTK2.TreeView(win->folders = GTK2.TreeStore(({"string", "string"})))
					->set_headers_visible(0)
					->append_column(GTK2.TreeViewColumn("Folder", GTK2.CellRendererText(), "text", 0))
					//Hidden column: IMAP folder name. Consists of the full hierarchy, eg INBOX.Stuff.Old
			), 0, 0, 0)
			->add(GTK2.ScrolledWindow()->set_policy(GTK2.POLICY_AUTOMATIC, GTK2.POLICY_AUTOMATIC)->add(
				win->messageview = GTK2.TreeView(GTK2.TreeModelSort(
					win->messages = GTK2.TreeStore(({"int", "string", "string", "string", "int"})))
					->set_sort_column_id(4, 1)
				)
					//Hidden column: UID
					->append_column(GTK2.TreeViewColumn("From", GTK2.CellRendererText(), "text", 1))
					//->append_column(GTK2.TreeViewColumn("To", GTK2.CellRendererText(), "text", 2))
					->append_column(GTK2.TreeViewColumn("Subject", GTK2.CellRendererText(([
						"ellipsize": GTK2.PANGO_ELLIPSIZE_END, "width-chars": 30
					])), "text", 3))
					//Hidden column: INTERNALDATE as a Unix time (0 for unknown)
			))
		)
	);
	::makewindow();
}

int sig_mainwindow_destroy() {exit(0);}

//Locate an account by its text and return an iterator
object locate_account(string addr)
{
	//Is there a better way to do this than just linear searching??
	//TODO: GTK2.TreeRowReference.
	object iter = win->folders->get_iter_from_string("0");
	if (!iter) return 0;
	do
	{
		if (win->folders->get_value(iter, 0) == addr) return iter;
	} while (win->folders->iter_next(iter));
}

void add_account(string addr)
{
	object root = win->folders->append();
	win->folders->set_row(root, ({addr}));
	win->folders->set_row(win->folders->append(root), ({"(loading)"}));
	win->folderview->expand_all();
}

void remove_account(string addr)
{
	object iter = locate_account(addr);
	if (iter) win->folders->remove(iter);
}

void update_folders(string addr, array(string) folders)
{
	object iter = locate_account(addr);
	if (!iter) return;
	//Remove all children
	while (object it = win->folders->iter_children(iter))
		win->folders->remove(it);
	mapping(string:object) parents = (["": iter]);
	foreach (folders, string fld)
	{
		array parts = fld / ".";
		object it = win->folders->append(parents[parts[..<1]*"."]);
		win->folders->set_row(it, ({parts[-1], fld}));
		parents[fld] = it;
	}
	win->folderview->expand_all();
}

void clear_messages()
{
	win->messages->clear();
}

string shorten_address(string addr)
{
	if (!addr) return "";
	if (sscanf(addr, "\"%s\" <%*s>", string name) && name != "") return name;
	if (sscanf(addr, "%s <%*s>", string name) && name != "") return name;
	if (sscanf(addr, "%*s (%s)", string name) && name != "") return name;
	return addr;
}

void update_message(mapping(string:mixed) msg, mapping(string:mixed)|void parent)
{
	//TODO: Order by Calendar.dwim_time(msg->INTERNALDATE)->unix_time() descending
	//TODO: Use msg->headers["message-id"] and msg->headers->references/" " to
	//establish a parent-child hierarchy (and do the above sort within that).
	//TODO: See whether it's better to sort by date *ascending* for everything after
	//the first level of messages. That would keep conversations together; within a
	//thread, new messages would appear at the bottom, but new threads would appear
	//at the top.
	if (!msg->rowref || !msg->rowref->valid())
	{
		object ref = parent?->rowref;
		mixed par = ref && ref->valid() && win->messages->get_iter(ref->get_path());
		object iter = win->messages->append(par || UNDEFINED);
		msg->rowref = GTK2.TreeRowReference(win->messages, win->messages->get_path(iter));
		win->messageview->expand_all();
	}
	win->messages->set_row(win->messages->get_iter(msg->rowref->get_path()), ({
		msg->UID,
		shorten_address(msg->headers->from),
		shorten_address(msg->headers->to),
		msg->headers->subject || "",
		Calendar.dwim_time(msg->INTERNALDATE)->unix_time(),
	}));
}

void sig_folderview_cursor_changed(object self)
{
	object path = self->get_cursor()->path;
	string folder = win->folders->get_value(win->folders->get_iter(path), 1);
	//Scan up to get to the top-level entry for this path
	//We get the array of indices (the fundamental of the path), take just
	//the first one, and construct a new path consisting of just that.
	object toplevel = win->folders->get_iter(GTK2.TreePath((string)path->get_indices()[0]));
	string addr = win->folders->get_value(toplevel, 0);
	G->G->connection->select_folder(addr, folder);
}

constant options_update = "Update code";
void opt_update()
{
	int err = G->bootstrap_all();
	if (!err) return; //All OK? Be silent.
	if (string winid = getenv("WINDOWID")) //On some Linux systems we can pop the console up.
		catch (Process.create_process(({"wmctrl", "-ia", winid}))->wait()); //Try, but don't mind errors, eg if wmctrl isn't installed.
	MessageBox(0, GTK2.MESSAGE_ERROR, GTK2.BUTTONS_OK, err + " compilation error(s) - see console", win->mainwindow);
}

constant options_accounts = "Configure accounts";
class opt_accounts
{
	inherit configdlg;
	mapping(string:mixed) windowprops=(["title": "Configure mail accounts"]);
	constant elements=({"kwd:Name", "IMAP server", "Login", "*Password"});
	constant persist_key = "accounts";
	void save_content() {call_out(G->G->connection->connect, 0);}
	void delete_content() {call_out(G->G->connection->connect, 0);}
}

void create(string name)
{
	if (G->G->window) mainwindow = G->G->window->mainwindow;
	G->G->window = this;
	::create(name);
	foreach (sort(indices(this_program)), string attr) if (sscanf(attr, "options_%s", string opt) && this["opt_" + opt])
	{
		if (object old = win->menuitems[opt]) old->destroy();
		object mi = GTK2.MenuItem(this[attr]);
		win->optmenu->add(mi->show());
		mi->signal_connect("activate", this["opt_" + opt]);
		win->menuitems[opt] = mi;
	}
}
