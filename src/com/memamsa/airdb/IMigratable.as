package com.memamsa.airdb
{
	public interface IMigratable
	{
		function get storeName():String;
		function migrate(fromVer:uint=0, toVer:uint=0):uint;
	}
}