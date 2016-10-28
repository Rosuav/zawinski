inherit movablewindow;
constant is_subwindow = 0;
constant pos_key = "mainwindow";
constant load_size = 1;
object mainwindow;

//Macro for GTK2.TreeViewColumn that allows multiple property/column pairs
/* Not needed in 8.1 latest - use this if 8.0 compat is needed.
GTK2.TreeViewColumn GTK2TreeViewColumn(string|mapping title_or_props, GTK2.CellRenderer renderer, string property, int col, string|int ... attrs)
{
	object ret = GTK2.TreeViewColumn(title_or_props, renderer, property, col);
	foreach (attrs/2, [string prop, int col]) ret->add_attribute(renderer, prop, col);
	return ret;
}
*/

constant html_tags = ([
	"b": (["weight": GTK2.PANGO_WEIGHT_BOLD]),
	"i": (["style": GTK2.PANGO_STYLE_ITALIC]),
	"a": (["foreground": "blue", "underline": GTK2.PANGO_UNDERLINE_SINGLE]),
]);

void makewindow()
{
	win->menuitems = ([]);
	win->mainwindow = mainwindow = GTK2.Window((["title": "Zawinski"]))->add(GTK2.Vbox(0, 0)
		->pack_start(stock_menu_bar("_Options"), 0, 0, 0)
		->add(GTK2.Hbox(0, 0)
			->pack_start(GTK2.ScrolledWindow()->set_policy(GTK2.POLICY_NEVER, GTK2.POLICY_AUTOMATIC)->add(
				win->folderview = GTK2.TreeView(win->folders = GTK2.TreeStore(({"string", "string", "string"})))
					->set_headers_visible(0)
					->append_column(GTK2.TreeViewColumn("Folder", GTK2.CellRendererText(), "text", 0))
					//Hidden column: IMAP folder name. Consists of the full hierarchy, eg INBOX.Stuff.Old
					//Hidden column: Associated account ("addr")
			), 0, 0, 0)
			->add(GTK2.ScrolledWindow()->set_policy(GTK2.POLICY_AUTOMATIC, GTK2.POLICY_AUTOMATIC)->add(
				win->messageview = GTK2.TreeView(win->messagesort = GTK2.TreeModelSort(
					win->messages = GTK2.TreeStore(({"int", "string", "string", "string", "int", "int", "string"})))
					->set_sort_column_id(4, 1)
				)
					//Hidden column: UID
					->append_column(GTK2.TreeViewColumn("From", GTK2.CellRendererText(), "text", 1, "weight", 5))
					//->append_column(GTK2.TreeViewColumn("To", GTK2.CellRendererText(), "text", 2))
					->append_column(GTK2.TreeViewColumn("Subject", GTK2.CellRendererText(([
						"ellipsize": GTK2.PANGO_ELLIPSIZE_END, "width-chars": 30
					])), "text", 3, "weight", 5))
					//Hidden column: INTERNALDATE as a Unix time (0 for unknown)
					//Hidden column: font weight (derived from read/unread status)
					//Hidden column: lookup key
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
		win->folders->set_row(it, ({parts[-1], fld, addr}));
		parents[fld] = it;
	}
	win->folderview->expand_all();
}

void clear_messages()
{
	win->messages->clear();
}

class show_message(string addr, mapping msg)
{
	inherit movablewindow;
	constant is_subwindow = 0;
	constant pos_key = "show_message";
	constant load_size = 1;
	void create() {::create();}
	MIME.Message plain, html; //0 if there is no part of that type

	string display_one_email(array(string) address)
	{
		/* RFC 3501:
		An address structure is a parenthesized list that describes an
		electronic mail address.  The fields of an address structure
		are in the following order: personal name, [SMTP]
		at-domain-list (source route), mailbox name, and host name.
		*/
		[string name, string route, string mbox, string host] = address;
		if (name && mbox && host) //Common case #1 (name and address)
			return sprintf("%O <%s@%s>", name, mbox, host);
		if (mbox && host) //Common case #2 (address w/o name)
			return sprintf("<%s@%s>", mbox, host);
		//Uncommon case: Some parts are missing.
		return sprintf("%O %O <%s@%s>", name, route, mbox || "NULL", host || "NULL");
	}
	string display_emails(array(array(string)) addresses)
	{
		if (!addresses) return 0;
		switch (sizeof(addresses))
		{
			case 0: return "(none)";
			case 1: return display_one_email(addresses[0]);
			case 2: case 3:
				//For small numbers of addresses, show them all.
				return display_one_email(addresses[*]) * ", ";
			default:
				//For large numbers of addresses, ellipsize.
				//TODO: Return a widget and make it clickable.
				return display_one_email(addresses[..3][*]) * ", " + ", ...";
		}
	}

	void find_text(MIME.Message mime)
	{
		//Look for text/html and text/plain and retain them.
		switch (mime->type)
		{
			case "multipart":
				//We have multiple parts. Recurse.
				foreach (mime->body_parts, MIME.Message part) find_text(part);
				break;
			case "text":
				if (mime->subtype == "plain") plain = mime;
				if (mime->subtype == "html") html = mime;
				break;
			default:
				//Could be an attachment or an inline image.
				//Ignore for now.
		}
	}

	void render_html(GTK2.TextView tv, string html)
	{
		//Instead of processing entities at the top level, it's simpler
		//to process them separately, on data-only sections.
		Parser.HTML entities = Parser.HTML()->add_entities(Parser.html_entities);
		multiset(string) attributes = (<>);
		GTK2.TextBuffer buf = tv->get_buffer();

		mixed attribute(object p, mapping attrs, string tag)
		{
			write("tag %s: %O\n", tag, attrs);
			if (tag[0] == '/') attributes[tag[1..]] = 0;
			else attributes[tag] = 1;
			return ({ });
		}

		mixed data(object p, string txt)
		{
			//TODO: Collapse all whitespace into a single space, instead of trimming externals only
			txt = string_to_utf8(String.trim_all_whites(entities->feed(txt)->read()));
			if (txt != "") buf->insert_with_tags_by_name(buf->get_end_iter(), txt, sizeof(txt), (array)attributes);
			return ({ });
		}

		mixed linebreak(object p, mapping attrs)
		{
			buf->insert_with_tags_by_name(buf->get_end_iter(), "\n\n", 2, (array)attributes);
			return ({ });
		}

		object p = Parser.HTML();
		foreach (html_tags; string tag; mapping styles)
		{
			buf->create_tag(tag, styles);
			p->add_tag(tag, ({attribute, tag}));
			p->add_tag("/"+tag, ({attribute, "/"+tag}));
		}
		foreach ("p br div"/" ", string tag)
			p->add_tag(tag, linebreak);
		p->_set_data_callback(data);
		p->finish(html);
	}

	void makewindow()
	{
		/* RFC 3501:
		The fields of the envelope structure are in the following
		order: date, subject, from, sender, reply-to, to, cc, bcc,
		in-reply-to, and message-id.  The date, subject, in-reply-to,
		and message-id fields are strings.  The from, sender, reply-to,
		to, cc, and bcc fields are parenthesized lists of address
		structures.
		*/
		find_text(MIME.Message(String.trim_all_whites(msg->RFC822)));
		//HACK: Test html-only or text-only with "plain=0;" or "html=0;"
		//TODO: Make the plain-vs-html preference configurable
		MIME.Message showme = html || plain;
		//MIME.Message showme = plain || html;
		if (!showme) error("No text/plain or text/html component in message, cannot display\n");
		//This will 99% of the time be equivalent to utf8_to_string(showme->getdata()),
		//but we do the job properly. Might be worth optimizing for the ASCII case though.
		string content = Charset.decoder(showme->charset)->feed(showme->getdata())->drain();
		mapping env = mkmapping("date subject from sender replyto to cc bcc inreplyto msgid"/" ", msg->ENVELOPE);
		win->mainwindow = GTK2.Window((["title": msg->headers->subject + " - Zawinski"]))->add(GTK2.Vbox(0, 0)
			->pack_start(stock_menu_bar("_Message"), 0, 0, 0)
			->pack_start(GTK2Table(({
				env->from && "From", display_emails(env->from),
				env->to && "To", display_emails(env->to),
				env->cc && "Cc", display_emails(env->cc),
				env->bcc && "Bcc", display_emails(env->bcc), //Usually only on sent mail or drafts
				"Subject", env->subject,
				"Date", env->date,
			})/2, (["xalign": 0.0])), 0, 0, 0)
			->add(GTK2.ScrolledWindow()->add(win->display=MultiLineEntryField()))
		);
		if (showme->subtype == "plain") win->display->set_text(content);
		else render_html(win->display, content);
		::makewindow();
	}

	constant menu_message_unread = "Leave _Unread";
	void message_unread()
	{
		//TODO: Should this close the window or not? Check with the Talldad.
		G->G->connection->mark_unread(addr, msg->key);
		closewindow();
	}
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
		object path = win->messages->get_path(iter);
		msg->rowref = GTK2.TreeRowReference(win->messages, path);
		win->messageview->expand_all()->scroll_to_cell(path);
	}
	//Note that most of this information could be obtained from msg->ENVELOPE, but
	//the full RFC822 headers are necessary in order to get the parenting, so we
	//fetch that and not the envelope.
	win->messages->set_row(win->messages->get_iter(msg->rowref->get_path()), ({
		msg->UID,
		shorten_address(msg->headers->from),
		shorten_address(msg->headers->to),
		msg->headers->subject || "",
		msg->INTERNALDATE && Calendar.dwim_time(msg->INTERNALDATE)->unix_time(),
		has_value(msg->FLAGS, "\\Seen") ? GTK2.PANGO_WEIGHT_NORMAL : GTK2.PANGO_WEIGHT_BOLD,
		msg->key,
	}));
}

void sig_folderview_cursor_changed(object self)
{
	object path = self->get_cursor()->path;
	array info = win->folders->get_row(win->folders->get_iter(path));
	//In theory, we could scan up to get to the top-level entry for this path.
	//In practice, it's easier to retain that info as a hidden column.
	//Is it safe to just save curaddr?? Are there race conditions possible??
	G->G->connection->select_folder(win->curaddr=info[2], info[1]);
}

void sig_messageview_row_activated(object self, object path, object col)
{
	string key = win->messages->get_value(win->messages->get_iter(win->messagesort->convert_path_to_child_path(path)), 6);
	//1) Trigger an asynchronous download of this message
	//2) Open up a new window when the result arrives.
	G->G->connection->fetch_message(win->curaddr, key);
}

constant menu_options_update = "Update code";
void options_update()
{
	int err = G->bootstrap_all();
	if (!err) return; //All OK? Be silent.
	if (string winid = getenv("WINDOWID")) //On some Linux systems we can pop the console up.
		catch (Process.create_process(({"wmctrl", "-ia", winid}))->wait()); //Try, but don't mind errors, eg if wmctrl isn't installed.
	MessageBox(0, GTK2.MESSAGE_ERROR, GTK2.BUTTONS_OK, err + " compilation error(s) - see console", win->mainwindow);
}

constant menu_options_accounts = "Configure accounts";
class options_accounts
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
}
