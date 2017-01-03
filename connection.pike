mapping(string:mixed) connections = ([]);

void poll()
{
	foreach (connections; string addr; mapping conn)
		send(conn, "a noop\r\n");
}

//Call this to update the folder list. Currently happens on login;
//can also be called in response to a user-initiated refresh, on a
//timer, or after getting some sort of folder error.
void getfolders(mapping conn)
{
	conn->folders = (<>);
	send(conn, "folders list \"\" *\r\n");
}

void select_folder(string addr, string folder)
{
	mapping conn = connections[addr];
	if (!conn) return;
	send(conn, "fldselect select " + folder + "\r\n");
}

void response_fldselect(mapping conn, bytes line)
{
	conn->message_cache = ([]);
	G->G->window->clear_messages();
	send(conn, "a uid search all\r\n");
}

void response_UNTAGGED_SEARCH(mapping conn, bytes line)
{
	array(int) uids = (array(int))(line/" ");
	send(conn, sprintf("a uid fetch %d:%d (flags internaldate rfc822.header)\r\n", uids[0], uids[-1]));
}

void response_auth(mapping conn, bytes line)
{
	if (has_prefix(line, "OK")) getfolders(conn);
	else send(conn, "quit logout\r\n");
}

void response_UNTAGGED_LIST(mapping conn, bytes line)
{
	sscanf(line, "(%s) %O %O", string flags, string sep, string fld);
	if (sep != ".") fld = replace(fld, sep, "."); //I doubt this will happen.
	if (conn->folders) conn->folders[fld] = 1;
}

mixed parse_imap(mapping conn, Stdio.Buffer buf)
{
	if (!sizeof(buf)) return UNDEFINED; //Shouldn't happen.
	switch (buf[0]) //NOTE: Peeks, doesn't remove this first octet
	{
		case '(':
		{
			//List. Recurse.
			array ret = ({ });
			buf->consume(1);
			while (buf[0] != ')') //Will throw if the close paren isn't found
			{
				ret += ({parse_imap(conn, buf)});
				buf->sscanf("%[ ]"); //Discard whitespace (maybe other ws too?)
			}
			buf->consume(1);
			return ret;
		}
		case '"':
			//Quoted string
			return buf->match("%O");
		case '\0':
		{
			//String literal marker
			buf->consume(1);
			[string ret, conn->string_literals] = Array.shift(conn->string_literals);
			return ret;
		}
		default:
		{
			//I think this will correctly match an ATOM_CHAR (or rather, that it will
			//correctly reject the atom_specials).
			string data = buf->match("%[^(){\1- *%]"); //Yes, that's "\1- " - control characters and space are forbidden
			if (data == (string)(int)data) return (int)data; //Integer
			return data != "NIL" && data; //Atom; NIL becomes 0.
		}
	}
}

//Recursively RFC-1522-decode an array of text, arbitrarily nested.
string|array|int(0..0) decode_all(string|array|int(0..0) txt)
{
	if (stringp(txt)) return MIME.decode_words_text_remapped(txt);
	return txt && decode_all(txt[*]);
}

void response_UNTAGGED_FETCH(mapping conn, bytes line)
{
	[int idx, array info] = parse_imap(conn, Stdio.Buffer("(" + line + ")"));
	mapping msg = (mapping)(info/2);
	if (!msg->UID)
	{
		//We've been sent some info without a UID in it.
		//This can't be in response to an actual request (we'll always ask
		//for the UID), so it most likely is a notification of changed flags.
		//Rather than maintain a list of UIDs in sequential order, we just
		//kick the request back to the server, asking for the UID too.
		//Possible traffic optimization: This is most likely to be in
		//response to another fetch (for the full body), which will have been
		//sent to us immediately prior. We could retain the idx and UID of
		//the one most recent untagged fetch, and assume that nothing's been
		//expunged in between.
		send(conn, sprintf("a fetch %d (UID%{ %s%})\r\n", idx, indices(msg)));
		return;
	}
	if (msg->ENVELOPE) msg->ENVELOPE = decode_all(msg->ENVELOPE);
	msg = (conn->message_cache[msg->UID] += msg);
	if (!msg->headers)
	{
		mapping hdr;
		if (string h = msg["RFC822"]) [hdr, msg->body] = MIME.parse_headers(h, UNDEFINED);
		else if (string h = msg["RFC822.HEADER"]) hdr = MIME.parse_headers(h, UNDEFINED)[0];
		else hdr = (["Headers": "not available"]);
		foreach ("from to subject"/" ", string h)
			if (hdr[h]) hdr[h] = MIME.decode_words_text_remapped(hdr[h]);
		msg->headers = hdr;
	}
	//Ideally, we'd like message IDs to be globally unique and perfectly stable.
	//If there's no Message-ID header, use the UID number - it's valid for this mailbox.
	//In theory, a server could mess us around by sending distinct messages with the
	//same ID. I don't know what the spec says about this, but it basically means a
	//broken server.
	msg->key = msg->headers["message-id"] || msg->UID;
	conn->message_cache[msg->key] = msg; //Allow lookups by message-id as well as UID
	mapping parent = 0;
	if (msg->headers->references)
		foreach (msg->headers->references/" ", string id)
			parent = conn->message_cache[id] || parent;
	G->G->window->update_message(msg, parent);
	if (m_delete(msg, "want_rfc822")) G->G->window->show_message(conn->addr, msg);
}

void response_folders(mapping conn, bytes line)
{
	if (!has_prefix(line, "OK")) return;
	multiset(string) folders = m_delete(conn, "folders");
	if (equal(folders, conn->last_folders)) return;
	G->G->window->update_folders(conn->addr, sort((array)folders));
}

void fetch_message(string addr, string key)
{
	mapping conn = connections[addr];
	if (!conn) return;
	//The message SHOULD be in the cache, and SHOULD have a UID set.
	mapping msg = conn->message_cache[key];
	if (!msg || !msg->UID) return; //If it doesn't, we might have moved folders.
	if (msg->RFC822) //Already in cache
	{
		G->G->window->show_message(addr, msg);
		//Fetching a message will normally mark it as \Seen.
		//Fetching from the cache doesn't, so we explicitly say so.
		if (!has_value(msg->FLAGS, "\\Seen"))
			send(conn, sprintf("a uid store %d +flags (\\Seen)\r\n", msg->UID));
		return;
	}
	msg->want_rfc822 = 1;
	send(conn, sprintf("a uid fetch %d (rfc822 envelope)\r\n", msg->UID));
}

void mark_unread(string addr, string key)
{
	mapping conn = connections[addr];
	if (!conn) return;
	//The message SHOULD be in the cache, and SHOULD have a UID set.
	mapping msg = conn->message_cache[key];
	if (!msg || !msg->UID) return; //If it doesn't, we might have moved folders.
	send(conn, sprintf("a uid store %d -flags (\\Seen)\r\n", msg->UID));
}

void response_move(mapping conn, bytes line)
{
	sscanf(line, "OK [COPYUID %d %d %d]", int destvalidity, int sourceuid, int destuid);
	if (!destuid) return;
	send(conn, sprintf("move2 uid store %d +flags.silent (\\Deleted)\r\nmove3 uid expunge %<d\r\n", sourceuid));
	response_fldselect(conn, ""); //TODO: Confirm that the message is gone, and then just remove it.
}

void move_message(string addr, string key, string dest)
{
	//This is looking like a standard preamble.
	mapping conn = connections[addr];
	if (!conn) return;
	//The message SHOULD be in the cache, and SHOULD have a UID set.
	mapping msg = conn->message_cache[key];
	if (!msg || !msg->UID) return; //If it doesn't, we might have moved folders.
	write("Move message %O to %O\n", msg->UID, dest);
	if (conn->caps->MOVE)
		//The "uid move" command isn't supported by all servers.
		send(conn, sprintf("mv uid move %d %s\r\n", msg->UID, dest));
	else if (conn->caps->UIDPLUS)
		//Nor is "uid copy" / "uid expunge", our next fallback.
		send(conn, sprintf("move uid copy %d %s\r\n", msg->UID, dest));
	else
		//TODO: Do this properly.
		werror("ERROR: Unimplemented [move w/o uidcopy]\n");
}

void response_UNTAGGED_OK(mapping conn, bytes line)
{
	if (sscanf(line, "[CAPABILITY%{ %[^] ]%}]", array(array(string)) caps))
		conn->caps = (multiset)caps[*][0];
}

//NOTE: Currently presumes ASCII for everything that matters.
//Binary data may be transmitted at various points (though it *should* be
//MIME-encoded or something), but I'm not going to deal with that yet.
void sockread(mapping conn, bytes data)
{
	conn->readbuffer += data;
	if (conn->string_literal_length)
	{
		if (conn->string_literal_length > sizeof(conn->readbuffer)) return; //Still don't have it all
		int length = m_delete(conn, "string_literal_length");
		conn->string_literals += ({conn->readbuffer[..length-1]});
		conn->readbuffer = m_delete(conn, "string_literal_line") + conn->readbuffer[length..];
	}
	while (sscanf(conn->readbuffer, "%s %s\n%s", ascii msg, bytes line, conn->readbuffer))
	{
		if (!line) break; //Unable to parse? Go back and wait for more from the socket.
		line = String.trim_all_whites(line); //Will trim off the \r that ought to end the line
		if (line == "") continue;
		if (line[-1] == '}')
		{
			//String literal. We don't properly parse everything, here; just stash it
			//into the connection mapping and plop in a magic marker of NUL. Since the
			//RFC strictly disallows NUL in transmission, this should be safe.
			int length = (int)(line/"{")[-1];
			if (length <= 0) continue; //Borked line??
			if (length >= 4294967296) {conn->sock->close(); return;} //Don't like the idea of loading up 4GB. Might change this later.
			line = (line/"{")[..<1] * "{" + "\0";
			if (sizeof(conn->readbuffer) >= length)
			{
				//We have the whole string already.
				conn->string_literals += ({conn->readbuffer[..length-1]});
				conn->readbuffer = msg + " " + line + conn->readbuffer[length..];
				continue;
			}
			else
			{
				//We don't have the whole string yet. Hold this line until we do.
				conn->string_literal_length = length;
				conn->string_literal_line = msg + " " + line;
				return;
			}
		}
		if (msg == "*")
		{
			array(string) words = line / " ";
			foreach (words; int i; string w) if (w != "" && w[0] >= 'A' && w[0] <= 'Z')
			{
				//The first alphabetic word is used as the message type.
				//Example: "* LIST (\HasNoChildren) ..." will be passed to UNTAGGED_LIST
				//Example: "* 1 FETCH (UID 23232 FLAGS (\Seen))" goes to UNTAGGED_FETCH
				words[i] = 0;
				msg = "UNTAGGED_" + w;
				line = words * " ";
				break;
			}
		}
		if (function resp = conn["response_" + msg] || this["response_" + msg]) resp(conn, line);
		else write(">>> [%s] %s\n", msg, line);
		m_delete(conn, "string_literals");
	}
}

//Clean up the socket connection; it's assumed to have already been closed.
void sockclosed(mapping conn)
{
	//TODO: Reconnect? Or at least show that the connection's broken.
	werror("DISCONNECTED\n");
	conn->sock=0; //Break refloop
}

//Write as much buffered socket data as possible
void sockwrite(mapping conn)
{
	if (conn->sock && conn->writeme!="") conn->writeme=conn->writeme[conn->sock->write(conn->writeme)..];
}

int send(mapping conn,string text)
{
	if (!conn) return 0;
	if (!conn->sock) return 0; //Discard text if we're not connected - no point keeping it all.
	if (text) conn->writeme += string_to_utf8(text);
	sockwrite(conn);
	return 1;
}

void complete_connection(string|Stdio.File|int(0..0) status, mapping conn)
{
	if (stringp(status)) return; //{werror("%%%%%% %s\n", status); return;}
	object est = m_delete(conn, "establish"); //De-floop. Whatever happens here, it's done and finished. No more resolving.
	if (!status)
	{
		if (!est->errno) werror("%%% Unable to resolve host name.\n");
		else werror("%%%%%% Error connecting to %s: %s [%d]\n", conn->worldname, strerror(est->errno), est->errno);
		return;
	}
	conn->sock = status;
	conn->sock->set_id(conn); //Refloop
	//Note: In setting the callbacks, use G->G->connection->x instead of just x, in case this is the old callback.
	//Not that that'll be likely - you'd have to "/update connection" while in the middle of establishing one -
	//but it's pretty cheap to do these lookups, and it'd be a nightmare to debug if it were ever wrong.
	conn->sock->set_nonblocking(G->G->connection->sockread, G->G->connection->sockwrite, G->G->connection->sockclosed);
	G->G->connection->sockread(conn, est->data_rcvd);
}

void connect()
{
	object window = G->G->window;
	if (!window) call_out(connect, 0.1); //Shouldn't happen. If we find ourselves racing, somehow, just delay startup a bit.
	mapping lose = connections - persist["accounts"];
	mapping gain = persist["accounts"] - connections;
	foreach (lose; string addr; mapping conn)
	{
		write("Disconnecting from %s\n", addr);
		m_delete(connections, addr);
		if (conn->socket) conn->socket->write("a logout\n");
		window->remove_account(addr);
	}
	foreach (gain; string addr; mapping info)
	{
		write("Connecting to %s\n", addr);
		mapping conn = connections[addr] = ([
			"addr": addr,
			"readbuffer": "",
			"writeme": sprintf("auth login %s %s\r\n", info->login, info->password),
		]);
		conn->establish = establish_connection(info->imap, 143, complete_connection, conn);
		window->add_account(addr);
	}
}

void smtpline(mapping info, bytes line)
{
	if (sscanf(line, "%d %s", int code, line) && code)
	{
		//Normal server message - status code plus human-readable
		switch (code)
		{
			case 220: //Initial greeting
			case 250: //Positive response
			case 354: //Socket to me
				info->sock->write(info->data[0]);
				info->data = info->data[1..];
				break;
			default: //Abort connection if we don't understand
				werror("UNKNOWN SMTP RESPONSE\n%d %s\n", code, line);
			case 554: //Abort also on error
				info->sock->write("quit\r\n");
			case 221: //OK, bye [0:08:53]
				m_delete(persist["sendme"], info->msgid);
				persist->save();
				break;
		}
	}
	//else it's a different sort of line (what, I'm not sure)
}

//Should this lot be packaged up into a coherent Hogan-like interface to a line-based socket??
void smtpread(mapping conn, bytes data)
{
	conn->readbuffer += data;
	while (sscanf(conn->readbuffer, "%s\n%s", bytes line, conn->readbuffer))
		smtpline(conn, line - "\r");
}

void deliver_message(string|Stdio.File|int(0..0) status, mapping info)
{
	if (!objectp(status)) return;
	info->sock = status;
	status->set_id(info);
	info->data = ({
		sprintf("helo %s\r\n", gethostname() || "zawinski"),
		sprintf("mail from:%s\r\n", persist["accounts"][info->addr]->from),
		}) + sprintf("rcpt to:%s\r\n", info->recipients[*]) + ({
		"data\r\n",
		info->body + "\r\n.\r\n", //NOTE: Could be huge. Might end up blocking.
		"quit\r\n"
	});
	status->set_nonblocking(G->G->connection->smtpread, G->G->connection->smtpwrite, 0);
}

void send_message(string addr, string msgid, string body, array(string) recipients)
{
	//TODO: Use 587 if available
	//Currently assumes the SMTP server is the IMAP server.
	mapping info = (["addr": addr, "msgid": msgid, "body": body, "recipients": recipients, "readbuffer": "", "writebuffer": ""]);
	if (!mappingp(persist["sendme"])) persist["sendme"] = ([]);
	persist["sendme"][msgid] = ({addr, body, recipients}); //TODO: Retrieve these on startup and autosend
	persist->save();
	//TODO: Should the message be stored in the sent box before or after attempting SMTP delivery??
	//Probably before.... I think.
	establish_connection(persist["accounts"][addr]->imap, 25, deliver_message, info);
}

void create()
{
	if (G->G->connection) connections = G->G->connection->connections;
	G->G->connection = this;
	call_out(connect, 0);
}
