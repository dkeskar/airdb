package com.memamsa.airdb
{
  /**
  * Model to hold and query schema version information for all the other
  * models created and tracked by AirDB within the application. 
  * Schema Version information is stored in property-value format, where
  * property => name of the table
  * value => current schema version for that table
  **/
	dynamic public class SchemaInfo extends Modeler
	{
		private static var migrations:Migrator = new Migrator(
		  SchemaInfo,
			{id: true}, 
			[
				function(my:Migrator):void {
					my.createTable(function():void {
						my.column('property', DB.Field.VarChar, {limit: 32});
						my.column('value', DB.Field.Integer, {'default': 0});
					});
				}
			]
		);
		public function SchemaInfo(newrow:Object=null)
		{
			data(newrow);  
		}
	}
}