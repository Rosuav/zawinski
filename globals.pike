void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	if (!G->G->windows)
	{
		GTK2.setup_gtk(G->G->argv);
		G->G->windows = ([]);
	}
	if (!G->G->dns_a) G->G->dns_a=([]); //Two separate caches, for simplicity.
	if (!G->G->dns_aaaa) G->G->dns_aaaa=([]); //0 means unknown or error; ({ }) meeans successful empty response.
}

typedef string(0..127) ascii;
typedef string(0..255) bytes;

//Usage: gtksignal(some_object,"some_signal",handler,arg,arg,arg) --> save that object.
//Equivalent to some_object->signal_connect("some_signal",handler,arg,arg,arg)
//When this object expires, the signal is disconnected, which should gc the function.
//obj should be a GTK2.G.Object or similar.
class gtksignal(object obj)
{
	int signal_id;
	void create(mixed ... args) {if (obj) signal_id=obj->signal_connect(@args);}
	void destroy() {if (obj && signal_id) obj->signal_disconnect(signal_id);}
}

class MessageBox
{
	inherit GTK2.MessageDialog;
	function callback;

	//flags: Normally 0. type: 0 for info, else GTK2.MESSAGE_ERROR or similar. buttons: GTK2.BUTTONS_OK etc.
	void create(int flags,int type,int buttons,string message,GTK2.Window parent,function|void cb,mixed|void cb_arg)
	{
		callback=cb;
		#if constant(COMPAT_MSGDLG)
		//There's some sort of issue in older Pikes (7.8 only) regarding the parent.
		//I'm no longer majorly supporting 7.8 though so I can't be bothered checking details.
		::create(flags,type,buttons,message);
		#else
		::create(flags,type,buttons,message,parent);
		#endif
		signal_connect("response",response,cb_arg);
		show();
	}

	void response(object self,int button,mixed cb_arg)
	{
		self->destroy();
		if (callback) callback(button,cb_arg);
	}
}

//A message box that calls its callback only if the user chooses OK. If you need to do cleanup
//on Cancel, use MessageBox above.
class confirm
{
	inherit MessageBox;
	void create(int flags,string message,GTK2.Window parent,function cb,mixed|void cb_arg)
	{
		::create(flags,GTK2.MESSAGE_WARNING,GTK2.BUTTONS_OK_CANCEL,message,parent,cb,cb_arg);
	}
	void response(object self,int button,mixed cb_arg)
	{
		self->destroy();
		if (callback && button==GTK2.RESPONSE_OK) callback(cb_arg);
	}
}

//Exactly the same as a GTK2.TextView but with additional methods for GTK2.Entry compatibility.
//Do not provide a buffer; create this with no args, and if you need access to the buffer, call
//obj->get_buffer() separately. NOTE: This does not automatically scroll (a GTK2.Entry does). If
//you need scrolling, place this inside a GTK2.ScrolledWindow.
class MultiLineEntryField
{
	#if constant(GTK2.SourceView)
	inherit GTK2.SourceView;
	#else
	inherit GTK2.TextView;
	#endif
	this_program set_text(mixed ... args)
	{
		object buf=get_buffer();
		buf->begin_user_action(); //Permit undo of the set_text operation
		buf->set_text(@args);
		buf->end_user_action();
		return this;
	}
	string get_text()
	{
		object buf=get_buffer();
		return buf->get_text(buf->get_start_iter(),buf->get_end_iter(),0);
	}
	this_program set_position(int pos)
	{
		object buf=get_buffer();
		buf->place_cursor(buf->get_iter_at_offset(pos));
		return this;
	}
	int get_position()
	{
		object buf=get_buffer();
		return buf->get_iter_at_mark(buf->get_insert())->get_offset();
	}
	this_program set_visibility(int state)
	{
		#if !constant(COMPAT_NOPASSWD)
		object buf=get_buffer();
		(state?buf->remove_tag_by_name:buf->apply_tag_by_name)("password", buf->get_start_iter(), buf->get_end_iter());
		#endif
		return this;
	}
}

//GTK2.ComboBox designed for text strings. Has set_text() and get_text() methods.
//Should be able to be used like an Entry.
class SelectBox(array(string) strings)
{
	inherit GTK2.ComboBox;
	void create() {::create(""); foreach (strings,string str) append_text(str);}
	this_program set_text(string txt)
	{
		set_active(search(strings,txt));
		return this;
	}
	string get_text() //Like get_active_text() but will return 0 (not "") if nothing's selected (may not strictly be necessary, but it's consistent with entry fields and such)
	{
		int idx=get_active();
		return (idx>=0 && idx<sizeof(strings)) && strings[idx];
	}
	void set_strings(array(string) newstrings)
	{
		foreach (strings,string str) remove_text(0);
		foreach (strings=newstrings,string str) append_text(str);
	}
}

//Advisory note that this widget should be packed without the GTK2.Expand|GTK2.Fill options
//As of Pike 8.0.2, this could safely be done with wid->set_data(), but it's not
//safe to call get_data() with a keyword that hasn't been set (it'll segfault older Pikes).
//So this works with a multiset instead. Once Pike 7.8 support can be dropped, switch to
//get_data to ensure that loose references are never kept.
multiset(GTK2.Widget) _noexpand=(<>);
GTK2.Widget noex(GTK2.Widget wid) {_noexpand[wid]=1; return wid;}

/** Create a GTK2.Table based on a 2D array of widgets
 * The contents will be laid out on the grid. Put a 0 in a cell to span
 * across multiple cells (the object preceding the 0 will span both cells).
 * Use noex(widget) to make a widget not expand (usually will want to do
 * this for a whole column). Shortcut: Labels can be included by simply
 * including a string - it will be turned into a label, expansion off, and
 * with options as set by the second parameter (if any).
 * A leading 0 on a line will be quietly ignored, not resulting in any
 * spanning. Recommended for unlabelled objects in a column of labels.
 */
GTK2.Table GTK2Table(array(array(string|GTK2.Widget)) contents,mapping|void label_opts)
{
	if (!label_opts) label_opts=([]);
	GTK2.Table tb=GTK2.Table(sizeof(contents[0]),sizeof(contents),0);
	foreach (contents;int y;array(string|GTK2.Widget) row) foreach (row;int x;string|GTK2.Widget obj) if (obj)
	{
		int opt=0;
		if (stringp(obj)) {obj=GTK2.Label(label_opts+(["label":obj])); opt=GTK2.Fill;}
		else if (_noexpand[obj]) _noexpand[obj]=0; //Remove it from the set so we don't hang onto references to stuff we don't need
		else opt=GTK2.Fill|GTK2.Expand;
		int xend=x+1; while (xend<sizeof(row) && !row[xend]) ++xend; //Span cols by putting 0 after the element
		tb->attach(obj,x,xend,y,y+1,opt,opt,1,1);
	}
	return tb;
}

//Derivative of GTK2Table above, specific to a two-column layout. Takes a 1D array.
//This is the most normal way to lay out labelled objects - alternate string labels and objects, or use CheckButtons without labels.
//The labels will be right justified.
GTK2.Table two_column(array(string|GTK2.Widget) contents) {return GTK2Table(contents/2,(["xalign":1.0]));}

//End of generic GTK utility classes/functions

//Generic window handler. If a plugin inherits this, it will normally show the window on startup and
//keep it there, though other patterns are possible. For instance, the window might be hidden when
//there's nothing useful to show; although this can cause unnecessary flicker, and so should be kept
//to a minimum (don't show/hide/show/hide in rapid succession). Note that this (via a subclass)
//implements the core window, not just plugin windows, as there's no fundamental difference.
//Transient windows (eg popups etc) are best implemented with nested classes - see usage of configdlg
//('inherit configdlg') for the most common example of this.
class window
{
	constant provides="window";
	mapping(string:mixed) win=([]);
	constant is_subwindow=1; //Set to 0 to disable the taskbar/pager hinting

	//Replace this and call the original after assigning to win->mainwindow.
	void makewindow() {if (win->accelgroup) win->mainwindow->add_accel_group(win->accelgroup);}

	//Stock item creation: Close button. Calls closewindow(), same as clicking the cross does.
	GTK2.Button stock_close()
	{
		return win->stock_close=GTK2.Button((["use-stock":1,"label":GTK2.STOCK_CLOSE]))
			->add_accelerator("clicked",stock_accel_group(),0xFF1B,0,0); //Esc as a shortcut for Close
	}

	//Stock item creation: Menu bar. Normally will want to be packed_start(,0,0,0) into a Vbox.
	GTK2.MenuBar stock_menu_bar(string ... menus)
	{
		win->stock_menu_bar = GTK2.MenuBar();
		win->menus = ([]); win->menuitems = ([]);
		foreach (menus, string menu)
		{
			string key = lower_case(menu) - "_"; //Callables to be placed in this menu start with this key.
			win->stock_menu_bar->add(GTK2.MenuItem(menu)->set_submenu(win->menus[key] = (object)GTK2.Menu()));
		}
		return win->stock_menu_bar;
	}

	//Stock "item" creation: AccelGroup. The value of this is that it will only ever create one.
	GTK2.AccelGroup stock_accel_group()
	{
		if (!win->accelgroup)
		{
			win->accelgroup = GTK2.AccelGroup();
			if (win->mainwindow) win->mainwindow->add_accel_group(win->accelgroup);
		}
		return win->accelgroup;
	}

	//Subclasses should call ::dosignals() and then append to to win->signals. This is the
	//only place where win->signals is reset. Note that it's perfectly legitimate to have
	//nulls in the array, as exploited here.
	void dosignals()
	{
		//NOTE: This does *not* use += here - this is where we (re)initialize the array.
		win->signals = ({
			gtksignal(win->mainwindow,"delete_event",closewindow),
			win->stock_close && gtksignal(win->stock_close,"clicked",closewindow),
		});
		collect_signals("sig_", win);
		if (win->stock_menu_bar)
		{
			multiset(string) seen = (<>);
			foreach (sort(indices(this_program)), string attr)
			{
				if (sscanf(attr, "menu_%s_%s", string menu, string item) && this[menu + "_" + item])
				{
					object m = win->menus[menu];
					if (!m) error("%s has no corresponding menu [try%{ %s%}]\n", attr, indices(win->menus));
					if (object old = win->menuitems[attr]) old->destroy();
					array|string info = this[attr];
					GTK2.MenuItem mi = arrayp(info)
						? GTK2.MenuItem(info[0])->add_accelerator("activate", stock_accel_group(), info[1], info[2], GTK2.ACCEL_VISIBLE)
						: GTK2.MenuItem(info); //String constants are just labels; arrays have accelerator key and modifiers.
					m->add(mi->show());
					win->signals += ({gtksignal(mi, "activate", this[menu + "_" + item])});
					win->menuitems[attr] = mi;
					seen[attr] = 1;
				}
			}
			//Having marked off everything we've added/updated, remove the left-overs.
			foreach (win->menuitems - seen; string key;)
				m_delete(win->menuitems, key)->destroy();
		}
	}

	//NOTE: prefix *must* be a single 'word' followed by an underscore. Stuff breaks otherwise.
	void collect_signals(string prefix, mapping(string:mixed) searchme,mixed|void arg)
	{
		foreach (indices(this),string key) if (has_prefix(key,prefix) && callablep(this[key]))
		{
			//Function names of format sig_x_y become a signal handler for win->x signal y.
			//(Note that classes are callable, so they can be used as signal handlers too.)
			//This may pose problems, as it's possible for x and y to have underscores in
			//them, so we scan along and find the shortest such name that exists in win[].
			//If there's none, ignore the callable (currently without any error or warning,
			//despite the explicit prefix). This can create ambiguities, but only in really
			//contrived situations, so I'm deciding not to care. :)
			array parts=(key/"_")[1..];
			int b4=(parts[0]=="b4"); if (b4) parts=parts[1..]; //sig_b4_some_object_some_signal will connect _before_ the normal action
			for (int i=0;i<sizeof(parts)-1;++i) if (mixed obj=searchme[parts[..i]*"_"])
			{
				if (objectp(obj) && callablep(obj->signal_connect))
				{
					win->signals+=({gtksignal(obj,parts[i+1..]*"_",this[key],arg,UNDEFINED,b4)});
					break;
				}
			}
		}
	}
	void create(string|void name)
	{
		if (name) sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) {if (G->G->windows[name]) win=G->G->windows[name]; else G->G->windows[name]=win;}
		win->self=this;
		if (!win->mainwindow) makewindow();
		if (is_subwindow) win->mainwindow->set_transient_for(win->_parentwindow || G->G->window->mainwindow);
		win->mainwindow->set_skip_taskbar_hint(is_subwindow)->set_skip_pager_hint(is_subwindow)->show_all();
		dosignals();
	}
	void showwindow()
	{
		if (!win->mainwindow) {makewindow(); dosignals();}
		win->mainwindow->set_no_show_all(0)->show_all();
	}
	int hidewindow()
	{
		win->mainwindow->hide();
		return 1; //Simplify anti-destruction as "return hidewindow()". Note that this can make updating tricky - be aware of this.
	}
	int closewindow()
	{
		win->mainwindow->destroy();
		destruct(win->mainwindow);
		return 1;
	}
}

//Subclass of window that handles save/load of position automatically.
class movablewindow
{
	inherit window;
	constant pos_key=0; //(string) Set this to the persist[] key in which to store and from which to retrieve the window pos
	constant load_size=0; //If set to 1, will attempt to load the size as well as position. (It'll always be saved.)
	constant provides=0;

	void makewindow()
	{
		if (array pos=persist[pos_key])
		{
			if (sizeof(pos)>3 && load_size) win->mainwindow->set_default_size(pos[2],pos[3]);
			win->x=1; call_out(lambda() {m_delete(win,"x");},1);
			win->mainwindow->move(pos[0],pos[1]);
		}
		::makewindow();
	}

	void sig_b4_mainwindow_configure_event()
	{
		if (!has_index(win,"x")) call_out(savepos,0.1);
		mapping pos=win->mainwindow->get_position(); win->x=pos->x; win->y=pos->y;
	}

	void savepos()
	{
		if (!pos_key) {werror("%% Assertion failed: Cannot save position without pos_key set!\n"); return;} //Shouldn't happen.
		mapping sz=win->mainwindow->get_size();
		persist[pos_key]=({m_delete(win,"x"),m_delete(win,"y"),sz->width,sz->height});
	}
}

//Base class for a configuration dialog. Permits the setup of anything where you
//have a list of keyworded items, can create/retrieve/update/delete them by keyword.
//It may be worth breaking out some of this code into a dedicated ListBox class
//for future reuse. Currently I don't actually need that for Gypsum, but it'd
//make a nice utility class for other programs.
//NOTE: This class may end up becoming the legacy compatibility class, with a new
//and simpler one (under a new name) being created, thus freeing current code from
//the baggage of backward compatibility - which this has a lot of. I could then
//deprecate this class (with no intention of removal) and start fresh.
class configdlg
{
	inherit window;
	//Provide me...
	mapping(string:mixed) windowprops=(["title":"Configure"]);
	mapping(string:mapping(string:mixed)) items; //Will never be rebound. Will generally want to be an alias for a better-named mapping, or something out of persist[] (and see persist_key)
	void save_content(mapping(string:mixed) info) { } //Retrieve content from the window and put it in the mapping.
	void load_content(mapping(string:mixed) info) { } //Store information from info into the window
	void delete_content(string kwd,mapping(string:mixed) info) { } //Delete the thing with the given keyword.
	string actionbtn; //(DEPRECATED) If set, a special "action button" will be included, otherwise not. This is its caption.
	void action_callback() { } //(DEPRECATED) Callback when the action button is clicked (provide if actionbtn is set)
	constant allow_new=1; //Set to 0 to remove the -- New -- entry; if omitted, -- New -- will be present and entries can be created.
	constant allow_delete=1; //Set to 0 to disable the Delete button (it'll always be visible though)
	constant allow_rename=1; //Set to 0 to ignore changes to keywords
	constant strings=({ }); //Simple string bindings - see plugins/README
	constant ints=({ }); //Simple integer bindings, ditto
	constant bools=({ }); //Simple boolean bindings (to CheckButtons), ditto
	constant labels=({ }); //Labels for the above
	/* PROVISIONAL: Instead of using all of the above four, use a single list of
	tokens which gets parsed out to provide keyword, label, and type.
	constant elements=({"kwd:Keyword", "name:Name", "?state:State of Being", "#value:Value","+descr:Description"});
	If the colon is omitted, the keyword will be the first word of the lowercased name, so this is equivalent:
	constant elements=({"kwd:Keyword", "Name", "?State of Being", "#Value", "+descr:Description"});
	In most cases, this and persist_key will be all you need to set.
	Still figuring out a good way to allow a SelectBox. Currently messing with "@name:lbl",({opt,opt,opt}) which
	is far from ideal.
	This is eventually going to be the primary way to do things, but it's currently unpledged to permit changes.
	In fact, I'd say that it's _now_ (20160809) the primary way to do things, but I haven't yet deprovisionalized
	it in case I want to make changes (esp to the SelectBox and Notebook APIs). There's already way too much
	cruft in this class to risk letting even more in.
	*/
	constant elements=({ });
	constant persist_key=0; //(string) Set this to the persist[] key to load items[] from; if set, persist will be saved after edits.
	constant descr_key=0; //(string) Set this to a key inside the info mapping to populate with descriptions.
	string selectme; //If this contains a non-null string, it will be preselected.
	//... end provide me.
	mapping defaults = ([]); //TODO: Figure out if any usage of defaults needs the value to be 'put back', or not be a string, or anything.
	string last_selected; //Set when something is loaded. Unless the user renames the thing, will be equal to win->kwd->get_text().

	void create(string|void name)
	{
		if (persist_key && !items) items=persist->setdefault(persist_key,([]));
		::create(!is_subwindow && name); //Unless we're a main window, pass on no args to the window constructor - all configdlgs are independent
	}

	//Return the keyword of the selected item, or 0 if none (or new) is selected
	string selecteditem()
	{
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		return (kwd!="-- New --") && kwd; //TODO: Recognize the "New" entry by something other than its text
	}

	void sig_pb_save_clicked()
	{
		string oldkwd=selecteditem();
		string newkwd=allow_rename?win->kwd->get_text():oldkwd;
		if (newkwd=="") return; //Blank keywords currently disallowed
		if (newkwd=="-- New --") return; //Since selecteditem() currently depends on "-- New --" being the 'New' entry, don't let it be used anywhere else.
		mapping info;
		if (allow_rename) info=m_delete(items,oldkwd); else info=items[oldkwd];
		if (!info)
			if (allow_new) info=([]); else return;
		if (allow_rename) items[newkwd]=info;
		foreach (win->real_strings,string key) info[key]=win[key]->get_text();
		foreach (win->real_ints,string key) info[key]=(int)win[key]->get_text();
		foreach (win->real_bools,string key) info[key]=(int)win[key]->get_active();
		save_content(info);
		if (persist_key) persist->save();
		[object iter,object store]=win->sel->get_selected();
		if (newkwd!=oldkwd)
		{
			if (!oldkwd) win->sel->select_iter(iter=store->insert_before(win->new_iter));
			store->set_value(iter,0,newkwd);
		}
		if (descr_key && info[descr_key]) store->set_value(iter,1,info[descr_key]);
		sig_sel_changed();
	}

	void sig_pb_delete_clicked()
	{
		if (!allow_delete) return; //The button will be insensitive anyway, but check just to be sure.
		[object iter,object store]=win->sel->get_selected();
		string kwd=iter && store->get_value(iter,0);
		if (!kwd) return;
		store->remove(iter);
		foreach (win->real_strings+win->real_ints,string key) win[key]->set_text("");
		foreach (win->real_bools,string key) win[key]->set_active(0);
		delete_content(kwd,m_delete(items,kwd));
		if (persist_key) persist->save();
	}

	int ischanged()
	{
		string kwd = last_selected; //NOT using selecteditem() here - compare against the last loaded state.
		if (!kwd) return 0; //For now, assume that moving off "-- New --" doesn't need to prompt. TODO.
		if (allow_rename && win->kwd->get_text() != kwd) return 1;
		mapping info = items[kwd] || ([]);
		foreach (win->real_strings, string key)
			if ((info[key] || defaults[key] || "") != win[key]->get_text()) return 1;
		foreach (win->real_ints, string key)
			if ((int)(info[key] || defaults[key]) != (int)win[key]->get_text()) return 1;
		foreach (win->real_bools, string key)
			if ((int)info[key] != (int)win[key]->get_active()) return 1;
		return 0;
	}

	void selchange_response(int btn, string kwd)
	{
		string btnname = ([GTK2.RESPONSE_APPLY: "Save", GTK2.RESPONSE_REJECT: "Discard", GTK2.RESPONSE_CANCEL: "Cancel"])[btn] || (string)btn;
		m_delete(win, "save_prompt");
		if (btn == GTK2.RESPONSE_APPLY) sig_pb_save_clicked();
		else if (btn != GTK2.RESPONSE_REJECT) return; //Cancel or closing the window leaves us where we were.
		win->save_prompt = "DISCARD";
		select_keyword(kwd);
		m_delete(win, "save_prompt");
	}

	void sig_sel_changed()
	{
		if (win->save_prompt && win->save_prompt != "DISCARD") return;
		string kwd = selecteditem();
		if (win->save_prompt != "DISCARD" && ischanged())
		{
			win->save_prompt = "PENDING";
			object dlg = MessageBox(0, GTK2.MESSAGE_WARNING, 0, "Unsaved changes will be lost.",
				win->mainwindow, selchange_response, kwd);
			dlg->add_button("_Save", GTK2.RESPONSE_APPLY);
			dlg->add_button("_Discard", GTK2.RESPONSE_REJECT);
			dlg->add_button("_Cancel", GTK2.RESPONSE_CANCEL);
			select_keyword(last_selected);
			return;
		}
		last_selected = kwd;
		mapping info=items[kwd] || ([]);
		if (win->kwd) win->kwd->set_text(kwd || "");
		foreach (win->real_strings,string key) win[key]->set_text((string)(info[key] || defaults[key] || ""));
		foreach (win->real_ints,string key) win[key]->set_text((string)(info[key] || defaults[key]));
		foreach (win->real_bools,string key) win[key]->set_active((int)info[key]);
		load_content(info);
	}

	void makewindow()
	{
		win->real_strings = strings; win->real_ints = ints; win->real_bools = bools; //Migrate the constants
		object ls=GTK2.ListStore(({"string","string"}));
		//TODO: Break out the list box code into a separate object - it'd be useful eg for zoneinfo.pike.
		foreach (sort(indices(items)),string kwd)
		{
			object iter=ls->append();
			ls->set_value(iter,0,kwd);
			if (string descr=descr_key && items[kwd][descr_key]) ls->set_value(iter,1,descr);
		}
		if (allow_new) ls->set_value(win->new_iter=ls->append(),0,"-- New --");
		//TODO: Have a way to customize this a little (eg a menu bar) without
		//completely replacing this function.
		win->mainwindow=GTK2.Window(windowprops)
			->add(GTK2.Vbox(0,10)
				->add(GTK2.Hbox(0,5)
					->add(win->list=GTK2.TreeView(ls) //All I want is a listbox. This feels like *such* overkill. Oh well.
						->append_column(GTK2.TreeViewColumn("Item",GTK2.CellRendererText(),"text",0))
						->append_column(GTK2.TreeViewColumn("",GTK2.CellRendererText(),"text",1))
					)
					->add(GTK2.Vbox(0,0)
						->add(make_content())
						->pack_end(
							(actionbtn?GTK2.HbuttonBox()
							->add(win->pb_action=GTK2.Button((["label":actionbtn,"use-underline":1])))
							:GTK2.HbuttonBox())
							->add(win->pb_save=GTK2.Button((["label":"_Save","use-underline":1])))
							->add(win->pb_delete=GTK2.Button((["label":"_Delete","use-underline":1,"sensitive":allow_delete])))
						,0,0,0)
					)
				)
				->add(win->buttonbox=GTK2.HbuttonBox()->pack_end(stock_close(),0,0,0))
			);
		win->sel=win->list->get_selection(); win->sel->select_iter(win->new_iter||ls->get_iter_first()); sig_sel_changed();
		::makewindow();
		if (stringp(selectme)) select_keyword(selectme) || (win->kwd && win->kwd->set_text(selectme));
	}

	//Generate a widget collection from either the constant or migration mode
	array(string|GTK2.Widget) collect_widgets(array|void elem, int|void noreset)
	{
		array objects = ({ });
		//Clear the arrays only if we're not recursing.
		if (!noreset) win->real_strings = win->real_ints = win->real_bools = ({ });
		elem = elem || elements; if (!sizeof(elem)) elem = migrate_elements();
		string next_obj_name = 0;
		foreach (elem, mixed element)
		{
			if (next_obj_name)
			{
				if (arrayp(element))
					objects += ({win[next_obj_name] = SelectBox(element)});
				else
					error("Assertion failed: SelectBox without element array\n");
				next_obj_name = 0;
				continue;
			}
			if (mappingp(element))
			{
				//EXPERIMENTAL: A mapping creates a notebook.
				object nb = GTK2.Notebook();
				foreach (sort(indices(element)), string tabtext)
					nb->append_page(
						//Tab contents: Recursively collect widgets from the given array.
						two_column(collect_widgets(element[tabtext], 1)),
						//Tab text comes from the mapping key.
						GTK2.Label(tabtext)
					);
				objects += ({nb, 0});
				continue;
			}
			sscanf(element, "%1[?#+'@!*]%s", string type, element);
			sscanf(element, "%s=%s", element, string dflt); //NOTE: I'm rather worried about collisions here. This is definitely PROVISIONAL.
			sscanf(element, "%s:%s", string name, string lbl);
			if (!lbl) sscanf(lower_case(lbl = element)+" ", "%s ", name);
			if (dflt) defaults[name] = dflt;
			switch (type)
			{
				case "?": //Boolean
					win->real_bools += ({name});
					objects += ({0,win[name]=noex(GTK2.CheckButton(lbl))});
					break;
				case "#": //Integer
					win->real_ints += ({name});
					objects += ({lbl, win[name]=noex(GTK2.Entry())});
					break;
				case 0: //String
				case "*": //Password
					win->real_strings += ({name});
					objects += ({lbl, win[name]=noex(GTK2.Entry())});
					if (type == "*") win[name]->set_visibility(0);
					break;
				case "+": //Multi-line text
					win->real_strings += ({name});
					objects += ({GTK2.Frame(lbl)->add(
						win[name]=MultiLineEntryField()->set_wrap_mode(GTK2.WRAP_WORD_CHAR)->set_size_request(225,70)
					),0});
					break;
				case "'": //Descriptive text
				{
					//Names apply to labels only if they consist entirely of lower-case ASCII letters.
					//Otherwise, the label has no name (even if it contains a colon).
					sscanf(element, "%[a-z]:%s", string lblname, string lbltext);
					//This looks a little odd, but it does work. If parsing is successful, we have
					//a name to save under; otherwise, sscanf will have put the text into lblname,
					//so we use that as the label *text*, and it has no name.
					object obj = noex(GTK2.Label(lbltext || element)->set_line_wrap(1));
					objects += ({obj, 0});
					if (lbltext) win[lblname] = obj;
					break;
				}
				case "@": //Drop-down
				{
					//Special case: Integer drop-downs are marked with "@#".
					if (name[0] == '#') win->real_ints += ({name=name[1..]});
					else win->real_strings += ({name});
					objects += ({lbl}); next_obj_name = name; //Object creation happens next iteration
					break;
				}
				case "!": //Button
				{
					//Buttons don't get any special load/save action.
					//Normally you'll attach a clicked event to them.
					//TODO: Put consecutive button elements into the same button box
					objects += ({GTK2.HbuttonBox()->add(win[name] = GTK2.Button((["label": lbl, "use-underline": 1]))), 0});
					break;
				}
			}
		}
		win->real_strings -= ({"kwd"});
		return objects;
	}

	//Iterates over labels, applying them to controls in this order:
	//1) win->kwd, if allow_rename is not zeroed
	//2) strings, creating Entry()
	//3) ints, ditto
	//4) bools, creating CheckButton()
	//5) strings, if marked to create MultiLineEntryField()
	//6) Descriptive text underneath
	//Not yet supported: Anything custom, eg insertion or reordering;
	//any other widget types eg SelectBox.
	array(string) migrate_elements()
	{
		array stuff = ({ });
		array atend = ({ });
		Iterator lbl = get_iterator(labels);
		if (!lbl) return stuff;
		if (allow_rename)
		{
			stuff += ({"kwd:"+lbl->value()});
			if (!lbl->next()) return stuff;
		}
		foreach (strings+ints, string name)
		{
			string desc=lbl->value();
			if (desc[0]=='\n') //Hack: Multiline fields get shoved to the end. Hack is not needed if elements[] is used instead - this is recommended.
				atend += ({sprintf("+%s:%s",name,desc[1..])});
			else
				stuff += ({sprintf("%s:%s",name,desc)});
			if (!lbl->next()) return stuff+atend;
		}
		foreach (bools, string name)
		{
			stuff += ({sprintf("?%s:%s",name,lbl->value())});
			if (!lbl->next()) return stuff+atend;
		}
		stuff += atend; //Now grab any multiline string fields
		//Finally, consume the remaining entries making text. There'll most
		//likely be zero or one of them.
		foreach (lbl;;string text)
			stuff += ({"'"+text});
		return stuff;
	}

	//Create and return a widget (most likely a layout widget) representing all the custom content.
	//If allow_rename (see below), this must assign to win->kwd a GTK2.Entry for editing the keyword;
	//otherwise, win->kwd is optional (it may be present and read-only (and ignored on save), or
	//it may be a GTK2.Label, or it may be omitted altogether).
	//By default, makes a two_column based on collect_widgets. It's easy to override this to add some
	//additional widgets before or after the ones collect_widgets creates.
	GTK2.Widget make_content()
	{
		return two_column(collect_widgets());
	}

	//Attempt to select the given keyword - returns 1 if found, 0 if not
	int select_keyword(string kwd)
	{
		object ls=win->list->get_model();
		object iter=ls->get_iter_first();
		do
		{
			if (ls->get_value(iter,0)==kwd)
			{
				win->sel->select_iter(iter); sig_sel_changed();
				return 1;
			}
		} while (ls->iter_next(iter));
		return 0;
	}

	void dosignals()
	{
		::dosignals();
		if (actionbtn) win->signals+=({gtksignal(win->pb_action,"clicked",action_callback)});
	}
}

//Look up some sort of name and return one or more IP addresses
class DNS(string hostname,function callback)
{
	//NOTE: This would be more idiomatically spelled as "mixed ... cbargs" above, rather
	//than collecting them up in create(); but in current Pikes (as of 20150827) this is
	//not working. Until it's fixed _and_ the patch makes its way into all the Pikes I
	//support, it's safer to just use the non-idiomatic explicit form.
	array cbargs;
	//Note that async_dual_client would probably be better, but only marginally, so since
	//it isn't available on all Pikes, I'll stick with UDP-only. TCP is only of value for
	//large responses, and we aren't expecting any such here (though it is possible).
	object cli=Protocols.DNS.async_client();

	array(string) ips=({ }); //May be mutated by the callback; will only ever be appended to, here.
	int pending; //If this is nonzero, the callback will be called again before destruction - possibly with more IPs (but possibly not)

	//Possible bug sighted 20160330 - a DNS lookup that ought to have succeeded was failing.
	//Cause uncertain. The cache expired and lookups began working again. Monitor.
	void dnsresponse(string domain,mapping resp)
	{
		/* CACHING [one of the hardest problems in computing]

		For simplicity, don't bother caching negative responses. If we
		get asked again for something that failed, it's quite possibly
		because network settings have changed and there's a chance it
		will now succeed.

		NOTE: If we have a positive response for one protocol, it will
		be used for future lookups, ignoring the other protocol. For
		example, if we look up minstrelhall.com and get 203.214.67.43
		and no AAAA records, we use the 3600 TTL from the A record as
		an indication that we shouldn't bother asking for AAAA records
		for the next hour. Forcing IPv6 will retry the query, but other
		than that, IPv6 will be ignored.

		Note that technically there can be multiple different TTLs on
		different records of the same type. In practice this will be a
		rarity, so we just take the lowest TTL from all answers and
		apply that to all of them. Simpler that way :)

		Note that we depend on upstream DNS not sending us superfluous responses. But
		we'd depend on them to not send us outright forged responses anyway, so that's
		not a big deal. If a server sends back a CNAME and a corresponding A/AAAA, we'll
		get the right address. TODO: Properly handle CNAMEs, including firing off other
		requests. Easiest to put all answers into the cache, then attempt to pull from
		the cache to get our actual response. Which means stuffing the cache based on
		resp->an[*]->name, not the provided domain.

		TODO: Is this getting incorrect results if additional records are sent? CHECK ME!
		TODO: Report more useful information on failure, eg distinguish NXDOMAIN from
		an absence of records and from timeouts.
		TODO: What should happen on SERVFAIL or other responses?
		*/
		if (resp && resp->an)
		{
			array ans = (resp->an->a + resp->an->aaaa) - ({0});
			mapping m = (resp->qd[0]->type==Protocols.DNS.T_AAAA) ? G->G->dns_aaaa : G->G->dns_a;
			m[domain] = ans;
			call_out(m_delete, min(@resp->an->ttl), m, domain);
			ips += ans;
		}
		--pending;
		callback(this,@cbargs);
	}

	void create(mixed ... args)
	{
		cbargs=args; //See above, can't be done the clean way.
		//TODO: What should be done if connection/protocol changes and we
		//have cached info? Should the cache retain A and AAAA records
		//separately, and proceed with the two parts independently?
		string prot=persist["connection/protocol"];
		//IP address literals get "resolved" instantly. And if the user requested direct connection attempts, same.
		//Note that direct connection attempts will normally result in synchronous DNS lookups. This will lag out the main
		//thread, and thus cause distinctly unpleasant problems on timeouts. But if you want it, go for it.
		if (prot=="*" || sscanf(hostname,"%d.%d.%d.%d",int q,int w,int e,int r)==4 || Protocols.IPv6.parse_addr(hostname))
		{
			ips=({hostname});
			call_out(callback,0,this,@cbargs); //The callback is always queued on the backend rather than being called synchronously.
			return;
		}
		//Check for cached responses. Normally, this will find either neither or both, but it's
		//possible it'll find just one, eg if there's a query currently in flight. This will
		//result in a partial response being given as if it were the entire; this is expected
		//to be rare (it'd happen if a DNS server is way slower responding to AAAA requests than
		//to A requests, or something like that), and will clear itself up once the other cache
		//gets populated (by the original request).
		array cache4 = G->G->dns_a[hostname];
		array cache6 = G->G->dns_aaaa[hostname];
		if (cache4 || cache6) {ips = cache4 + (cache6||({ })); call_out(callback, 0, this, @cbargs); return;}
		if (prot!="6") {++pending; cli->do_query(hostname, Protocols.DNS.C_IN, Protocols.DNS.T_A,    dnsresponse);}
		if (prot!="4") {++pending; cli->do_query(hostname, Protocols.DNS.C_IN, Protocols.DNS.T_AAAA, dnsresponse);}
	}

	string _sprintf(int type) {return type=='O' && sprintf("DNS(%O -> %d/({%{%O,%}}))",hostname,pending,ips);}
}

//Establish a socket connection to a specified host/port
//The callback will be called with either a socket object or 0.
//Connections will be attempted to all available IP addresses
//for the specified host, in sequence.
//The callback receives three possible first arguments: an open
//socket (indicating success), a string (indicating progress),
//or 0 (indicating failure). The strings are human-readable.
//Note that the zero indicates complete failure, rather than a
//single failed connection; if no A/AAAA records are returned,
//or if multiple are and they've all been tried, the result is
//the same as the "classic" case of one IP address and a failed
//connection.

//If connections fail for different reasons, this information is
//lost. Only the one most recent socket connection errno is kept;
//in the common case where there is only one IP address for the
//host name, this is fine, but if there are both IPv4 and IPv6
//addresses, it's possible that an interesting error on the IPv4
//will be ousted by the uninteresting error that this computer has
//no IPv6 routing. It may be necessary to make errno into an array.
class establish_connection(string hostname,int port,function callback)
{
	object sock;
	object dns;
	array cbargs;
	int errno; //If 0, no socket connections have failed - maybe it was DNS that failed instead.
	string data_rcvd = "";

	void cancel() {callback=0;} //Prevent further calls to the callback (eg if the user requests cancellation)
	void connected()
	{
		if (!sock) return;
		if (!sock->is_open() || !sock->query_address()) {sock=0; tryconn(); return;} //Actually a failure, not success.
		callback(sock, @cbargs);
		cancel();
	}

	//Having *something*, anything, as a socket-read callback seems to make the socket-disconnect
	//callback functional. HUH?!? So we have to snapshot the text for the caller, making this a
	//bit like the way TCP fast-open works.
	void readable(mixed id,bytes data) {data_rcvd += data;}
	void connfailed() {errno = sock->errno(); sock = 0; tryconn();}

	void tryconn()
	{
		if (sock || !callback) return;
		if (!sizeof(dns->ips)) {if (!dns->pending) callback(0,@cbargs); return;} //If we've run out of addresses to try, connection has failed. Otherwise wait for more DNS.
		[string ip,dns->ips]=Array.shift(dns->ips);
		callback("Connecting to "+ip+"...", @cbargs); if (!callback) return;
		sock=Stdio.File(); sock->open_socket();
		sock->set_nonblocking(readable,connected,connfailed);
		if (mixed ex=catch {sock->connect(ip,port);})
		{
			callback("Exception in connection: "+describe_error(ex), @cbargs);
			sock=0; tryconn(); //I doubt this will happen repeatedly (and definitely not infinitely), so just recurse. (TBH Pike probably recognizes this as a tail call anyway.)
		}
	}

	void create(mixed ... args) {cbargs=args; dns=DNS(hostname,tryconn);} //As above. Note that initializing dns at its declaration would do it before hostname is set.
}
