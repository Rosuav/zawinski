inherit movablewindow;
constant is_subwindow = 0;
constant pos_key = "mainwindow";
constant load_size = 1;

void makewindow()
{
	win->menuitems = ([]);
	win->mainwindow = GTK2.Window((["title": "Zawinski"]))->add(GTK2.Vbox(0, 0)
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
	object inbox = win->folders->append();
	win->folders->set_row(inbox, ({"chrisa@kepl.com.au"}));
	win->folders->set_row(win->folders->append(inbox), ({"INBOX"}));
	win->folderview->expand_all();
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

void create(string name)
{
	::create(name);
	foreach (indices(this_program), string attr) if (sscanf(attr, "options_%s", string opt) && this["opt_" + opt])
	{
		if (object old = win->menuitems[name]) old->destroy();
		object mi = GTK2.MenuItem(this_program[attr]);
		win->optmenu->add(mi->show());
		mi->signal_connect("activate", this["opt_" + opt]);
		win->menuitems[name] = mi;
	}
}
