package com.memamsa.airdb
{
  /**
  * The <code>SchemaInfo</code> model maintains schema version information for 
  * all the other models. 
  * 
  * <p>Uses <code>Modeler</code> query and update methods to create and track 
  * migration versions for all <code>Modeler</code> sub-classes within the 
  * application.</p>
  * 
  * <p>The schema for the <code>SchemaInfo</code> class consists of a simple 
  * property-value format, where
  * <pre>
  * property => name of the table
  * value => current schema version for that table
  * </pre>
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