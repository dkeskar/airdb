package com.memamsa.airdb
{
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