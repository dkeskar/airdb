package com.memamsa.airdb
{
  /** 
  * IMigratable interface specifies the methods which a migratable
  * object must implement. 
  * 
  * The DB invokes these IMigratable methods to ensure schema migration.
  * 
  **/
	public interface IMigratable
	{
	  // Return the table name 
		function get storeName():String;
		
		// Runs specified migration directives. 
		// Migrations are numbered from zero. 
		// If the toVer is unspecified (0), all migrations are run.
		// Returns a number indicating the total migration directives applied, 
		// which forms the basis, if necessary, for next version to start from.
		function migrate(fromVer:uint=0, toVer:uint=0):uint;
	}
}