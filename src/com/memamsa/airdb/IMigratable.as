package com.memamsa.airdb
{
  /** 
  * IMigratable methods must be implemented by a migratable object. 
  * 
  * The DB invokes these IMigratable methods to ensure schema migration.
  **/
	public interface IMigratable
	{
	  /**
	  * Return the table name 
	  **/
		function get storeName():String;
		
		/**
    * Run the necessary migration directives to bring the schema for the
    * corresponding database table up-to-date. The N migration directives
    * specified during instantiation of this <code>Migrator</code> are
    * numbered as versions from 0 to N-1
    * 
    * @param fromVer Starting schema version for this table. 
    * @default 0, begin from the first directive.
    * 
    * @param toVer Desired ending version for the schema. 
    * @default 0, in which case all directives upto the last are applied.
    * 
    * @return The final schema version after necessary migration directives
    * have been applied. This forms the starting version, if necessary, for 
    * the next set of migrations.
    * 
  	* @see Migrator
  	* @see DB#migrate
    * 
    **/    
		function migrate(fromVer:uint=0, toVer:uint=0):uint;
	}
}