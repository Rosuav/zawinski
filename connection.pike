mapping(string:mixed) connections = ([]);

void connect()
{
	mapping lose = connections - persist["accounts"];
	mapping gain = persist["accounts"] - connections;
	foreach (lose; string addr; mapping conn)
	{
		write("Disconnecting from %s\n", addr);
		m_delete(connections, addr);
	}
	foreach (gain; string addr; mapping info)
	{
		write("Connecting to %s\n", addr);
		connections[addr] = ([]);
	}
}

void create()
{
	if (G->G->connection) connections = G->G->connection->connections;
	G->G->connection = this;
	call_out(connect, 0);
}
