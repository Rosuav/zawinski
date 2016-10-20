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
			->pack_start(win->folderview = GTK2.TreeView(win->folders = GTK2.TreeStore(({"string"})))
				->append_column(GTK2.TreeViewColumn("Folder", GTK2.CellRendererText(), "text", 0))
			, 0, 0, 0)
			->add(win->messageview = GTK2.TreeView(win->messages = GTK2.TreeStore(({"string"}))))
		)
	);
	::makewindow();
}

int sig_mainwindow_destroy() {exit(0);}

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
		object mi = GTK2.MenuItem(this_program[attr]);
		win->optmenu->add(mi->show());
		mi->signal_connect("activate", this["opt_" + opt]);
		win->menuitems[opt] = mi;
	}
}
