package example
{
	import com.memamsa.airdb.DB;
	import com.memamsa.airdb.Migrator;
	import com.memamsa.airdb.Modeler;
	import com.memamsa.airdb.Relater;

	public dynamic class Relationship extends Modeler
	{
		private static const migrations:Array = [
			function(my:Migrator):void {
				my.column('from_id', DB.Field.Integer);
				my.column('to_id', DB.Field.Integer);
				my.column('descr', DB.Field.VarChar, {limit: 255});
				my.createTable();
			}
		];
		private static const schema:Migrator = new Migrator(Relationship, 
			{id: true}, migrations);
		
		private static const relations:Relater = new Relater(Relationship, 
			function(me:Relater):void {
				me.belongsTo('initiator', {foreign_key: 'from_id', class_name: 'example.Person'});
				me.belongsTo('receptor', {foreign_key: 'to_id', class_name: 'example.Person'});
			});
			
		public static function make(initiator:Person, receptor:Person, descr:String):Relationship {
			var keyvals:Object = {from_id: initiator.id, to_id: receptor.id}; 			
			var rel:Relationship = Modeler.findery(Relationship, keyvals) as Relationship;
			if (!rel) {
				rel = new Relationship();
				rel.data(keyvals);
			}
			rel.descr = descr;
			rel.save();
			return rel;			
		} 
	}
}