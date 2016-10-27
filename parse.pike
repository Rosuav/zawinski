//Instead of processing entities at the top level, it's simpler
//to process them separately, on data-only sections.
Parser.HTML entities = Parser.HTML()->add_entities(Parser.html_entities);;

multiset(string) attributes = (<>);

mixed attribute(object p, mapping attrs, string tag)
{
	write("tag %s: %O\n", tag, attrs);
	if (tag[0] == '/') attributes[tag[1..]] = 0;
	else attributes[tag] = 1;
	return ({ });
}

mixed data(object p, string txt)
{
	txt = String.trim_all_whites(entities->feed(txt)->read());
	if (txt != "") write("[%{%s %}] %s\n", (array)attributes, string_to_utf8(txt));
	return ({ });
}

int main()
{
	object p = Parser.HTML();
	array containers = "a b i"/" ";
	foreach (containers, string tag)
	{
		p->add_tag(tag, ({attribute, tag}));
		p->add_tag("/"+tag, ({attribute, "/"+tag}));
	}
	p->_set_data_callback(data);
	p->finish(utf8_to_string(Stdio.read_file("HTML")));
}
