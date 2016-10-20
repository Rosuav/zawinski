inherit movablewindow;
constant is_subwindow = 0;
constant pos_key = "mainwindow";

void makewindow()
{
	win->mainwindow = GTK2.Window((["title": "Zawinski"]))->add(GTK2.Vbox(0, 0)
		->pack_start(GTK2.MenuBar()
			->add(GTK2.MenuItem("_File")->set_submenu((object)GTK2.Menu()))
			->add(GTK2.MenuItem("_Options")->set_submenu((object)GTK2.Menu()))
			->add(GTK2.MenuItem("_Plugins")->set_submenu((object)GTK2.Menu()))
			->add(GTK2.MenuItem("_Help")->set_submenu((object)GTK2.Menu()))
		,0,0,0)
		->add(GTK2.Hbox(0, 0)
			->pack_start(win->folderview = GTK2.TreeView(win->folders = GTK2.TreeStore(({"string"}))), 0, 0, 0)
			->add(win->messageview = GTK2.TreeView(win->messages = GTK2.TreeStore(({"string"}))))
		)
	);
	::makewindow();
}

int sig_mainwindow_destroy() {exit(0);}
