package example
{
	import com.memamsa.airdb.DB;
	import com.memamsa.airdb.Migrator;
	import com.memamsa.airdb.Modeler;
	import com.memamsa.airdb.Relater;

	public dynamic class Person extends Modeler
	{
		private static const migrations:Array = [
			function(my:Migrator):void {
				my.column('name', DB.Field.VarChar, {limit: 64});
				my.column('age', DB.Field.Integer);
				my.column('city', DB.Field.VarChar, {limit: 32});
				my.createTable();
			}
		];
		private static const schema:Migrator = new Migrator(Person, 
			{id: true}, migrations);
		
		private static const relations:Relater = new Relater(Person, 
			function(me:Relater):void {
				me.hasMany('friendships', {foreign_key: 'from_id', 
					class_name: 'example.Relationship'});
				me.hasMany('friends', {through: 'friendships', foreign_key: 'to_id', 
					class_name: 'example.Person'});
			});
		
	}
}