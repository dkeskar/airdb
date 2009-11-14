package example
{
	import com.memamsa.airdb.DB;
	import com.memamsa.airdb.Migrator;
	import com.memamsa.airdb.Modeler;
  
	dynamic public class Comment extends Modeler
	{
		private static const migrations:Migrator = new Migrator(
			Comment, 
			{id: true},
			[
				function(my:Migrator):void {
					my.createTable(function():void {
					my.column('title', DB.Field.VarChar, {limit: 128});
					my.column('author', DB.Field.VarChar, {limit: 40});
					my.columnTimestamps();  				
				});
			}
			]
		);
		// other class methods and properties
	}
}