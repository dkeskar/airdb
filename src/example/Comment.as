package example
{
	import com.memamsa.airdb.DB;
	import com.memamsa.airdb.Migrator;
	import com.memamsa.airdb.Modeler;

 	[Association(type="belongs_to", name="parent", className="example.Comment")]
	[Association(type="has_many", name="comments", className="example.Comment")]  
	
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
				},
				// self-referential item relationships are possible
				function(my:Migrator):void {
					my.column('comment_id',DB.Field.Integer, {'default': 0});
				}
			]
		);
		// other class methods and properties
	}
}